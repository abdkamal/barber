import { Body, Controller, Get, HttpCode, Param, ParseUUIDPipe, Post, Put, Req } from '@nestjs/common';
import type { Request } from 'express';
import { z } from 'zod';
import { Roles } from '../auth/auth.decorators';
import type { Principal } from '../auth/principal';
import { SessionsRepo } from '../auth/sessions';
import { normalizePhone } from '../common/normalize';
import { CustomersRepo } from '../customers/customers.repository';
import { isUniqueViolation } from '../db/sql';
import { PHONE_DISPUTES_SQL } from './reports.repository';
import { Errors } from '../common/errors';
import { ZodPipe } from '../common/zod.pipe';
import { writeAudit } from '../security/audit';
import { clientIp } from '../security/client-ip';
import type { TenantContext, TenantQueryable } from '../tenancy/tenant-context';
import { CurrentPrincipal, Tenant } from '../tenancy/tenant.decorator';

const LinkWalkIn = z.object({ walkInId: z.string().uuid() }).strict();
const PhoneBody = z.object({ phone: z.string().min(1).max(32) }).strict();
const uuid = new ParseUUIDPipe({ version: '4', exceptionFactory: () => Errors.notFound() });

/**
 * Manual walk-in linking and phone-number dispute resolution (ق20). Auto-linking on registration
 * (when account approval is enabled) is handled by the auth module; this covers the manager's
 * manual fallback and the dispute screen — same underlying action: point an app account at the
 * walk-in record that is really the same person.
 */
async function doLink(q: TenantQueryable, accountId: string, walkInId: string) {
  const account = await CustomersRepo.findAccountById(q, accountId);
  if (!account) throw Errors.notFound();
  const { rows } = await q.query<{ id: string; phone: string; password_hash: string | null; linked: boolean }>(
    `SELECT c.id, c.phone, c.password_hash, EXISTS(SELECT 1 FROM customers a WHERE a.linked_walk_in_id = c.id) AS linked
       FROM customers c WHERE c.id = $1`,
    [walkInId],
  );
  const walkIn = rows[0];
  if (!walkIn || walkIn.password_hash !== null) throw Errors.validation([{ path: 'walkInId', code: 'not_a_walk_in' }]);
  if (walkIn.linked) throw Errors.conflict('WALK_IN_ALREADY_LINKED', 'هذا السجل مرتبط بحساب آخر بالفعل');
  if (walkIn.phone !== account.phone) throw Errors.conflict('PHONE_MISMATCH', 'رقم هاتف السجل الحاضر لا يطابق رقم هاتف الحساب');
  await q.query('UPDATE customers SET linked_walk_in_id = $2, proposed_walk_in_id = NULL, updated_at = now() WHERE id = $1', [accountId, walkInId]);
}

@Controller('manager')
@Roles('manager')
export class CustomerAdminController {
  /** Direct link: the manager already knows which walk-in record belongs to this account. */
  @Post('customers/:id/link-walkin')
  @HttpCode(200)
  async linkWalkIn(@Tenant() t: TenantContext, @CurrentPrincipal() me: Principal, @Param('id', uuid) id: string, @Body(new ZodPipe(LinkWalkIn)) body: z.infer<typeof LinkWalkIn>, @Req() req: Request) {
    return t.db.tx(async (q) => {
      await doLink(q, id, body.walkInId);
      await writeAudit(q, {
        actorKind: 'staff', actorId: me.subjectId, action: 'customer.walkin_linked', targetKind: 'customer', targetId: id,
        ip: clientIp(req), details: { walkInId: body.walkInId },
      });
      return { ok: true };
    });
  }

  /** Review H2: undoes a link (or a pending proposal) — the walk-in history is no longer the account's. */
  @Post('customers/:id/unlink-walkin')
  @HttpCode(200)
  async unlinkWalkIn(@Tenant() t: TenantContext, @CurrentPrincipal() me: Principal, @Param('id', uuid) id: string, @Req() req: Request) {
    return t.db.tx(async (q) => {
      const account = await CustomersRepo.findAccountById(q, id);
      if (!account) throw Errors.notFound();
      await q.query('UPDATE customers SET linked_walk_in_id = NULL, proposed_walk_in_id = NULL, updated_at = now() WHERE id = $1', [id]);
      await writeAudit(q, {
        actorKind: 'staff', actorId: me.subjectId, action: 'customer.walkin_unlinked', targetKind: 'customer', targetId: id,
        ip: clientIp(req), details: { walkInId: account.linked_walk_in_id, proposedWalkInId: account.proposed_walk_in_id },
      });
      return { ok: true };
    });
  }

  /**
   * Review H2 (ق20 «إعادة إسناده»): gives an account a different phone number (the manager checked it
   * in person). Any link/proposal to walk-in records of the old number is dropped.
   */
  @Put('customers/:id/phone')
  async reassignPhone(@Tenant() t: TenantContext, @CurrentPrincipal() me: Principal, @Param('id', uuid) id: string, @Body(new ZodPipe(PhoneBody)) body: z.infer<typeof PhoneBody>, @Req() req: Request) {
    const phone = normalizePhone(body.phone);
    if (!phone) throw Errors.validation([{ path: 'phone', code: 'invalid_phone' }]);
    try {
      return await t.db.tx(async (q) => {
        const account = await CustomersRepo.findAccountById(q, id);
        if (!account) throw Errors.notFound();
        const holder = await CustomersRepo.findAccountByPhone(q, phone);
        if (holder && holder.id !== id) throw Errors.conflict('PHONE_IN_USE', 'هذا الرقم مستخدم في حساب آخر — أفرج عنه أولًا');
        await q.query(
          `UPDATE customers SET phone = $2, phone_released_at = NULL, linked_walk_in_id = NULL, proposed_walk_in_id = NULL,
                  token_version = token_version + 1, updated_at = now() WHERE id = $1`,
          [id, phone],
        );
        await SessionsRepo.revokeAllFor(q, 'customer', id, 'phone_changed');
        await writeAudit(q, {
          actorKind: 'staff', actorId: me.subjectId, action: 'customer.phone_reassigned', targetKind: 'customer', targetId: id,
          ip: clientIp(req), details: { from: account.phone, to: phone },
        });
        return CustomersRepo.findPublicById(q, id);
      });
    } catch (e) {
      if (isUniqueViolation(e, 'customers_account_phone_key')) throw Errors.conflict('PHONE_IN_USE', 'هذا الرقم مستخدم في حساب آخر — أفرج عنه أولًا');
      throw e;
    }
  }

  /**
   * Review H2: releases an account's phone number (e.g. someone registered with another person's
   * number): the account is suspended, its sessions revoked, links dropped, and the number is free
   * for its real owner to register. Audited.
   */
  @Post('customers/:id/release-phone')
  @HttpCode(200)
  async releasePhone(@Tenant() t: TenantContext, @CurrentPrincipal() me: Principal, @Param('id', uuid) id: string, @Req() req: Request) {
    return t.db.tx(async (q) => {
      const account = await CustomersRepo.findAccountById(q, id);
      if (!account) throw Errors.notFound();
      await q.query(
        `UPDATE customers SET phone_released_at = COALESCE(phone_released_at, now()), status = 'suspended',
                linked_walk_in_id = NULL, proposed_walk_in_id = NULL, token_version = token_version + 1, updated_at = now()
          WHERE id = $1`,
        [id],
      );
      await SessionsRepo.revokeAllFor(q, 'customer', id, 'phone_released');
      await writeAudit(q, {
        actorKind: 'staff', actorId: me.subjectId, action: 'customer.phone_released', targetKind: 'customer', targetId: id,
        ip: clientIp(req), details: { phone: account.phone, from: account.status },
      });
      return { ok: true };
    });
  }

  /**
   * Numbers needing a decision (ق20, review H2): ≥ 2 unlinked walk-in records, or a pending/suspended
   * account holding a number used by walk-in records.
   */
  @Get('phone-disputes')
  async listDisputes(@Tenant() t: TenantContext) {
    const { rows } = await t.db.query<{
      phone: string;
      account_id: string | null;
      account_status: string | null;
      linked_walk_in_id: string | null;
      proposed_walk_in_id: string | null;
      walk_ins: { id: string; name: string; createdAt: Date }[];
    }>(
      `SELECT g.phone, a.id AS account_id, a.status AS account_status, a.linked_walk_in_id, a.proposed_walk_in_id,
              (SELECT json_agg(json_build_object('id', w.id, 'name', w.name, 'createdAt', w.created_at) ORDER BY w.created_at)
                 FROM customers w WHERE w.phone = g.phone AND w.password_hash IS NULL
                   AND NOT EXISTS (SELECT 1 FROM customers a2 WHERE a2.linked_walk_in_id = w.id AND a2.status = 'active')) AS walk_ins
         FROM (${PHONE_DISPUTES_SQL}) g
         LEFT JOIN customers a ON a.phone = g.phone AND a.password_hash IS NOT NULL AND a.phone_released_at IS NULL
        ORDER BY g.phone`,
    );
    return rows.map((r) => ({
      phone: r.phone,
      accountId: r.account_id,
      accountStatus: r.account_status,
      linkedWalkInId: r.linked_walk_in_id,
      proposedWalkInId: r.proposed_walk_in_id,
      walkIns: r.walk_ins ?? [],
    }));
  }

  /** Resolves a dispute by linking the chosen walk-in record to the account sharing that phone. */
  @Post('phone-disputes/:accountId/resolve')
  @HttpCode(200)
  async resolveDispute(@Tenant() t: TenantContext, @CurrentPrincipal() me: Principal, @Param('accountId', uuid) accountId: string, @Body(new ZodPipe(LinkWalkIn)) body: z.infer<typeof LinkWalkIn>, @Req() req: Request) {
    return t.db.tx(async (q) => {
      await doLink(q, accountId, body.walkInId);
      await writeAudit(q, {
        actorKind: 'staff', actorId: me.subjectId, action: 'customer.phone_dispute_resolved', targetKind: 'customer', targetId: accountId,
        ip: clientIp(req), details: { walkInId: body.walkInId },
      });
      return { ok: true };
    });
  }
}

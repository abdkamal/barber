import { Body, Controller, Get, HttpCode, Param, ParseUUIDPipe, Post, Req } from '@nestjs/common';
import type { Request } from 'express';
import { z } from 'zod';
import { Roles } from '../auth/auth.decorators';
import type { Principal } from '../auth/principal';
import { CustomersRepo } from '../customers/customers.repository';
import { Errors } from '../common/errors';
import { ZodPipe } from '../common/zod.pipe';
import { writeAudit } from '../security/audit';
import { clientIp } from '../security/client-ip';
import type { TenantContext, TenantQueryable } from '../tenancy/tenant-context';
import { CurrentPrincipal, Tenant } from '../tenancy/tenant.decorator';

const LinkWalkIn = z.object({ walkInId: z.string().uuid() }).strict();
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
  await q.query('UPDATE customers SET linked_walk_in_id = $2, updated_at = now() WHERE id = $1', [accountId, walkInId]);
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

  /** Phone numbers with more than one unlinked walk-in record — ambiguous, needs a manual pick (ق20). */
  @Get('phone-disputes')
  async listDisputes(@Tenant() t: TenantContext) {
    const { rows } = await t.db.query<{ phone: string; account_id: string | null; walk_ins: { id: string; name: string; createdAt: Date }[] }>(
      `SELECT g.phone,
              (SELECT a.id FROM customers a WHERE a.phone = g.phone AND a.password_hash IS NOT NULL) AS account_id,
              (SELECT json_agg(json_build_object('id', w.id, 'name', w.name, 'createdAt', w.created_at) ORDER BY w.created_at)
                 FROM customers w WHERE w.phone = g.phone AND w.password_hash IS NULL
                   AND NOT EXISTS (SELECT 1 FROM customers a2 WHERE a2.linked_walk_in_id = w.id)) AS walk_ins
         FROM (SELECT phone FROM customers WHERE password_hash IS NULL GROUP BY phone HAVING count(*) > 1) g`,
    );
    return rows.map((r) => ({ phone: r.phone, accountId: r.account_id, walkIns: r.walk_ins ?? [] }));
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

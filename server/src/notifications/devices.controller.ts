import { Body, Controller, HttpCode, Post } from '@nestjs/common';
import { z } from 'zod';
import { type Principal, subjectKindOf } from '../auth/principal';
import { ZodPipe } from '../common/zod.pipe';
import type { TenantContext } from '../tenancy/tenant-context';
import { CurrentPrincipal, Tenant } from '../tenancy/tenant.decorator';

const DeviceBody = z
  .object({
    fcmToken: z.string().min(10).max(4096),
    notificationsAllowed: z.boolean(),
    hasPlayServices: z.boolean(),
  })
  .strict();

/**
 * Registers the FCM token of the signed-in device (any role: customers get booking notices,
 * barbers the overrun reminder, managers alerts). One device per session; a token moves to the
 * latest account that registers it.
 */
@Controller('devices')
export class DevicesController {
  @Post()
  @HttpCode(200)
  async register(@Tenant() t: TenantContext, @CurrentPrincipal() me: Principal, @Body(new ZodPipe(DeviceBody)) body: z.infer<typeof DeviceBody>) {
    const kind = subjectKindOf(me.role);
    return t.db.tx(async (q) => {
      const { rows } = await q.query<{ id: string }>(
        `INSERT INTO devices (owner_kind, owner_id, fcm_token, notifications_allowed, has_play_services, last_seen_at)
         VALUES ($1, $2, $3, $4, $5, now())
         ON CONFLICT (fcm_token) WHERE fcm_token IS NOT NULL DO UPDATE
           SET owner_kind = EXCLUDED.owner_kind, owner_id = EXCLUDED.owner_id,
               notifications_allowed = EXCLUDED.notifications_allowed, has_play_services = EXCLUDED.has_play_services,
               last_seen_at = now(), updated_at = now()
         RETURNING id`,
        [kind, me.subjectId, body.fcmToken, body.notificationsAllowed, body.hasPlayServices],
      );
      const id = rows[0]!.id;
      // The session's previous token (rotated by FCM) must not receive pushes any more.
      await q.query(
        `UPDATE devices SET fcm_token = NULL, updated_at = now()
          WHERE id = (SELECT device_id FROM sessions WHERE id = $1) AND id <> $2`,
        [me.sessionId, id],
      );
      await q.query('UPDATE sessions SET device_id = $2 WHERE id = $1', [me.sessionId, id]);
      return { id, notificationsAllowed: body.notificationsAllowed };
    });
  }
}

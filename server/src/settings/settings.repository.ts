import type { TenantQueryable } from '../tenancy/tenant-context';

export interface SettingsRow {
  require_account_approval: boolean;
  max_active_bookings_per_customer: number;
  booking_opens_before_minutes: number;
  eta_change_notify_minutes: number;
  max_disconnect_window_minutes: number;
  gap_margin_min_minutes: number;
  gap_margin_percent: number;
  offer_hold_minutes: number;
  barber_not_connected_alert_minutes: number;
  overrun_alert_percent: number;
  updated_at: Date;
}

/** API field name → column. Only these can be changed by a manager. */
export const SETTINGS_FIELDS = {
  requireAccountApproval: 'require_account_approval',
  maxActiveBookingsPerCustomer: 'max_active_bookings_per_customer',
  bookingOpensBeforeMinutes: 'booking_opens_before_minutes',
  etaChangeNotifyMinutes: 'eta_change_notify_minutes',
  maxDisconnectWindowMinutes: 'max_disconnect_window_minutes',
  gapMarginMinMinutes: 'gap_margin_min_minutes',
  gapMarginPercent: 'gap_margin_percent',
  offerHoldMinutes: 'offer_hold_minutes',
  barberNotConnectedAlertMinutes: 'barber_not_connected_alert_minutes',
  overrunAlertPercent: 'overrun_alert_percent',
} as const;

export type SettingsDto = { [K in keyof typeof SETTINGS_FIELDS]: SettingsRow[(typeof SETTINGS_FIELDS)[K]] };

export function toSettingsDto(r: SettingsRow): SettingsDto {
  const out = {} as Record<string, unknown>;
  for (const [k, col] of Object.entries(SETTINGS_FIELDS)) out[k] = r[col];
  return out as SettingsDto;
}

export const SettingsRepo = {
  async get(q: TenantQueryable): Promise<SettingsRow> {
    const { rows } = await q.query<SettingsRow>('SELECT * FROM settings WHERE id = 1');
    return rows[0]!;
  },

  async update(q: TenantQueryable, patch: Partial<SettingsDto>): Promise<SettingsRow> {
    const sets: string[] = [];
    const params: unknown[] = [];
    for (const [k, v] of Object.entries(patch)) {
      const col = SETTINGS_FIELDS[k as keyof typeof SETTINGS_FIELDS];
      if (!col || v === undefined) continue;
      params.push(v);
      sets.push(`${col} = $${params.length}`); // column names come from the fixed whitelist above
    }
    if (!sets.length) return this.get(q);
    const { rows } = await q.query<SettingsRow>(
      `UPDATE settings SET ${sets.join(', ')}, updated_at = now() WHERE id = 1 RETURNING *`,
      params,
    );
    return rows[0]!;
  },
};

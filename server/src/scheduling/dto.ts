import type { ProjectedSlot } from '@saloni/engine';
import type { TenantQueryable } from '../tenancy/tenant-context';
import { reasonText } from './reasons';
import { type BookingRow, type BookingServiceRow, bookingServices } from './rows';

const iso = (d: Date | number | null | undefined): string | null =>
  d === null || d === undefined ? null : new Date(d).toISOString();

/**
 * Booking as sent to both apps — the fields of Dart `Booking` (packages/saloni_api) plus extras
 * the apps may use (names, services with prices, current projection).
 */
export interface BookingDto {
  id: string;
  customerId: string;
  barberId: string;
  serviceIds: string[];
  kind: 'queue' | 'requested';
  requestedAt: string | null;
  status: string;
  queuePosition: number | null;
  originalEta: string;
  lastShownEta: string | null;
  postponementUsed: boolean;
  actualStart: string | null;
  actualEnd: string | null;
  source: 'app' | 'barber';
  walkIn: boolean;
  createdAt: string;
  // extras
  workDate: string;
  customerName: string;
  services: Array<{ id: string; name: string; priceCents: number; baseDurationMin: number }>;
  priceCents: number;
  estimatedDurationMin: number | null;
  eta: string | null;
  etaEnd: string | null;
  calledAt: string | null;
  offerExpiresAt: string | null;
  lastChangeReason: string | null;
  serveLate: boolean;
  needsReview: boolean;
}

export function toBookingDto(r: BookingRow, services: BookingServiceRow[], slot?: ProjectedSlot | null, opts: { includePhone?: boolean } = {}): BookingDto & { customerPhone?: string } {
  const eta = slot ? slot.start : r.actual_start?.getTime() ?? r.projected_start?.getTime() ?? null;
  const etaEnd = slot ? slot.end : r.projected_end?.getTime() ?? null;
  return {
    id: r.id,
    customerId: r.customer_id,
    barberId: r.staff_id,
    serviceIds: services.map((s) => s.service_id),
    kind: r.kind,
    requestedAt: iso(r.requested_at),
    status: r.status,
    queuePosition: r.queue_position,
    originalEta: iso(r.original_expected_start ?? r.projected_start ?? r.created_at)!,
    lastShownEta: iso(r.last_shown_expected_start),
    postponementUsed: r.postpone_used,
    actualStart: iso(r.actual_start),
    actualEnd: iso(r.actual_end),
    source: r.source,
    walkIn: r.source === 'barber',
    createdAt: iso(r.created_at)!,
    workDate: r.work_date,
    customerName: r.customer_name,
    ...(opts.includePhone ? { customerPhone: r.customer_phone } : {}),
    services: services.map((s) => ({
      id: s.service_id,
      name: s.name_snapshot,
      priceCents: Number(s.price_minor),
      baseDurationMin: s.duration_minutes_snapshot,
    })),
    priceCents: services.reduce((a, s) => a + Number(s.price_minor), 0),
    estimatedDurationMin: r.estimated_duration_seconds ? Math.round(r.estimated_duration_seconds / 60) : null,
    eta: iso(eta),
    etaEnd: iso(etaEnd),
    calledAt: iso(r.called_at),
    offerExpiresAt: r.status === 'offered' ? iso(r.offer_expires_at) : null,
    lastChangeReason: reasonText(r.last_change_reason),
    serveLate: r.serve_late,
    needsReview: r.needs_review,
  };
}

export async function bookingDtos(
  q: TenantQueryable,
  rows: BookingRow[],
  slots?: Map<string, ProjectedSlot>,
  opts: { includePhone?: boolean } = {},
): Promise<BookingDto[]> {
  const svc = await bookingServices(q, rows.map((r) => r.id));
  return rows.map((r) => toBookingDto(r, svc.get(r.id) ?? [], slots?.get(r.id) ?? null, opts));
}

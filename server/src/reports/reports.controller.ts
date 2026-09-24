import { Controller, Get, Query } from '@nestjs/common';
import { z } from 'zod';
import { Roles } from '../auth/auth.decorators';
import { Errors } from '../common/errors';
import { ZodPipe } from '../common/zod.pipe';
import type { TenantContext } from '../tenancy/tenant-context';
import { Tenant } from '../tenancy/tenant.decorator';
import { ReportsRepo } from './reports.repository';

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const Query_ = z
  .object({
    from: z.string().regex(DATE_RE, 'invalid_date'),
    to: z.string().regex(DATE_RE, 'invalid_date'),
  })
  .strict()
  .refine((q) => q.from <= q.to, { message: 'from must not be after to', path: ['from'] });

/** Manager reports for a date range (design §9): revenue, visits, services, ETA accuracy, peak hours, pending items. */
@Controller('manager/reports')
@Roles('manager')
export class ReportsController {
  @Get()
  async get(@Tenant() t: TenantContext, @Query(new ZodPipe(Query_)) query: z.infer<typeof Query_>) {
    // A generous but finite window keeps ad-hoc "custom" ranges from becoming an unbounded scan.
    const days = (Date.parse(query.to) - Date.parse(query.from)) / 86_400_000;
    if (days > 366) throw Errors.validation([{ path: 'to', code: 'range_too_large' }]);
    const range = { from: query.from, to: query.to };

    const [revenue, visits, postponements, topServices, durationVsBase, etaAccuracy, peakHours, pendingItems] = await Promise.all([
      ReportsRepo.revenue(t.db, range),
      ReportsRepo.visits(t.db, range),
      ReportsRepo.postponements(t.db, range),
      ReportsRepo.topServices(t.db, range),
      ReportsRepo.durationVsBase(t.db, range),
      ReportsRepo.etaAccuracy(t.db, range),
      ReportsRepo.peakHours(t.db, range, t.salon.timezone),
      ReportsRepo.pendingItems(t.db),
    ]);

    const revenueTotal = revenue.reduce(
      (a, r) => ({
        confirmed: a.confirmed + r.confirmed,
        expectedConfirmed: a.expectedConfirmed + r.expectedConfirmed,
        awaiting: a.awaiting + r.awaiting,
        discrepancies: a.discrepancies + r.discrepancies,
      }),
      { confirmed: 0, expectedConfirmed: 0, awaiting: 0, discrepancies: 0 },
    );
    const visitsWithPostpone = visits.map((v) => ({ ...v, postponed: postponements.get(v.staffId) ?? 0 }));

    return {
      range,
      revenue: { perBarber: revenue, total: revenueTotal },
      visits: visitsWithPostpone,
      topServices,
      durationVsBase,
      etaAccuracy,
      peakHours,
      pendingItems,
    };
  }
}

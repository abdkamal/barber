import type { Request } from 'express';
import type { TenantContext } from '../tenancy/tenant-context';

export type Role = 'customer' | 'barber' | 'manager';
export type SubjectKind = 'staff' | 'customer';

export interface Principal {
  salonId: string;
  subjectId: string;
  role: Role;
  sessionId: string;
  /** Only for customers: pending | active (suspended accounts never authenticate). */
  customerStatus?: 'pending' | 'active';
}

export interface AuthenticatedRequest extends Request {
  tenant?: TenantContext;
  principal?: Principal;
}

export function subjectKindOf(role: Role): SubjectKind {
  return role === 'customer' ? 'customer' : 'staff';
}

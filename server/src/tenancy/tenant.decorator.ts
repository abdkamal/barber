import { createParamDecorator, ExecutionContext } from '@nestjs/common';
import type { TenantContext } from './tenant-context';
import type { AuthenticatedRequest, Principal } from '../auth/principal';

/**
 * Injects the TenantContext established by AuthGuard from the verified access token.
 * Fails closed (500) if used on a route where no authenticated tenant exists.
 */
export const Tenant = createParamDecorator((_: unknown, ctx: ExecutionContext): TenantContext => {
  const req = ctx.switchToHttp().getRequest<AuthenticatedRequest>();
  if (!req.tenant) throw new Error('No tenant bound to this request (route must be authenticated)');
  return req.tenant;
});

export const CurrentPrincipal = createParamDecorator((_: unknown, ctx: ExecutionContext): Principal => {
  const req = ctx.switchToHttp().getRequest<AuthenticatedRequest>();
  if (!req.principal) throw new Error('No principal bound to this request');
  return req.principal;
});

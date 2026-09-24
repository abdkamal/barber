import { CanActivate, ExecutionContext, Injectable } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { Errors } from '../common/errors';
import { IS_PUBLIC_KEY, ROLES_KEY } from './auth.decorators';
import { AuthService } from './auth.service';
import type { AuthenticatedRequest, Role } from './principal';

/**
 * Global guard: every route is authenticated unless marked @Public().
 * The tenant is taken ONLY from the verified access token — headers, query and body are never
 * consulted for the salon identity. Role restrictions (@Roles) are enforced here too.
 */
@Injectable()
export class AuthGuard implements CanActivate {
  constructor(
    private readonly reflector: Reflector,
    private readonly auth: AuthService,
  ) {}

  async canActivate(ctx: ExecutionContext): Promise<boolean> {
    const targets = [ctx.getHandler(), ctx.getClass()];
    if (this.reflector.getAllAndOverride<boolean>(IS_PUBLIC_KEY, targets)) return true;

    const req = ctx.switchToHttp().getRequest<AuthenticatedRequest>();
    const header = req.headers.authorization;
    const m = typeof header === 'string' ? /^Bearer ([A-Za-z0-9._~+/=-]+)$/.exec(header) : null;
    if (!m) throw Errors.unauthenticated();
    const result = await this.auth.authenticate(m[1]!);
    if (!result) throw Errors.unauthenticated();
    req.tenant = result.tenant;
    req.principal = result.principal;

    const roles = this.reflector.getAllAndOverride<Role[] | undefined>(ROLES_KEY, targets);
    if (roles && !roles.includes(result.principal.role)) throw Errors.forbidden();
    return true;
  }
}

import { SetMetadata } from '@nestjs/common';
import type { Role } from './principal';

export const IS_PUBLIC_KEY = 'saloni:public';
export const ROLES_KEY = 'saloni:roles';

/** Route needs no access token. Such routes cannot use @Tenant(). */
export const Public = () => SetMetadata(IS_PUBLIC_KEY, true);

/** Restricts an authenticated route to these roles (checked server-side on every request). */
export const Roles = (...roles: Role[]) => SetMetadata(ROLES_KEY, roles);

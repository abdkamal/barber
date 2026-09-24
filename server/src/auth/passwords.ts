import * as argon2 from 'argon2';
import type { AppConfig } from '../config/config';
import type { SubjectKind } from './principal';

/** Minimum lengths from design §7: 8 for customers, 10 for staff. Max bounds hashing cost. */
export const PASSWORD_MIN = { customer: 8, staff: 10 } as const;
export const PASSWORD_MAX = 128;

export function passwordPolicyError(kind: SubjectKind, password: string): number | null {
  const min = PASSWORD_MIN[kind];
  if (typeof password !== 'string' || [...password].length < min || password.length > PASSWORD_MAX) return min;
  if (password.trim().length === 0) return min;
  return null;
}

export class PasswordHasher {
  private dummy?: Promise<string>;

  constructor(private readonly params: AppConfig['auth']['argon2']) {}

  hash(password: string): Promise<string> {
    return argon2.hash(password, { type: argon2.argon2id, ...this.params });
  }

  async verify(hash: string, password: string): Promise<boolean> {
    try {
      return await argon2.verify(hash, password);
    } catch {
      return false;
    }
  }

  /** Burns comparable time when the account does not exist (no user enumeration by timing). */
  async verifyDummy(password: string): Promise<false> {
    this.dummy ??= this.hash('dummy-password-for-timing-equalisation');
    await this.verify(await this.dummy, password);
    return false;
  }
}

import { Injectable } from '@nestjs/common';

/**
 * Server time source for all queue logic. Tests pin or shift it; production uses the system clock.
 * (Database defaults such as created_at still use PostgreSQL now().)
 */
@Injectable()
export class Clock {
  private fixed: number | null = null;
  private offset = 0;

  now(): number {
    return this.fixed ?? Date.now() + this.offset;
  }

  /** Test helper: freeze time at an instant (null = back to the system clock). */
  set(instant: number | Date | null): void {
    this.fixed = instant === null ? null : +instant;
  }

  /** Test helper: move the (frozen or live) clock forward. */
  advance(ms: number): void {
    if (this.fixed !== null) this.fixed += ms;
    else this.offset += ms;
  }
}

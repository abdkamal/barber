import { Injectable } from '@nestjs/common';

export interface ChangeSignal {
  salonId: string;
  /** Barber the changes concern; managers receive every signal of their salon. */
  staffIds: string[];
  seq: number;
}

type Listener = (s: ChangeSignal) => void;

/**
 * In-process fan-out of committed change-feed sequence numbers (one server instance, ق8).
 * The WebSocket stream subscribes; writers publish after their transaction commits.
 */
@Injectable()
export class ChangeBus {
  private readonly listeners = new Set<Listener>();

  subscribe(l: Listener): () => void {
    this.listeners.add(l);
    return () => this.listeners.delete(l);
  }

  publish(s: ChangeSignal): void {
    for (const l of this.listeners) {
      try {
        l(s);
      } catch {
        /* a broken listener must not affect writers */
      }
    }
  }
}

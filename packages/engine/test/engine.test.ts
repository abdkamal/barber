import { describe, expect, it } from 'vitest';
import {
  HOUR,
  MINUTE,
  assertQueueShape,
  baseDurationSuspect,
  bookingGate,
  canMarkNoShow,
  canPostpone,
  changeDuration,
  changeTime,
  chooseBarber,
  confirmOffer,
  diffProjections,
  estimateDuration,
  findPlacement,
  finishService,
  fitAroundBreaks,
  gapBuffer,
  measuredDuration,
  needsNotification,
  offlineBookingDeadline,
  overrunAlert,
  pastClosing,
  placeWithBarber,
  postpone,
  postponeIsExempt,
  projectQueue,
  remove,
  requestedHourOutcome,
  selectToCall,
  serviceSetKey,
  startService,
  type BarberCandidate,
  type BarberDay,
  type QueueEntry,
} from '../src/index.js';

const DAY0 = Date.UTC(2026, 8, 23);
const t = (h: number, m = 0) => DAY0 + h * HOUR + m * MINUTE;
const min = (n: number) => n * MINUTE;

const day = (over: Partial<BarberDay> = {}): BarberDay => ({ barberId: 'b1', workStart: t(9), workEnd: t(21), breaks: [], ...over });
const q = (id: string, dur: number, over: Partial<QueueEntry> = {}): QueueEntry => ({
  bookingId: id,
  kind: 'queue',
  status: 'waiting',
  estimatedDuration: min(dur),
  ...over,
});
const req = (id: string, dur: number, at: number, over: Partial<QueueEntry> = {}) => q(id, dur, { kind: 'requested', requestedAt: at, ...over });
const starts = (slots: { start: number }[]) => slots.map((s) => s.start);
const online = { kind: 'online' } as const;

describe('queue shape', () => {
  it('accepts a valid queue and rejects broken ones', () => {
    expect(() => assertQueueShape([q('a', 30, { status: 'in_service', actualStart: t(9) }), q('b', 30, { status: 'called' }), q('c', 10)])).not.toThrow();
    expect(() => assertQueueShape([q('a', 30), q('b', 30, { status: 'called' })])).toThrow(/order/);
    expect(() => assertQueueShape([q('a', 30), q('a', 30)])).toThrow(/duplicate/);
    expect(() => assertQueueShape([q('a', 30, { kind: 'requested' })])).toThrow(/requestedAt/);
  });
});

describe('projectQueue (design §5.1)', () => {
  it('chains bookings from opening time', () => {
    expect(starts(projectQueue(day(), [q('a', 30), q('b', 20)], t(8)))).toEqual([t(9), t(9, 30)]);
  });

  it('never ends an overrunning service automatically while live', () => {
    const queue = [q('a', 30, { status: 'in_service', actualStart: t(10) }), q('b', 20)];
    const slots = projectQueue(day(), queue, t(10, 45));
    expect(slots[0]!.end).toBe(t(10, 45));
    expect(slots[1]!.start).toBe(t(10, 45));
  });

  it('freezes on estimates when the barber is offline (design §4)', () => {
    const queue = [q('a', 30, { status: 'in_service', actualStart: t(10) }), q('b', 20)];
    const slots = projectQueue(day(), queue, t(11, 30), { frozenAt: t(10, 5) });
    expect(slots[0]!.end).toBe(t(10, 30));
    expect(slots[1]!.start).toBe(t(10, 30));
  });

  it('waits for a requested hour and never straddles a break', () => {
    const d = day({ breaks: [{ start: t(12), end: t(12, 30) }] });
    expect(starts(projectQueue(d, [q('a', 30), req('r', 30, t(11))], t(9)))).toEqual([t(9), t(11)]);
    expect(fitAroundBreaks(t(11, 45), min(30), d.breaks)).toBe(t(12, 30));
  });

  it('walk-in-only windows block app bookings but not walk-ins (ق33)', () => {
    const d = day({ breaks: [{ start: t(9), end: t(10), kind: 'walk_in_only' }] });
    expect(projectQueue(d, [q('app', 30)], t(9))[0]!.start).toBe(t(10));
    expect(projectQueue(d, [q('w', 30, { walkIn: true })], t(9))[0]!.start).toBe(t(9));
  });

  it('flags bookings pushed past closing (ق24)', () => {
    const d = day({ workEnd: t(10) });
    const slots = projectQueue(d, [q('a', 30, { status: 'in_service', actualStart: t(9) }), q('b', 30), q('c', 20)], t(9, 20));
    expect(pastClosing(d, slots)).toEqual(['c']);
  });
});

describe('findPlacement — ق4 nobody is delayed, ق19 gap buffer', () => {
  it('appends a plain turn', () => {
    expect(findPlacement(day(), [q('a', 30), q('b', 30)], t(9), { kind: 'queue', duration: min(20) })).toMatchObject({ position: 2, start: t(10) });
  });

  it('never puts a requested hour ahead of someone who booked earlier', () => {
    const p = findPlacement(day(), [q('a', 60), q('b', 60)], t(9), { kind: 'requested', requestedAt: t(10), duration: min(30) });
    expect(p).toMatchObject({ position: 2, start: t(11) });
    expect(requestedHourOutcome(p!.start, t(10))).toBe('offer');
  });

  it('books the exact requested hour when free (ق13)', () => {
    const p = findPlacement(day(), [q('a', 30)], t(9), { kind: 'requested', requestedAt: t(15), duration: min(30) });
    expect(p!.start).toBe(t(15));
    expect(requestedHourOutcome(p!.start, t(15))).toBe('accept');
  });

  it('fills a gap only when it is bigger than the service plus the buffer', () => {
    // Gap 9:30–11:00 (90 min) before a requested booking.
    const queue = [q('a', 30), req('r', 30, t(11))];
    // 30 min service: buffer max(10, 7.5) = 10 → needs 40 ≤ 90 → fits.
    expect(findPlacement(day(), queue, t(9), { kind: 'queue', duration: min(30) })).toMatchObject({ position: 1, start: t(9, 30) });
    // 75 min service: buffer max(10, 18.75) ≈ 19 → needs 94 > 90 → appended after r.
    expect(findPlacement(day(), queue, t(9), { kind: 'queue', duration: min(75) })).toMatchObject({ position: 2, start: t(11, 30) });
    expect(gapBuffer(min(75))).toBe(min(18.75));
  });

  it('never goes ahead of the customer in service or the one called', () => {
    const queue = [q('a', 30, { status: 'in_service', actualStart: t(9) }), req('b', 30, t(12), { status: 'called' })];
    expect(findPlacement(day(), queue, t(9, 5), { kind: 'queue', duration: min(20) })!.position).toBe(2);
  });

  it('only appends while the barber is offline', () => {
    const queue = [q('a', 30), req('r', 30, t(11))];
    expect(findPlacement(day(), queue, t(9), { kind: 'queue', duration: min(30) }, { appendOnly: true })!.position).toBe(2);
  });

  it('refuses a booking that cannot finish before closing', () => {
    expect(findPlacement(day({ workEnd: t(10) }), [q('a', 45)], t(9), { kind: 'queue', duration: min(20) })).toBeNull();
  });

  it('a walk-in may use the walk-in-only window without delaying the first booking after it', () => {
    const d = day({ breaks: [{ start: t(9), end: t(10), kind: 'walk_in_only' }] });
    const queue = [q('app', 30)]; // starts 10:00
    expect(findPlacement(d, queue, t(9), { kind: 'queue', duration: min(30), walkIn: true })).toMatchObject({ position: 0, start: t(9) });
    expect(findPlacement(d, queue, t(9), { kind: 'queue', duration: min(55), walkIn: true })!.position).toBe(1);
  });
});

describe('booking gate — day states (design §4, ق3, ق26)', () => {
  it('not connected yet: bookings open, estimates frozen', () => {
    expect(bookingGate({ kind: 'not_connected' }, t(8))).toMatchObject({ accepts: true, autoAssignable: true, frozenAt: t(8) });
  });

  it('absent today: closed', () => {
    expect(bookingGate({ kind: 'absent' }, t(10)).accepts).toBe(false);
  });

  it('offline with ≥ 2h known work: append-only for two hours', () => {
    const s = { kind: 'offline', offlineSince: t(10), knownWorkEnd: t(13) } as const;
    expect(offlineBookingDeadline(t(10), t(13))).toBe(t(12));
    expect(bookingGate(s, t(11, 59))).toMatchObject({ accepts: true, appendOnly: true, autoAssignable: false });
    expect(bookingGate(s, t(12)).accepts).toBe(false);
  });

  it('offline with less than 2h known work: stops immediately', () => {
    expect(bookingGate({ kind: 'offline', offlineSince: t(10), knownWorkEnd: t(11, 30) }, t(10)).accepts).toBe(false);
  });
});

describe('chooseBarber (design §5.4)', () => {
  const cand = (id: string, queue: QueueEntry[], dur: number, over: Partial<BarberCandidate> = {}): BarberCandidate => ({
    day: day({ barberId: id }),
    queue,
    state: online,
    duration: min(dur),
    bookingsToday: 0,
    seniority: 0,
    ...over,
  });

  it('picks the barber who can start soonest, not the one with fewer bookings', () => {
    const r = chooseBarber([cand('b2', [q('c', 60)], 20), cand('b1', [q('a', 10), q('b', 10)], 20)], t(9), { kind: 'queue' });
    expect(r).toMatchObject({ barberId: 'b1', start: t(9, 20) });
  });

  it('breaks ties by earlier finish, then fewer bookings today, then seniority', () => {
    expect(chooseBarber([cand('slow', [], 40), cand('fast', [], 25)], t(9), { kind: 'queue' })!.barberId).toBe('fast');
    expect(chooseBarber([cand('x', [], 30, { bookingsToday: 5 }), cand('y', [], 30, { bookingsToday: 2 })], t(9), { kind: 'queue' })!.barberId).toBe('y');
    expect(chooseBarber([cand('x', [], 30, { seniority: 2 }), cand('y', [], 30, { seniority: 1 })], t(9), { kind: 'queue' })!.barberId).toBe('y');
  });

  it('skips offline and absent barbers', () => {
    const r = chooseBarber(
      [cand('off', [], 20, { state: { kind: 'offline', offlineSince: t(8), knownWorkEnd: t(12) } }), cand('abs', [], 20, { state: { kind: 'absent' } }), cand('ok', [q('a', 60)], 20)],
      t(9),
      { kind: 'queue' },
    );
    expect(r!.barberId).toBe('ok');
  });

  it('a chosen offline barber still takes appended bookings within the window (ق3)', () => {
    const c = { day: day(), queue: [q('a', 30), req('r', 30, t(11))], state: { kind: 'offline', offlineSince: t(9), knownWorkEnd: t(12) } as const, duration: min(30) };
    expect(placeWithBarber(c, t(9, 10), { kind: 'queue' })!.position).toBe(2);
  });
});

describe('calling rule (design §5.5)', () => {
  it('calls the next customer within the lead time, or immediately after a postponement', () => {
    const queue = [q('a', 30, { status: 'in_service', actualStart: t(9) }), q('b', 30)];
    expect(selectToCall(queue, projectQueue(day(), queue, t(9, 5)), t(9, 5), min(20))).toBeNull();
    expect(selectToCall(queue, projectQueue(day(), queue, t(9, 12)), t(9, 12), min(20))).toBe('b');
    expect(selectToCall(queue, projectQueue(day(), queue, t(9, 5)), t(9, 5), min(20), { immediate: true })).toBe('b');
  });

  it('never calls a third while the called one has not arrived, and never calls an offer', () => {
    const queue = [q('a', 30, { status: 'in_service', actualStart: t(9) }), q('b', 30, { status: 'called' }), q('c', 10)];
    expect(selectToCall(queue, projectQueue(day(), queue, t(9, 29)), t(9, 29), min(60))).toBeNull();
    const offerFirst = [q('o', 30, { offer: true }), q('c', 10)];
    expect(selectToCall(offerFirst, projectQueue(day(), offerFirst, t(9)), t(9), min(60))).toBe('c');
  });
});

describe('postponement and no-show (ق10, ق21, ق22, ق23)', () => {
  it('postpones once, N turns, and then only no-show is possible', () => {
    const queue = [q('b', 30, { status: 'called' }), q('c', 30), q('d', 30), q('e', 30)];
    const after = postpone(queue, 'b', 2);
    expect(after.map((e) => e.bookingId)).toEqual(['c', 'd', 'b', 'e']);
    const b = after.find((e) => e.bookingId === 'b')!;
    expect(b.status).toBe('waiting');
    expect(canPostpone(b)).toBe(false);
    expect(canMarkNoShow(b)).toBe(true);
    expect(() => postpone(after, 'b')).toThrow(/already used/);
  });

  it('no-show is not available before the postponement', () => {
    expect(canMarkNoShow(q('x', 30, { status: 'called' }))).toBe(false);
  });

  it('skipping the called customer counts as their postponement', () => {
    const r = startService([q('b', 30, { status: 'called' }), q('c', 30)], 'c', t(10));
    expect(r.skipped).toBe('b');
    expect(r.queue.map((e) => [e.bookingId, e.status, !!e.postponeUsed])).toEqual([
      ['c', 'in_service', false],
      ['b', 'waiting', true],
    ]);
  });

  it('a postponement caused by being moved earlier > 30 min does not count', () => {
    expect(postponeIsExempt(t(11), t(10, 20))).toBe(true);
    expect(postponeIsExempt(t(11), t(10, 40))).toBe(false);
    const after = postpone([q('b', 30, { status: 'called' }), q('c', 30)], 'b', 1, { exempt: true });
    expect(canPostpone(after[1]!)).toBe(true);
  });
});

describe('service lifecycle', () => {
  it('start, change services mid-session, finish', () => {
    const d = day();
    const { queue } = startService([q('a', 20), q('b', 30)], 'a', t(9));
    const before = projectQueue(d, queue, t(9, 10));
    const edited = changeDuration(queue, 'a', min(60));
    const after = projectQueue(d, edited, t(9, 10));
    expect(after[0]!.start).toBe(t(9));
    expect(diffProjections(before, after)).toEqual([{ bookingId: 'b', before: t(9, 20), after: t(10), delta: min(40) }]);
    expect(finishService(edited, 'a').map((e) => e.bookingId)).toEqual(['b']);
  });

  it('notification is due only beyond the margin, in either direction (ق5)', () => {
    expect(needsNotification(t(9, 20), t(10))).toBe(true);
    expect(needsNotification(t(10), t(9, 20))).toBe(true);
    expect(needsNotification(t(9, 20), t(9, 50))).toBe(false);
  });

  it('alerts the barber at 100% of the estimate, never ends it (ق27)', () => {
    expect(overrunAlert(t(9), min(30), t(9, 29))).toBe(false);
    expect(overrunAlert(t(9), min(30), t(9, 30))).toBe(true);
  });

  it('cannot remove a booking in service; cancel otherwise (ق29)', () => {
    const queue = [q('a', 30, { status: 'in_service', actualStart: t(9) }), q('b', 30, { status: 'called' })];
    expect(() => remove(queue, 'a')).toThrow();
    expect(remove(queue, 'b').map((e) => e.bookingId)).toEqual(['a']);
  });
});

describe('offers and time changes', () => {
  it('an offer holds its place and is confirmed in place (ق13)', () => {
    const queue = [q('a', 30), q('o', 30, { kind: 'requested', requestedAt: t(9, 30), offer: true })];
    const p = findPlacement(day(), queue, t(9), { kind: 'queue', duration: min(20) });
    expect(p!.position).toBe(2);
    expect(confirmOffer(queue, 'o')[1]!.offer).toBe(false);
  });

  it('a time change is atomic: moved when it fits, untouched when it does not (§5.12)', () => {
    const d = day({ workEnd: t(12) });
    const queue = [q('a', 30), q('b', 30)];
    const ok = changeTime(d, queue, t(9), 'a', { kind: 'requested', requestedAt: t(11) });
    expect(ok!.start).toBe(t(11));
    expect(ok!.queue.map((e) => e.bookingId)).toEqual(['b', 'a']);
    expect(changeTime(d, queue, t(9), 'a', { kind: 'requested', requestedAt: t(11, 45) })).toBeNull();
  });
});

describe('duration learning (ق11, §5.10)', () => {
  it('starts from the base, learns the barber, personalises gently', () => {
    expect(estimateDuration(min(30), [], [])).toBe(min(30));
    expect(estimateDuration(min(30), Array(20).fill(min(20)), [])).toBe(min(20));
    expect(estimateDuration(min(30), [], [min(45)])).toBe(min(35));
  });

  it('ignores implausible taps and keeps learning when the base is wrong', () => {
    expect(estimateDuration(min(30), [min(1), min(300)], [])).toBe(min(30));
    // Base 10 min but the barber really takes 35: once enough history exists, his median becomes the reference.
    const real = Array(12).fill(min(35));
    expect(estimateDuration(min(10), real, [])).toBe(min(35));
    expect(baseDurationSuspect(min(10), real)).toBe(true);
    expect(baseDurationSuspect(min(30), real)).toBe(false);
  });

  it('measures only real taps and keys service sets by content', () => {
    expect(measuredDuration(t(9), t(9, 30))).toBe(min(30));
    expect(measuredDuration(t(9), t(9, 30), { approximate: true })).toBeNull();
    expect(measuredDuration(t(9, 30), t(9))).toBeNull();
    expect(serviceSetKey(['hair', 'beard'])).toBe(serviceSetKey(['beard', 'hair', 'beard']));
  });
});

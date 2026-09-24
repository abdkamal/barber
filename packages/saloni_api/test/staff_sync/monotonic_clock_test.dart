import 'package:saloni_api/staff_sync.dart';
import 'package:test/test.dart';

class _FakeStopwatch implements Stopwatch {
  Duration _elapsed = Duration.zero;

  void advance(Duration d) => _elapsed += d;

  @override
  Duration get elapsed => _elapsed;

  @override
  int get elapsedMicroseconds => _elapsed.inMicroseconds;

  @override
  int get elapsedMilliseconds => _elapsed.inMilliseconds;

  @override
  int get elapsedTicks => _elapsed.inMicroseconds;

  @override
  int get frequency => 1000000;

  @override
  bool get isRunning => true;

  @override
  void reset() => _elapsed = Duration.zero;

  @override
  void start() {}

  @override
  void stop() {}
}

void main() {
  group('MonotonicClock', () {
    test('falls back to wall clock and marks approximate before any anchor',
        () {
      final clock = MonotonicClock(stopwatch: _FakeStopwatch());
      final reading = clock.now();
      expect(reading.approximate, isTrue);
      expect(clock.hasAnchor, isFalse);
    });

    test(
        'computes occurredAt from server anchor + elapsed, non-approximate after a live anchor',
        () {
      final sw = _FakeStopwatch();
      final clock = MonotonicClock(stopwatch: sw);
      final serverTime = DateTime.utc(2026, 9, 24, 10, 0, 0);
      clock.anchor(serverTime);

      sw.advance(const Duration(seconds: 30));
      final reading = clock.now();

      expect(reading.approximate, isFalse);
      expect(reading.occurredAt, serverTime.add(const Duration(seconds: 30)));
    });

    test('restoreAnchor keeps readings approximate until a new live anchor',
        () {
      final sw = _FakeStopwatch();
      final clock = MonotonicClock(stopwatch: sw);
      final restoredServerTime = DateTime.utc(2026, 9, 24, 8, 0, 0);

      // Simulates loading a persisted serverTime after an app restart: the
      // Stopwatch continuity from before the restart is lost, so readings
      // stay marked approximate.
      clock.restoreAnchor(restoredServerTime);
      sw.advance(const Duration(minutes: 5));
      expect(clock.now().approximate, isTrue);

      // A real sync response arrives in this run -> continuity restored.
      final freshServerTime = DateTime.utc(2026, 9, 24, 8, 5, 1);
      clock.anchor(freshServerTime);
      sw.advance(const Duration(seconds: 10));
      final reading = clock.now();
      expect(reading.approximate, isFalse);
      expect(
          reading.occurredAt, freshServerTime.add(const Duration(seconds: 10)));
    });

    test(
        'unaffected by device wall-clock time (only Stopwatch elapsed matters)',
        () {
      final sw = _FakeStopwatch();
      final clock = MonotonicClock(stopwatch: sw);
      clock.anchor(DateTime.utc(2026, 9, 24, 10, 0, 0));
      sw.advance(const Duration(minutes: 2));
      // No dependency on DateTime.now() at all for the computed reading.
      final reading = clock.now();
      expect(reading.occurredAt, DateTime.utc(2026, 9, 24, 10, 2, 0));
    });
  });

  group('MonotonicClock — ق40 مراجعة F1: الساعة عبر إعادة فتح التطبيق', () {
    final server = DateTime.utc(2026, 9, 24, 8, 0, 0);
    const saved = BootReading(Duration(hours: 3), bootId: '17');

    test(
        'app restarted without a reboot: the closed time counts and the reading is exact',
        () {
      final sw = _FakeStopwatch(); // new process: starts at zero
      final clock =
          MonotonicClock(stopwatch: sw, wallClock: () => DateTime.utc(2000));
      // Closed for 40 minutes (elapsed-since-boot grew by 40 min), wall clock wrong.
      clock.restoreAnchor(server,
          savedBoot: saved,
          currentBoot:
              const BootReading(Duration(hours: 3, minutes: 40), bootId: '17'));
      final r = clock.now();
      expect(r.approximate, isFalse);
      expect(r.occurredAt, server.add(const Duration(minutes: 40)));
      // Later readings: by the boot clock when passed (counts deep sleep), else the stopwatch.
      expect(
          clock
              .now(const BootReading(Duration(hours: 4), bootId: '17'))
              .occurredAt,
          server.add(const Duration(hours: 1)));
      sw.advance(const Duration(minutes: 5));
      expect(clock.now().occurredAt, server.add(const Duration(minutes: 45)));
    });

    test(
        'after a reboot: wall clock, never before the last server time, approximate',
        () {
      final wallBehind = MonotonicClock(
          stopwatch: _FakeStopwatch(),
          wallClock: () => DateTime.utc(2026, 9, 24, 7));
      wallBehind.restoreAnchor(server,
          savedBoot: saved,
          currentBoot: const BootReading(Duration(minutes: 2), bootId: '18'));
      expect(wallBehind.now().approximate, isTrue);
      expect(wallBehind.now().occurredAt,
          server); // clamped up to the last server time

      final wallAhead = MonotonicClock(
          stopwatch: _FakeStopwatch(),
          wallClock: () => DateTime.utc(2026, 9, 24, 9, 30));
      wallAhead.restoreAnchor(server,
          savedBoot: saved,
          currentBoot: const BootReading(Duration(minutes: 2)));
      final r = wallAhead.now(const BootReading(Duration(minutes: 12)));
      expect(r.approximate, isTrue);
      expect(r.occurredAt, DateTime.utc(2026, 9, 24, 9, 40));
    });

    test('a different boot id means a reboot even if the new uptime is larger',
        () {
      final clock = MonotonicClock(
          stopwatch: _FakeStopwatch(),
          wallClock: () => DateTime.utc(2026, 9, 24, 12));
      clock.restoreAnchor(server,
          savedBoot: saved,
          currentBoot: const BootReading(Duration(hours: 5), bootId: '18'));
      expect(clock.now().approximate, isTrue);
      expect(clock.now().occurredAt, DateTime.utc(2026, 9, 24, 12));
    });

    test('no boot reading (platform without it): the old approximate behaviour',
        () {
      final clock = MonotonicClock(
          stopwatch: _FakeStopwatch(),
          wallClock: () => DateTime.utc(2026, 9, 24, 8, 30));
      clock.restoreAnchor(server);
      expect(clock.now().approximate, isTrue);
      expect(clock.now().occurredAt, DateTime.utc(2026, 9, 24, 8, 30));
    });

    test('a live anchor measured by the boot clock counts deep sleep', () {
      final sw = _FakeStopwatch();
      final clock = MonotonicClock(stopwatch: sw);
      clock.anchor(server, boot: const BootReading(Duration(hours: 1)));
      sw.advance(
          const Duration(minutes: 1)); // the process slept most of the time
      final r = clock.now(const BootReading(Duration(hours: 1, minutes: 30)));
      expect(r.approximate, isFalse);
      expect(r.occurredAt, server.add(const Duration(minutes: 30)));
    });

    test('BootReading / ClockAnchorRecord JSON round-trip', () {
      final a = ClockAnchorRecord(server, boot: saved);
      final back = ClockAnchorRecord.fromJson(a.toJson())!;
      expect(back.serverTime, server);
      expect(back.boot, saved);
      expect(
          ClockAnchorRecord.fromJson({'serverTime': server.toIso8601String()})!
              .boot,
          isNull);
      expect(ClockAnchorRecord.fromJson('junk'), isNull);
    });
  });
}

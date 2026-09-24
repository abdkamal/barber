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
    test('falls back to wall clock and marks approximate before any anchor', () {
      final clock = MonotonicClock(stopwatch: _FakeStopwatch());
      final reading = clock.now();
      expect(reading.approximate, isTrue);
      expect(clock.hasAnchor, isFalse);
    });

    test('computes occurredAt from server anchor + elapsed, non-approximate after a live anchor', () {
      final sw = _FakeStopwatch();
      final clock = MonotonicClock(stopwatch: sw);
      final serverTime = DateTime.utc(2026, 9, 24, 10, 0, 0);
      clock.anchor(serverTime);

      sw.advance(const Duration(seconds: 30));
      final reading = clock.now();

      expect(reading.approximate, isFalse);
      expect(reading.occurredAt, serverTime.add(const Duration(seconds: 30)));
    });

    test('restoreAnchor keeps readings approximate until a new live anchor', () {
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
      expect(reading.occurredAt, freshServerTime.add(const Duration(seconds: 10)));
    });

    test('unaffected by device wall-clock time (only Stopwatch elapsed matters)', () {
      final sw = _FakeStopwatch();
      final clock = MonotonicClock(stopwatch: sw);
      clock.anchor(DateTime.utc(2026, 9, 24, 10, 0, 0));
      sw.advance(const Duration(minutes: 2));
      // No dependency on DateTime.now() at all for the computed reading.
      final reading = clock.now();
      expect(reading.occurredAt, DateTime.utc(2026, 9, 24, 10, 2, 0));
    });
  });
}

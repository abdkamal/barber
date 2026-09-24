import 'package:drift/native.dart';
import 'package:saloni_api/saloni_api.dart';
import 'package:saloni_api/staff_sync.dart';
import 'package:test/test.dart';

void main() {
  late StaffSyncDatabase db;
  late DriftLocalStore store;

  setUp(() {
    db = StaffSyncDatabase(NativeDatabase.memory());
    store = DriftLocalStore(db);
  });

  tearDown(() => db.close());

  group('DriftLocalStore', () {
    test('persists and reads back the queue, services and breaks', () async {
      final booking = Booking(
        id: 'b1',
        customerId: 'c1',
        barberId: 'br1',
        serviceIds: const ['s1'],
        kind: BookingKind.queue,
        status: BookingStatus.waiting,
        originalEta: DateTime.utc(2026, 9, 24, 10, 0),
        source: BookingSource.app,
      );
      await store.saveQueue([booking]);
      await store.saveServices(const [
        Service(id: 's1', name: 'قص', baseDurationMin: 20, priceCents: 3000),
      ]);
      await store.saveBreaks([
        BreakPeriod(
          id: 'br1',
          kind: BreakKind.rest,
          start: DateTime.utc(2026, 9, 24, 12, 0),
          end: DateTime.utc(2026, 9, 24, 12, 10),
        ),
      ]);

      expect((await store.getQueue()).single.id, 'b1');
      expect((await store.getServices()).single.name, 'قص');
      expect((await store.getBreaks()).single.kind, BreakKind.rest);
    });

    test('sync cursor and last server time round-trip', () async {
      expect(await store.getSyncCursor(), 0);
      await store.saveSyncCursor(42);
      expect(await store.getSyncCursor(), 42);

      expect(await store.getLastServerTime(), isNull);
      final t = DateTime.utc(2026, 9, 24, 9, 30);
      await store.saveLastServerTime(t);
      expect(await store.getLastServerTime(), t);

      // ق40 مراجعة F1: مرساة الساعة مع قراءة ساعة التشغيل، تُحفظان معًا وتُمسحان مع الجهاز.
      expect(await store.getClockAnchor(), isNull);
      await store.saveClockAnchor(ClockAnchorRecord(t, boot: const BootReading(Duration(minutes: 90), bootId: '4')));
      final a = (await store.getClockAnchor())!;
      expect(a.serverTime, t);
      expect(a.boot, const BootReading(Duration(minutes: 90), bootId: '4'));
      await store.wipe();
      expect(await store.getClockAnchor(), isNull);
    });

    test('nextDeviceSeq increases monotonically and survives re-reads', () async {
      expect(await store.nextDeviceSeq(), 1);
      expect(await store.nextDeviceSeq(), 2);
      expect(await store.nextDeviceSeq(), 3);
    });

    test('outbox entries are stored ordered by deviceSeq and removable', () async {
      final e1 = DeviceEvent(
        id: 'e1',
        deviceSeq: 2,
        type: DeviceEventType.serviceStarted,
        occurredAt: DateTime.utc(2026, 9, 24, 10, 0),
        approximate: false,
      );
      final e2 = DeviceEvent(
        id: 'e2',
        deviceSeq: 1,
        type: DeviceEventType.serviceFinished,
        occurredAt: DateTime.utc(2026, 9, 24, 10, 5),
        approximate: false,
      );
      await store.putOutboxEntry(OutboxEntry(event: e1));
      await store.putOutboxEntry(OutboxEntry(event: e2));

      final all = await store.getOutbox();
      expect(all.map((e) => e.event.id).toList(), ['e2', 'e1']);

      await store.removeOutboxEntry('e2');
      expect((await store.getOutbox()).map((e) => e.event.id), ['e1']);
    });

    test('wipe clears everything (logout — design.md §6.1)', () async {
      await store.saveSyncCursor(5);
      await store.putOutboxEntry(OutboxEntry(
        event: DeviceEvent(
          id: 'e1',
          deviceSeq: 1,
          type: DeviceEventType.serviceStarted,
          occurredAt: DateTime.utc(2026, 9, 24, 10, 0),
          approximate: false,
        ),
      ));

      await store.wipe();

      expect(await store.getSyncCursor(), 0);
      expect(await store.getOutbox(), isEmpty);
    });
  });
}

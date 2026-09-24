import 'dart:convert';

import 'package:drift/drift.dart';

import '../models/models.dart';
import 'drift_database.dart';
import 'local_store.dart';

const _kQueue = 'queue';
const _kServices = 'services';
const _kBreaks = 'breaks';
const _kSettings = 'settings';
const _kCursor = 'cursor';
const _kLastServerTime = 'lastServerTime';
const _kDeviceSeq = 'deviceSeq';

/// تنفيذ [LocalStore] فوق Drift/SQLite — design.md §6.1.
///
/// يُبنى عادة فوق منفّذ استعلام (`QueryExecutor`) عادي في الاختبارات
/// (`NativeDatabase.memory()`)، وفوق منفّذ مشفّر بـSQLCipher في التطبيق
/// الحقيقي — انظر `lib/staff_sync.dart` وREADME.
class DriftLocalStore implements LocalStore {
  DriftLocalStore(this._db);

  final StaffSyncDatabase _db;

  Future<void> _putRaw(String key, Object? value) async {
    await _db.into(_db.keyValueEntries).insertOnConflictUpdate(
          KeyValueEntriesCompanion.insert(key: key, value: jsonEncode(value)),
        );
  }

  Future<T?> _getRaw<T>(String key, T Function(dynamic) decode) async {
    final row = await (_db.select(_db.keyValueEntries)
          ..where((t) => t.key.equals(key)))
        .getSingleOrNull();
    if (row == null) return null;
    return decode(jsonDecode(row.value));
  }

  @override
  Future<List<Booking>> getQueue() async =>
      await _getRaw<List<Booking>>(
        _kQueue,
        (raw) => (raw as List)
            .map((e) => Booking.fromJson(e as Map<String, dynamic>))
            .toList(),
      ) ??
      const [];

  @override
  Future<void> saveQueue(List<Booking> queue) =>
      _putRaw(_kQueue, queue.map((e) => e.toJson()).toList());

  @override
  Future<List<Service>> getServices() async =>
      await _getRaw<List<Service>>(
        _kServices,
        (raw) => (raw as List)
            .map((e) => Service.fromJson(e as Map<String, dynamic>))
            .toList(),
      ) ??
      const [];

  @override
  Future<void> saveServices(List<Service> services) =>
      _putRaw(_kServices, services.map((e) => e.toJson()).toList());

  @override
  Future<List<BreakPeriod>> getBreaks() async =>
      await _getRaw<List<BreakPeriod>>(
        _kBreaks,
        (raw) => (raw as List)
            .map((e) => BreakPeriod.fromJson(e as Map<String, dynamic>))
            .toList(),
      ) ??
      const [];

  @override
  Future<void> saveBreaks(List<BreakPeriod> breaks) =>
      _putRaw(_kBreaks, breaks.map((e) => e.toJson()).toList());

  @override
  Future<Map<String, dynamic>> getSettings() async =>
      await _getRaw<Map<String, dynamic>>(
        _kSettings,
        (raw) => Map<String, dynamic>.from(raw as Map),
      ) ??
      const {};

  @override
  Future<void> saveSettings(Map<String, dynamic> settings) =>
      _putRaw(_kSettings, settings);

  @override
  Future<int> getSyncCursor() async =>
      await _getRaw<int>(_kCursor, (raw) => raw as int) ?? 0;

  @override
  Future<void> saveSyncCursor(int seq) => _putRaw(_kCursor, seq);

  @override
  Future<DateTime?> getLastServerTime() async => await _getRaw<DateTime>(
        _kLastServerTime,
        (raw) => DateTime.parse(raw as String).toUtc(),
      );

  @override
  Future<void> saveLastServerTime(DateTime time) =>
      _putRaw(_kLastServerTime, time.toUtc().toIso8601String());

  @override
  Future<int> nextDeviceSeq() async {
    return _db.transaction(() async {
      final current =
          await _getRaw<int>(_kDeviceSeq, (raw) => raw as int) ?? 0;
      final next = current + 1;
      await _putRaw(_kDeviceSeq, next);
      return next;
    });
  }

  OutboxEntry _rowToEntry(OutboxRow row) => OutboxEntry(
        event: DeviceEvent.fromJson(
            jsonDecode(row.eventJson) as Map<String, dynamic>),
        status: row.status == 'sending' ? OutboxStatus.sending : OutboxStatus.pending,
        attempts: row.attempts,
        nextRetryAt: row.nextRetryAt,
      );

  @override
  Future<List<OutboxEntry>> getOutbox() async {
    final rows = await (_db.select(_db.outboxEntries)
          ..orderBy([(t) => OrderingTerm.asc(t.deviceSeq)]))
        .get();
    return rows.map(_rowToEntry).toList();
  }

  @override
  Future<void> putOutboxEntry(OutboxEntry entry) async {
    await _db.into(_db.outboxEntries).insertOnConflictUpdate(
          OutboxEntriesCompanion.insert(
            eventId: entry.event.id,
            deviceSeq: entry.event.deviceSeq,
            eventJson: jsonEncode(entry.event.toJson()),
            status: Value(
                entry.status == OutboxStatus.sending ? 'sending' : 'pending'),
            attempts: Value(entry.attempts),
            nextRetryAt: Value(entry.nextRetryAt),
          ),
        );
  }

  @override
  Future<void> removeOutboxEntry(String eventId) async {
    await (_db.delete(_db.outboxEntries)..where((t) => t.eventId.equals(eventId)))
        .go();
  }

  @override
  Future<void> wipe() async {
    await _db.delete(_db.keyValueEntries).go();
    await _db.delete(_db.outboxEntries).go();
  }
}

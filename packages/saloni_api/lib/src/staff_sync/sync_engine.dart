import 'dart:async';

import 'package:uuid/uuid.dart';

import '../api_client.dart';
import '../models/models.dart';
import 'connection_state.dart';
import 'local_store.dart';
import 'monotonic_clock.dart';
import 'outbox.dart';

/// محرّك المزامنة لتطبيق الطاقم أثناء الاتصال والانقطاع (design.md §6):
/// يسجّل أحداث الجهاز في الصندوق، يدفعها بالترتيب، يسحب تغييرات السيرفر،
/// يرسل نبضة كل 30 ثانية، ويعرض حالة الاتصال لشريط الاتصال الدائم.
///
/// إضافة زبون حاضر تُرفض صراحة أثناء الانقطاع (design.md §10، «معطل دون
/// اتصال») برسالة عربية واضحة.
class StaffSyncEngine {
  StaffSyncEngine({
    required this.api,
    required this.store,
    MonotonicClock? clock,
    Uuid? uuid,
    this.heartbeatInterval = const Duration(seconds: 30),
    void Function(List<SyncChange> changes)? onChanges,
  })  : clock = clock ?? MonotonicClock(),
        _uuid = uuid ?? const Uuid(),
        _onChanges = onChanges {
    outbox = Outbox(store: store, api: api);
  }

  final ApiClient api;
  final LocalStore store;
  final MonotonicClock clock;
  final Duration heartbeatInterval;
  final Uuid _uuid;
  final void Function(List<SyncChange> changes)? _onChanges;

  late final Outbox outbox;
  Timer? _timer;
  bool _started = false;

  final StreamController<ConnectionState> _controller =
      StreamController<ConnectionState>.broadcast();
  ConnectionState _state = ConnectionState(
    status: ConnectionStatus.offline,
    since: DateTime.now().toUtc(),
    pendingCount: 0,
  );

  /// حالة الاتصال الحالية والتيار المباشر لتغيّراتها (لشريط الاتصال).
  ConnectionState get state => _state;
  Stream<ConnectionState> get connectionState => _controller.stream;

  bool get isOnline => _state.status == ConnectionStatus.online;

  void _emit(ConnectionState next) {
    _state = next;
    _controller.add(next);
  }

  /// يُستدعى مرة عند بدء تشغيل شاشة «طابوري»: يسترجع مرساة الساعة الرتيبة
  /// المحفوظة، ثم يبدأ حلقة النبضة/المزامنة كل [heartbeatInterval].
  Future<void> start() async {
    if (_started) return;
    _started = true;
    final lastServerTime = await store.getLastServerTime();
    if (lastServerTime != null) {
      clock.restoreAnchor(lastServerTime);
    }
    await _emitPendingCount();
    unawaited(_tick());
    _timer = Timer.periodic(heartbeatInterval, (_) => _tick());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _started = false;
  }

  Future<void> dispose() async {
    stop();
    await _controller.close();
  }

  Future<void> _emitPendingCount() async {
    _emit(_state.copyWith(pendingCount: await outbox.pendingCount()));
  }

  Future<void> _tick() async {
    _emit(_state.copyWith(status: ConnectionStatus.syncing));
    try {
      await outbox.flush();
      final deviceSeq = await store.nextDeviceSeq();
      await api.heartbeat(
        deviceSeq: deviceSeq,
        queueDigest: await _queueDigest(),
      );
      final cursor = await store.getSyncCursor();
      final pull = await api.pullSync(cursor);
      if (pull.changes.isNotEmpty) {
        await store.saveSyncCursor(pull.seq);
        _onChanges?.call(pull.changes);
      } else {
        await store.saveSyncCursor(pull.seq);
      }
      clock.anchor(pull.serverTime);
      await store.saveLastServerTime(pull.serverTime);
      _emit(ConnectionState(
        status: ConnectionStatus.online,
        since: DateTime.now().toUtc(),
        pendingCount: await outbox.pendingCount(),
      ));
    } on ApiError {
      _emit(ConnectionState(
        status: ConnectionStatus.offline,
        since: DateTime.now().toUtc(),
        pendingCount: await outbox.pendingCount(),
      ));
    }
  }

  Future<String> _queueDigest() async {
    final queue = await store.getQueue();
    final ids = queue.map((b) => '${b.id}:${b.status.toWire()}').join(',');
    return ids.hashCode.toRadixString(16);
  }

  /// يسجّل حدث جهاز جديد بوقت الساعة الرتيبة، ويحفظه في الصندوق فورًا.
  Future<DeviceEvent> recordEvent(
    DeviceEventType type, {
    String? bookingId,
    Map<String, dynamic> payload = const {},
  }) async {
    final deviceSeq = await store.nextDeviceSeq();
    final reading = clock.now();
    final event = DeviceEvent(
      id: _uuid.v4(),
      deviceSeq: deviceSeq,
      type: type,
      bookingId: bookingId,
      occurredAt: reading.occurredAt,
      approximate: reading.approximate,
      payload: payload,
    );
    await outbox.add(event);
    await _emitPendingCount();
    return event;
  }

  /// إضافة زبون حاضر — **متصل فقط** (design.md §10: «معطل دون اتصال»، و§6).
  /// يُرفض فورًا ومحليًا أثناء الانقطاع، دون محاولة شبكة، برسالة عربية واضحة.
  Future<Booking> createWalkIn({
    required String name,
    required String phone,
    required List<String> serviceIds,
  }) async {
    if (!isOnline) {
      throw const ApiError(
        code: 'OFFLINE_WALK_IN_REFUSED',
        message:
            'لا يمكن إضافة زبون حاضر دون اتصال بالإنترنت. الرجاء الانتظار حتى تعود الشبكة.',
      );
    }
    return api.createWalkIn(name: name, phone: phone, serviceIds: serviceIds);
  }

  /// يمسح كل التخزين المحلي — عند تسجيل الخروج أو إيقاف الحساب (design.md §6.1).
  Future<void> wipeOnLogout() async {
    stop();
    await store.wipe();
  }
}

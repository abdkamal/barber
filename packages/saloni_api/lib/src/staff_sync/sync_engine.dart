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
/// حالة الاتصال:
/// - لا تُبث حالة مطابقة للسابقة (نفس الحالة ونفس `since` ونفس عدد المعلّق).
/// - `since` ثابت ما دامت الحالة المستقرة (متصل/غير متصل) لم تتغير — النبضات
///   المتتالية الناجحة أو الفاشلة لا تجدّده.
/// - `syncing` تظهر فقط أثناء إرسال أحداث فعلية من الصندوق، لا مع كل نبضة.
/// - الحالة الابتدائية قبل أول محاولة `offline`؛ [hasAttempted] يميّزها عن
///   انقطاع فعلي.
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
    DateTime Function()? now,
  })  : clock = clock ?? MonotonicClock(),
        _uuid = uuid ?? const Uuid(),
        _onChanges = onChanges,
        _now = now ?? (() => DateTime.now().toUtc()) {
    outbox = Outbox(store: store, api: api);
    _state = ConnectionState(
      status: ConnectionStatus.offline,
      since: _now(),
      pendingCount: 0,
    );
  }

  final ApiClient api;
  final LocalStore store;
  final MonotonicClock clock;
  final Duration heartbeatInterval;
  final Uuid _uuid;
  final void Function(List<SyncChange> changes)? _onChanges;
  final DateTime Function() _now;

  late final Outbox outbox;
  Timer? _timer;
  bool _started = false;
  Future<void>? _tickInFlight;

  /// هل نجحت نبضة واحدة على الأقل في هذا التشغيل.
  bool hasConnected = false;

  /// هل انتهت محاولة اتصال واحدة على الأقل (ناجحة أو فاشلة). قبلها تكون
  /// الحالة `offline` ابتدائية لا تعني انقطاعًا فعليًا.
  bool hasAttempted = false;

  /// آخر نتيجة نبضة ناجحة.
  HeartbeatResult? lastHeartbeat;

  final StreamController<ConnectionState> _controller =
      StreamController<ConnectionState>.broadcast();
  late ConnectionState _state;

  /// الحالة المستقرة الأخيرة (online/offline) ومنذ متى — `since` لا يتجدد
  /// إلا بتغيّرها.
  ConnectionStatus? _settled;
  DateTime? _settledSince;

  /// حالة الاتصال الحالية والتيار المباشر لتغيّراتها (لشريط الاتصال).
  ConnectionState get state => _state;
  Stream<ConnectionState> get connectionState => _controller.stream;

  bool get isOnline => _state.status != ConnectionStatus.offline;

  void _emit(ConnectionState next) {
    if (next.status == _state.status &&
        next.since == _state.since &&
        next.pendingCount == _state.pendingCount) {
      return;
    }
    _state = next;
    if (!_controller.isClosed) _controller.add(next);
  }

  /// ينتقل لحالة مستقرة؛ `since` يبقى كما هو إن لم تتغير.
  void _settle(ConnectionStatus status, int pending) {
    if (_settled != status) {
      _settled = status;
      _settledSince = _now();
    }
    _emit(ConnectionState(
      status: status,
      since: _settledSince!,
      pendingCount: pending,
    ));
  }

  Future<void> _emitPendingCount() async {
    _emit(_state.copyWith(pendingCount: await outbox.pendingCount()));
  }

  /// يُستدعى مرة عند بدء تشغيل شاشة «طابوري»: يسترجع مرساة الساعة الرتيبة
  /// المحفوظة، ثم يبدأ حلقة النبضة/المزامنة كل [heartbeatInterval].
  Future<void> start() async {
    if (_started) return;
    _started = true;
    final lastServerTime = await store.getLastServerTime();
    if (lastServerTime != null && !clock.hasAnchor) {
      clock.restoreAnchor(lastServerTime);
    }
    await _emitPendingCount();
    unawaited(sync());
    _timer = Timer.periodic(heartbeatInterval, (_) => sync());
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

  /// دورة مزامنة واحدة (تُستدعى دوريًا): إرسال المستحق من الصندوق، نبضة،
  /// ثم سحب التغييرات. لا تتداخل دورتان — الاستدعاء أثناء دورة جارية ينتظرها.
  Future<void> sync({bool force = false}) {
    return _tickInFlight ??= _tick(force: force).whenComplete(() {
      _tickInFlight = null;
    });
  }

  /// يرسل كل الصندوق الآن متجاوزًا التراجع الأُسّي، ثم نبضة وسحب — لزر
  /// «تحديث» أو عند عودة الشبكة.
  Future<OutboxFlushResult> flushNow() async {
    await _tickInFlight;
    final result = await _flush(force: true);
    await sync();
    return result;
  }

  Future<OutboxFlushResult> _flush({required bool force}) async {
    final pending = await outbox.pendingCount();
    if (pending > 0 && _settled == ConnectionStatus.online) {
      _emit(_state.copyWith(status: ConnectionStatus.syncing));
    }
    final r = await outbox.flush(force: force);
    if (r.error != null && r.error!.isNetwork) {
      hasAttempted = true;
      _settle(ConnectionStatus.offline, r.remaining);
    } else if (_state.status == ConnectionStatus.syncing) {
      _settle(ConnectionStatus.online, r.remaining);
    } else {
      _emit(_state.copyWith(pendingCount: r.remaining));
    }
    return r;
  }

  Future<void> _tick({bool force = false}) async {
    try {
      await _flush(force: force);
      final hb = await api.heartbeat(deviceSeq: await store.currentDeviceSeq());
      lastHeartbeat = hb;
      var cursor = await store.getSyncCursor();
      final changes = <SyncChange>[];
      late SyncPullResult pull;
      do {
        pull = await api.pullSync(cursor);
        changes.addAll(pull.changes);
        cursor = pull.seq;
        await store.saveSyncCursor(cursor);
      } while (pull.hasMore && pull.changes.isNotEmpty);
      clock.anchor(pull.serverTime);
      await store.saveLastServerTime(pull.serverTime);
      hasConnected = true;
      hasAttempted = true;
      _settle(ConnectionStatus.online, await outbox.pendingCount());
      if (changes.isNotEmpty) _onChanges?.call(changes);
    } on ApiError {
      hasAttempted = true;
      _settle(ConnectionStatus.offline, await outbox.pendingCount());
    } catch (_) {
      // رد غير متوقع من السيرفر (تحليل JSON…) — لا يُعدّ انقطاعًا؛ يُعاد
      // المحاولة في الدورة التالية.
      hasAttempted = true;
    }
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
  /// حالة «مزامنة» تُعدّ اتصالًا.
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
    try {
      return await api.createWalkIn(
          name: name, phone: phone, serviceIds: serviceIds);
    } on ApiError catch (e) {
      if (e.isNetwork) _settle(ConnectionStatus.offline, _state.pendingCount);
      rethrow;
    }
  }

  /// ق40: يوقف الحلقة ويصدّر أحداث الصندوق كلها لرفعها عبر مسار المدير
  /// (الحساب موقوف فلا يستطيع المحرك إرسالها بنفسه).
  Future<List<DeviceEvent>> exportPendingForRecovery() async {
    stop();
    return outbox.exportPending();
  }

  /// يمسح كل التخزين المحلي — عند تسجيل الخروج أو إيقاف الحساب (design.md §6.1).
  Future<void> wipeOnLogout() async {
    stop();
    await store.wipe();
  }
}

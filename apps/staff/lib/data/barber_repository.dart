import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:saloni_api/saloni_api.dart' as sa;
import 'package:saloni_api/staff_sync.dart';

import '../core/format.dart';
import '../core/platform/device_services.dart';
import '../core/platform/storage.dart';
import 'models.dart';
import 'queue_logic.dart';

/// حالة الاتصال كما يعرضها شريط الاتصال الدائم.
enum LinkStatus { online, syncing, offline }

class ActiveBreak {
  const ActiveBreak(this.kind, this.since);
  final sa.BreakKind kind;
  final DateTime since;
}

/// مستودع طابور الحلاق — فوق `StaffSyncEngine` (design.md §6).
///
/// كل إجراء للحلاق يُسجَّل حدثًا في الصندوق ويُطبَّق محليًا فورًا؛ الشبكة لا
/// تُنتظر أبدًا (عدا إضافة زبون حاضر ومعاينة الأثر، وهما «متصل فقط»).
class BarberRepository extends ChangeNotifier {
  BarberRepository({
    required this.api,
    required Future<LocalStoreHandle> Function() openStore,
    required this.device,
    this.currency = const Currency('SAR', 'ر.س', 2),
    this.heartbeat = const Duration(seconds: 30),
    DateTime Function()? clock,
    void Function()? onHandleReleased,
  })  : _openStore = openStore,
        _onHandleReleased = onHandleReleased,
        _now = clock ?? DateTime.now;

  final sa.ApiClient api;
  final DeviceServices device;
  final Currency currency;
  final Duration heartbeat;
  final Future<LocalStoreHandle> Function() _openStore;

  /// يُستدعى بعد إغلاق أو مسح مقبض القاعدة، ليُصفّر منسّق المقابض في
  /// `AppServices` (`activeHandle`) — يمنع فتح مقبض ثانٍ متزامن لاحقًا.
  final void Function()? _onHandleReleased;
  final DateTime Function() _now;

  LocalStoreHandle? _handle;
  StaffSyncEngine? _engine;
  StreamSubscription<ConnectionState>? _sub;
  bool _disposed = false;
  bool _refreshing = false;

  // ---------------- الحالة المعروضة ----------------
  bool ready = false;
  String? loadError;
  List<QueueEntry> entries = const [];
  List<sa.Service> services = const [];
  List<sa.BreakPeriod> breaks = const [];

  /// فترات «حاضرون فقط» اليوم (ق33): لا حجوزات تطبيق، للزبائن الحاضرين فقط.
  List<sa.TimeWindow> walkInOnly = const [];
  Map<String, dynamic> settings = const {};
  ActiveBreak? activeBreak;
  bool absentToday = false;

  /// لا دوام لهذا الحلاق اليوم (`day: null` من السيرفر).
  bool noShiftToday = false;
  List<PaymentView> serverPayments = const [];

  /// حجوزات `in_service` من يوم عمل سابق أُغلق قبل إنهائها (ق24) — من
  /// `unfinishedFromPreviousDay` في `GET /staff/today`. تُعرض في قسم منفصل
  /// أعلى «طابوري» وتُنهى/تُدفع عبر الصندوق مثل أي حجز آخر.
  List<QueueEntry> unfinishedFromPreviousDay = const [];

  LinkStatus link = LinkStatus.syncing;
  DateTime? offlineSince;
  int pending = 0;
  DateTime? lastSyncAt;
  final Set<String> _overrunAlerted = {};

  StaffSyncEngine? get engine => _engine;
  bool get isOnline => link == LinkStatus.online;

  List<QueueEntry> get active => activeOrdered(entries);
  QueueEntry? get current => currentInService(entries);
  List<QueueEntry> get upcoming =>
      active.where((e) => e.status != sa.BookingStatus.inService).toList();

  QueueEntry? get called {
    for (final e in entries) {
      if (e.status == sa.BookingStatus.called) return e;
    }
    return null;
  }

  List<QueueEntry> get closingDecisionsNeeded =>
      entries.where((e) => e.needsClosingDecision).toList();

  int get maxDisconnectMinutes =>
      (settings['maxDisconnectWindowMinutes'] as num?)?.toInt() ?? 120;

  int get overrunPercent =>
      (settings['overrunAlertPercent'] as num?)?.toInt() ?? 100;

  /// ق3: هل الحجز البعيد متوقف عند هذا الحلاق أثناء الانقطاع؟
  bool get remoteBookingPaused {
    if (link != LinkStatus.offline || offlineSince == null) return false;
    final work = remainingWorkMinutes(entries, offlineSince!);
    if (work < maxDisconnectMinutes) return true;
    return _now().difference(offlineSince!).inMinutes >= maxDisconnectMinutes;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  // ---------------- دورة الحياة ----------------

  Future<void> start() async {
    try {
      _handle = await _openStore();
    } catch (e) {
      loadError = 'تعذّر فتح التخزين المحلي';
      ready = true;
      _notify();
      return;
    }
    if (_disposed) return;
    await _loadLocal();
    final engine = StaffSyncEngine(
      api: api,
      store: _handle!.store,
      heartbeatInterval: heartbeat,
      onChanges: (_) => unawaited(refresh()),
    );
    _engine = engine;
    _sub = engine.connectionState.listen(_onConnection);
    ready = true;
    _notify();
    await refresh();
    if (_disposed) return;
    await engine.start();
    unawaited(device.startKeepAlive(
      title: 'صالوني — الطاقم',
      text: _keepAliveText(),
    ));
  }

  String _keepAliveText() {
    final n = upcoming.length;
    switch (link) {
      case LinkStatus.offline:
        return pending > 0
            ? 'غير متصل — ${digits('$pending')} إجراء بانتظار المزامنة'
            : 'غير متصل — طابورك محفوظ على الجهاز';
      case LinkStatus.syncing:
      case LinkStatus.online:
        return n == 0 ? 'متصل — لا أحد في الانتظار' : 'متصل — ${digits('$n')} في طابورك';
    }
  }

  String? _lastKeepAliveText;
  void _updateKeepAlive() {
    final t = _keepAliveText();
    if (t == _lastKeepAliveText) return;
    _lastKeepAliveText = t;
    unawaited(device.updateKeepAlive(title: 'صالوني — الطاقم', text: t));
  }

  /// يعكس حالة المحرك على الشريط. المحرك لا يبث حالة مكررة، و`since` ثابت
  /// ما دامت الحالة المستقرة لم تتغير، و«مزامنة» لا تظهر إلا أثناء إرسال أحداث.
  void _onConnection(ConnectionState s) {
    pending = s.pendingCount;
    switch (s.status) {
      case ConnectionStatus.syncing:
        if (link != LinkStatus.offline) link = LinkStatus.syncing;
      case ConnectionStatus.offline:
        // الحالة الابتدائية للمحرك (قبل أول محاولة) ليست انقطاعًا فعليًا.
        if (_engine?.hasAttempted ?? false) {
          link = LinkStatus.offline;
          offlineSince = s.since;
        }
      case ConnectionStatus.online:
        final wasOffline = link == LinkStatus.offline;
        link = LinkStatus.online;
        offlineSince = null;
        lastSyncAt = _now();
        if (wasOffline) unawaited(refresh());
    }
    _updateKeepAlive();
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    final engine = _engine;
    _engine = null;
    if (engine != null) unawaited(engine.dispose());
    final h = _handle;
    _handle = null;
    if (h != null) unawaited(h.close().whenComplete(() => _onHandleReleased?.call()));
    super.dispose();
  }

  /// الخروج: يمسح التخزين المحلي والمفتاح ويوقف الخدمة الأمامية (§6.1).
  Future<void> wipeAll() async {
    final engine = _engine;
    if (engine != null) await engine.wipeOnLogout();
    final h = _handle;
    _handle = null;
    if (h != null) await h.destroy();
    _onHandleReleased?.call();
    await device.stopKeepAlive();
  }

  // ---------------- التخزين المحلي ----------------

  Future<void> _loadLocal() async {
    final store = _handle!.store;
    try {
      services = await store.getServices();
      breaks = await store.getBreaks();
      final all = await store.getSettings();
      final app = (all['_app'] as Map?)?.cast<String, dynamic>() ?? const {};
      settings = Map<String, dynamic>.from(all)..remove('_app');
      final details = (app['details'] as Map?)?.cast<String, dynamic>() ?? const {};
      final queue = await store.getQueue();
      entries = [
        for (final b in queue)
          QueueEntry.from(b, services,
              local: (details[b.id] as Map?)?.cast<String, dynamic>()),
      ];
      final prevDetails =
          (app['previousDayDetails'] as Map?)?.cast<String, dynamic>() ?? const {};
      final prevQueue = (app['previousDayQueue'] as List?) ?? const [];
      unfinishedFromPreviousDay = [
        for (final j in prevQueue)
          QueueEntry.from(
            sa.Booking.fromJson((j as Map).cast<String, dynamic>()),
            services,
            local: (prevDetails[(j)['id']] as Map?)?.cast<String, dynamic>(),
          ),
      ];
      absentToday = app['absentToday'] == true;
      final br = app['activeBreak'];
      if (br is Map) {
        activeBreak = ActiveBreak(
          sa.BreakKind.fromWire(br['kind'] as String),
          DateTime.parse(br['since'] as String),
        );
      }
      pending = (await store.getOutbox()).length;
    } catch (_) {
      // بيانات محلية تالفة — نكمل بطابور فارغ حتى تصل بيانات السيرفر.
    }
  }

  Future<void> _saveLocal() async {
    final store = _handle?.store;
    if (store == null) return;
    await store.saveQueue([for (final e in entries) e.toBooking()]);
    await store.saveServices(services);
    await store.saveBreaks(breaks);
    await store.saveSettings({
      ...settings,
      '_app': {
        'details': {for (final e in entries) e.id: e.extrasJson()},
        'previousDayQueue': [
          for (final e in unfinishedFromPreviousDay) e.toBooking().toJson(),
        ],
        'previousDayDetails': {
          for (final e in unfinishedFromPreviousDay) e.id: e.extrasJson(),
        },
        'absentToday': absentToday,
        if (activeBreak != null)
          'activeBreak': {
            'kind': activeBreak!.kind.toWire(),
            'since': activeBreak!.since.toUtc().toIso8601String(),
          },
      },
    });
  }

  // ---------------- المزامنة ----------------

  /// يرسل الصندوق ثم يجلب طابور اليوم من السيرفر. لا يرمي عند الانقطاع.
  Future<void> refresh() async {
    final engine = _engine;
    if (engine == null || _refreshing || _disposed) return;
    _refreshing = true;
    try {
      // تحديث يدوي أو بعد عودة الاتصال: أرسل كل المعلّق الآن متجاوزًا مهلة
      // التراجع الأُسّي — عبر `engine.flushNow()` لا `outbox.flush` مباشرة،
      // فهي الوحيدة التي تنتظر أي دورة مزامنة جارية (`_tickInFlight`) فلا
      // يتزامن إرسالان معًا (design.md §6.2).
      final beforeFlush = {for (final o in await engine.store.getOutbox()) o.event.id: o.event};
      final flushResult = await engine.flushNow();
      _recordRejected(flushResult.rejected, beforeFlush);
      final today = await api.getStaffToday();
      // ق24: حجوزات متوقعة بعد الإغلاق وتنتظر قرار الحلاق.
      final warnings = today.closingWarnings.toSet();
      walkInOnly = today.walkInOnly;
      noShiftToday = !today.hasShift;
      if (today.day?.absentToday ?? false) absentToday = true;
      // استراحة مفتوحة على السيرفر (بدأها الحلاق من جهاز آخر أو قبل إعادة التشغيل).
      final open = today.openBreak;
      if (open != null && activeBreak == null) {
        activeBreak = ActiveBreak(open.kind, open.start);
      } else if (open == null && activeBreak != null) {
        final pendingBreak = (await engine.store.getOutbox())
            .any((o) => o.event.type == sa.DeviceEventType.breakStarted);
        if (!pendingBreak) activeBreak = null;
      }
      // حالة محلية لا يرسلها السيرفر (قرار الإغلاق، الدفع المؤكد محليًا).
      final localById = {for (final e in entries) e.id: e.extrasJson()};
      final localPrevById = {
        for (final e in unfinishedFromPreviousDay) e.id: e.extrasJson(),
      };
      services = today.services;
      breaks = today.breaks;
      settings = today.settings;
      var fresh = [
        for (final b in today.queue)
          QueueEntry.from(b, services,
              local: localById[b.id], pastClosing: warnings.contains(b.id)),
      ];
      // إبقاء المنجز محليًا (للدفعات) إن لم يعد السيرفر يرسله.
      for (final e in entries) {
        if (e.status == sa.BookingStatus.done && !fresh.any((f) => f.id == e.id)) {
          fresh.add(e);
        }
      }
      // إعادة تطبيق ما لم يُرسل بعد فوق حالة السيرفر.
      final outbox = await engine.store.getOutbox();
      for (final o in outbox) {
        fresh = applyEvent(fresh, o.event, services, _now(), breaks: breaks, walkInOnly: walkInOnly);
      }
      entries = fresh;
      // حجوزات يوم سابق أُغلق وما زالت `in_service` (ق24) — تُنهى وتُدفع عبر
      // الصندوق مثل أي حجز آخر؛ إعادة تطبيق ما لم يُرسل بعد فوقها أيضًا.
      var freshPrev = [
        for (final b in today.unfinishedFromPreviousDay)
          QueueEntry.from(b, services, local: localPrevById[b.id]),
      ];
      for (final o in outbox) {
        freshPrev = applyEvent(freshPrev, o.event, services, _now());
      }
      unfinishedFromPreviousDay = freshPrev;
      pending = outbox.length;
      if (settings['absentToday'] == true) absentToday = true;
      loadError = null;
      if (link != LinkStatus.online) {
        link = LinkStatus.online;
        offlineSince = null;
      }
      lastSyncAt = _now();
      await _saveLocal();
    } on sa.ApiError catch (e) {
      if (e.code == 'NETWORK_ERROR' || e.code == 'TIMEOUT') {
        if (link != LinkStatus.offline) {
          link = LinkStatus.offline;
          offlineSince ??= _now();
        }
      } else if (e.code != 'SIGNED_OUT') {
        loadError = e.message;
      }
    } catch (e) {
      loadError = 'تعذّر قراءة بيانات الطابور';
    } finally {
      _refreshing = false;
      _updateKeepAlive();
      _notify();
    }
  }

  // ---------------- إجراءات الحلاق (عبر الصندوق) ----------------

  Future<sa.DeviceEvent?> _record(
    sa.DeviceEventType type, {
    String? bookingId,
    Map<String, dynamic> payload = const {},
  }) async {
    final engine = _engine;
    if (engine == null) return null;
    final event = await engine.recordEvent(type, bookingId: bookingId, payload: payload);
    entries = applyEvent(entries, event, services, _now(), breaks: breaks, walkInOnly: walkInOnly);
    pending = await engine.outbox.pendingCount();
    if (link == LinkStatus.online) {
      // نرسل في الخلفية؛ الواجهة لا تنتظر الشبكة.
      unawaited(_flushSoon());
    }
    await _saveLocal();
    _updateKeepAlive();
    _notify();
    return event;
  }

  Future<void> _flushSoon() async {
    final engine = _engine;
    if (engine == null || _disposed) return;
    final beforeFlush = {for (final o in await engine.store.getOutbox()) o.event.id: o.event};
    // إرسال فوري (يتجاوز التراجع) ثم نبضة وسحب — المحرك يحدّث الشريط والعدد.
    final r = await engine.flushNow();
    if (_disposed) return;
    pending = r.remaining;
    _recordRejected(r.rejected, beforeFlush);
    _notify();
  }

  /// أحداث رفضها السيرفر في آخر إرسال (انتقال غير صالح — design.md §6.2)،
  /// لتُعرض للحلاق برسالة عربية واضحة بدل أن تختفي بصمت.
  List<RejectedEvent> lastRejectedEvents = const [];

  void _recordRejected(
    List<sa.SyncEventOutcome> rejected, [
    Map<String, sa.DeviceEvent> eventsById = const {},
  ]) {
    if (rejected.isEmpty) return;
    lastRejectedEvents = [
      ...lastRejectedEvents,
      for (final o in rejected)
        RejectedEvent(
          eventId: o.eventId,
          type: eventsById[o.eventId]?.type,
          bookingId: eventsById[o.eventId]?.bookingId,
          customerName: eventsById[o.eventId]?.bookingId == null
              ? null
              : entries.where((e) => e.id == eventsById[o.eventId]!.bookingId).firstOrNull?.name,
          reason: o.reason,
        ),
    ];
  }

  /// يمسح الأحداث المرفوضة بعد عرضها للحلاق (مثلًا بعد إغلاق شريط تنبيه).
  void clearRejectedEvents() {
    if (lastRejectedEvents.isEmpty) return;
    lastRejectedEvents = const [];
    _notify();
  }

  Future<void> startService(String bookingId) =>
      _record(sa.DeviceEventType.serviceStarted, bookingId: bookingId);

  Future<void> finishService(String bookingId) =>
      _record(sa.DeviceEventType.serviceFinished, bookingId: bookingId);

  Future<void> changeServices(String bookingId, List<String> serviceIds) =>
      _record(sa.DeviceEventType.servicesChanged,
          bookingId: bookingId, payload: {'serviceIds': serviceIds});

  /// ق10/ق21: مرة واحدة فقط — إلا أن يُعفى الحجز صراحة (ق23: تقديم مفاجئ).
  /// إن استُخدم التأجيل ولم يصرّح السيرفر بإعفاء (`canPostpone == false`)
  /// يُمنع محليًا؛ إن كان معفًى (`true`) أو غير معروف بعد (`null`، السيرفر لم
  /// يرسل الحقل) يُسمح محليًا ويُترك القرار النهائي للسيرفر — رفضه يظهر
  /// للحلاق برسالة واضحة (انظر `lastRejectedEvents`).
  Future<void> postpone(String bookingId, int steps) async {
    final e = entries.where((x) => x.id == bookingId).firstOrNull;
    if (e == null) throw StateError('الحجز غير موجود');
    if (e.postponementUsed && e.canPostpone == false) {
      throw StateError('التأجيل مستخدم لهذا الحجز');
    }
    await _record(sa.DeviceEventType.postponed,
        bookingId: bookingId, payload: {'steps': steps});
  }

  Future<void> waitForCustomer(String bookingId) =>
      _record(sa.DeviceEventType.waited, bookingId: bookingId);

  /// ق10: «لم يحضر» متاح فقط بعد استخدام التأجيل.
  Future<void> markNoShow(String bookingId) async {
    final e = entries.where((x) => x.id == bookingId).firstOrNull;
    if (e == null || !e.postponementUsed) {
      throw StateError('«لم يحضر» يُتاح بعد استخدام التأجيل');
    }
    await _record(sa.DeviceEventType.noShow, bookingId: bookingId);
  }

  Future<void> closingDecision(
    String bookingId,
    sa.ClosingDecision decision,
    String reason,
  ) =>
      _record(sa.DeviceEventType.closingDecision,
          bookingId: bookingId,
          payload: {'decision': decision.toWire(), 'reason': reason});

  Future<void> confirmPayment(String bookingId, int amountCents) =>
      _record(sa.DeviceEventType.paymentConfirmed,
          bookingId: bookingId, payload: {'amount': amountCents});

  // ---------------- حجوزات يوم سابق أُغلق (ق24) ----------------

  /// «إنهاء الخدمة» لحجز `in_service` من يوم عمل سابق أُغلق قبل إنهائه —
  /// نفس حدث الصندوق، لكنه يُطبَّق على [unfinishedFromPreviousDay] لا
  /// [entries] (الحجز ليس في طابور اليوم الحالي).
  Future<void> finishPreviousDayService(String bookingId) =>
      _recordOnPreviousDay(sa.DeviceEventType.serviceFinished, bookingId);

  /// «تأكيد الدفع» لحجز يوم سابق بعد إنهائه.
  Future<void> confirmPreviousDayPayment(String bookingId, int amountCents) =>
      _recordOnPreviousDay(sa.DeviceEventType.paymentConfirmed, bookingId,
          payload: {'amount': amountCents});

  Future<void> _recordOnPreviousDay(
    sa.DeviceEventType type,
    String bookingId, {
    Map<String, dynamic> payload = const {},
  }) async {
    final engine = _engine;
    if (engine == null) return;
    final event = await engine.recordEvent(type, bookingId: bookingId, payload: payload);
    unfinishedFromPreviousDay =
        applyEvent(unfinishedFromPreviousDay, event, services, _now());
    pending = await engine.outbox.pendingCount();
    if (link == LinkStatus.online) {
      unawaited(_flushSoon());
    }
    await _saveLocal();
    _notify();
  }

  Future<void> startBreak(sa.BreakKind kind) async {
    activeBreak = ActiveBreak(kind, _now());
    await _record(sa.DeviceEventType.breakStarted, payload: {'kind': kind.toWire()});
  }

  Future<void> endBreak() async {
    final b = activeBreak;
    if (b == null) return;
    activeBreak = null;
    await _record(sa.DeviceEventType.breakEnded, payload: {'kind': b.kind.toWire()});
  }

  /// ق26: «لن أعمل اليوم».
  Future<void> reportAbsentToday(String reason) async {
    absentToday = true;
    await _record(sa.DeviceEventType.absentToday, payload: {'reason': reason});
  }

  // ---------------- متصل فقط ----------------

  /// إضافة زبون حاضر — متصل فقط (design.md §10). يرمي `ApiError` برسالة عربية.
  Future<void> addWalkIn({
    required String name,
    required String phone,
    required List<String> serviceIds,
  }) async {
    final engine = _engine;
    if (engine == null || link == LinkStatus.offline) {
      throw const sa.ApiError(
        code: 'OFFLINE_WALK_IN_REFUSED',
        message: 'لا يمكن إضافة زبون حاضر دون اتصال بالإنترنت.',
      );
    }
    final booking =
        await engine.createWalkIn(name: name, phone: phone, serviceIds: serviceIds);
    final entry = QueueEntry.from(booking, services);
    entries = [...entries.where((e) => e.id != entry.id), entry];
    await _saveLocal();
    _notify();
    unawaited(refresh());
  }

  /// معاينة أثر تعديل الخدمة — متصل فقط (ق9، ق24).
  Future<ImpactPreview> previewImpact(String bookingId, List<String> serviceIds) async {
    final impact = await api.getStaffImpact(bookingId: bookingId, serviceIds: serviceIds);
    return ImpactPreview.fromImpact(impact);
  }

  /// الوقت المتوقع التقريبي لزبون حاضر جديد (آخر الطابور).
  DateTime estimateNextSlot() {
    final now = _now();
    var t = now;
    for (final e in active) {
      final start = e.status == sa.BookingStatus.inService ? (e.actualStart ?? now) : e.eta;
      final end = start.add(Duration(minutes: e.durationMin));
      if (end.isAfter(t)) t = end;
    }
    return t;
  }

  // ---------------- الدفعات ----------------

  Future<void> loadPayments() async {
    try {
      final list = await api.getStaffPayments();
      serverPayments = [
        for (final p in list)
          PaymentView(
            bookingId: p.bookingId,
            name: p.customerName ??
                entries.where((e) => e.id == p.bookingId).firstOrNull?.name ??
                'زبون',
            services: _servicesOf(p.bookingId),
            amountCents: p.amountCents,
            status: p.status,
            at: p.finishedAt ??
                entries.where((e) => e.id == p.bookingId).firstOrNull?.actualEnd ??
                p.confirmedAt,
          ),
      ];
      _notify();
    } on sa.ApiError {
      // دون اتصال: تُعرض الدفعات المعروفة محليًا.
    }
  }

  String _servicesOf(String bookingId) {
    final e = entries.where((x) => x.id == bookingId).firstOrNull;
    return e == null ? '' : serviceNames(e.serviceIds, services);
  }

  /// الدفعات: السيرفر + ما أُنهي أو أُكّد محليًا ولم يُزامن بعد.
  List<PaymentView> get payments {
    final byId = <String, PaymentView>{
      for (final p in serverPayments) p.bookingId: p,
    };
    for (final e in entries) {
      if (e.status != sa.BookingStatus.done) continue;
      final local = e.payment ?? sa.PaymentStatus.awaitingConfirmation;
      final existing = byId[e.id];
      if (existing == null ||
          (local == sa.PaymentStatus.confirmed &&
              existing.status != sa.PaymentStatus.confirmed)) {
        byId[e.id] = PaymentView(
          bookingId: e.id,
          name: e.name,
          services: serviceNames(e.serviceIds, services),
          amountCents: existing?.amountCents ?? e.priceCents,
          status: local == sa.PaymentStatus.confirmed
              ? sa.PaymentStatus.confirmed
              : (existing?.status ?? local),
          at: e.actualEnd,
        );
      }
    }
    final list = byId.values.toList()
      ..sort((a, b) => (b.at ?? DateTime(0)).compareTo(a.at ?? DateTime(0)));
    return list;
  }

  int get awaitingPayments =>
      payments.where((p) => p.status == sa.PaymentStatus.awaitingConfirmation).length;

  // ---------------- تنبيه تجاوز المدة (ق27) ----------------

  /// يعيد الخدمة الجارية إن تجاوزت للتو نسبة التنبيه (مرة واحدة لكل حجز).
  QueueEntry? checkOverrun() {
    final c = current;
    if (c == null || c.actualStart == null) return null;
    final elapsed = _now().difference(c.actualStart!).inSeconds / 60;
    if (elapsed * 100 >= c.durationMin * overrunPercent &&
        _overrunAlerted.add(c.id)) {
      unawaited(device.updateKeepAlive(
        title: 'تجاوزت الخدمة مدتها',
        text: 'تجاوزت خدمة ${c.name} مدتها المقدرة — لا تنسَ الضغط على «إنهاء»',
      ));
      _lastKeepAliveText = null;
      return c;
    }
    return null;
  }
}

import '../models/models.dart';

/// حالة حدث في صندوق الأحداث المحلي.
enum OutboxStatus { pending, sending }

/// حدث بانتظار الإرسال، مع عدد المحاولات ووقت إعادة المحاولة التالي
/// (تراجع أُسّي — design.md §6.2).
class OutboxEntry {
  const OutboxEntry({
    required this.event,
    this.status = OutboxStatus.pending,
    this.attempts = 0,
    this.nextRetryAt,
  });

  final DeviceEvent event;
  final OutboxStatus status;
  final int attempts;
  final DateTime? nextRetryAt;

  OutboxEntry copyWith({
    OutboxStatus? status,
    int? attempts,
    DateTime? nextRetryAt,
  }) =>
      OutboxEntry(
        event: event,
        status: status ?? this.status,
        attempts: attempts ?? this.attempts,
        nextRetryAt: nextRetryAt ?? this.nextRetryAt,
      );
}

/// تخزين محلي مشفّر لتطبيق الطاقم (design.md §6.1): طابور اليوم، الخدمات،
/// الاستراحات، الإعدادات، مؤشر المزامنة، صندوق الأحداث. تنفيذ [DriftLocalStore]
/// (في `drift_local_store.dart`) يخزّنها في SQLite؛ هذه الواجهة تجريدية بحتة
/// كي يبقى منطق المزامنة قابلًا للاختبار بمخزن في الذاكرة.
abstract class LocalStore {
  Future<List<Booking>> getQueue();
  Future<void> saveQueue(List<Booking> queue);

  Future<List<Service>> getServices();
  Future<void> saveServices(List<Service> services);

  Future<List<BreakPeriod>> getBreaks();
  Future<void> saveBreaks(List<BreakPeriod> breaks);

  Future<Map<String, dynamic>> getSettings();
  Future<void> saveSettings(Map<String, dynamic> settings);

  /// مؤشر المزامنة الحالي (`seq` من آخر `GET /sync?since=` أو `0`).
  Future<int> getSyncCursor();
  Future<void> saveSyncCursor(int seq);

  /// آخر وقت سيرفر معروف — لاسترجاع مرساة الساعة الرتيبة عند بدء التطبيق.
  Future<DateTime?> getLastServerTime();
  Future<void> saveLastServerTime(DateTime time);

  /// رقم تسلسل الجهاز التالي (متزايد دائمًا، حتى عبر إعادة التشغيل).
  Future<int> nextDeviceSeq();

  Future<List<OutboxEntry>> getOutbox();
  Future<void> putOutboxEntry(OutboxEntry entry);
  Future<void> removeOutboxEntry(String eventId);

  /// يمسح كل شيء — عند الخروج أو إيقاف الحساب (design.md §6.1).
  Future<void> wipe();
}

/// تنفيذ في الذاكرة — للاختبارات، ومرجع لسلوك [DriftLocalStore].
class InMemoryLocalStore implements LocalStore {
  List<Booking> _queue = const [];
  List<Service> _services = const [];
  List<BreakPeriod> _breaks = const [];
  Map<String, dynamic> _settings = const {};
  int _cursor = 0;
  DateTime? _lastServerTime;
  int _deviceSeq = 0;
  final Map<String, OutboxEntry> _outbox = {};

  @override
  Future<List<Booking>> getQueue() async => _queue;

  @override
  Future<void> saveQueue(List<Booking> queue) async => _queue = queue;

  @override
  Future<List<Service>> getServices() async => _services;

  @override
  Future<void> saveServices(List<Service> services) async =>
      _services = services;

  @override
  Future<List<BreakPeriod>> getBreaks() async => _breaks;

  @override
  Future<void> saveBreaks(List<BreakPeriod> breaks) async => _breaks = breaks;

  @override
  Future<Map<String, dynamic>> getSettings() async => _settings;

  @override
  Future<void> saveSettings(Map<String, dynamic> settings) async =>
      _settings = settings;

  @override
  Future<int> getSyncCursor() async => _cursor;

  @override
  Future<void> saveSyncCursor(int seq) async => _cursor = seq;

  @override
  Future<DateTime?> getLastServerTime() async => _lastServerTime;

  @override
  Future<void> saveLastServerTime(DateTime time) async =>
      _lastServerTime = time;

  @override
  Future<int> nextDeviceSeq() async => ++_deviceSeq;

  @override
  Future<List<OutboxEntry>> getOutbox() async {
    final entries = _outbox.values.toList()
      ..sort((a, b) => a.event.deviceSeq.compareTo(b.event.deviceSeq));
    return entries;
  }

  @override
  Future<void> putOutboxEntry(OutboxEntry entry) async =>
      _outbox[entry.event.id] = entry;

  @override
  Future<void> removeOutboxEntry(String eventId) async =>
      _outbox.remove(eventId);

  @override
  Future<void> wipe() async {
    _queue = const [];
    _services = const [];
    _breaks = const [];
    _settings = const {};
    _cursor = 0;
    _lastServerTime = null;
    _deviceSeq = 0;
    _outbox.clear();
  }
}

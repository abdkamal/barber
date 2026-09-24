import '../api_client.dart';
import '../models/models.dart';
import 'local_store.dart';

/// نتيجة محاولة إرسال (flush) واحدة.
class OutboxFlushResult {
  const OutboxFlushResult({
    required this.sent,
    required this.remaining,
    this.error,
    this.outcomes = const [],
  });

  /// عدد الأحداث التي طُبّقت أو تكررت (أُزيلت من الصندوق).
  final int sent;

  /// عدد الأحداث المتبقية في الصندوق بعد المحاولة.
  final int remaining;

  final ApiError? error;

  /// نتائج السيرفر لكل حدث أُرسل (بترتيب الإرسال).
  final List<SyncEventOutcome> outcomes;

  /// الأحداث التي رفضها السيرفر (أُزيلت من الصندوق).
  List<SyncEventOutcome> get rejected =>
      outcomes.where((o) => o.result == SyncEventResult.rejected).toList();

  bool get succeeded => error == null;
}

/// صندوق أحداث تطبيق الطاقم — design.md §6.2: يُحفظ كل حدث قبل الإرسال،
/// يُرسل بترتيب رقم تسلسل الجهاز، ويُعاد المحاولة بتراجع أُسّي عند الفشل.
class Outbox {
  Outbox({
    required this.store,
    required this.api,
    Duration baseBackoff = const Duration(seconds: 2),
    Duration maxBackoff = const Duration(seconds: 60),
    DateTime Function() now = DateTime.now,
  })  : _baseBackoff = baseBackoff,
        _maxBackoff = maxBackoff,
        _now = now;

  final LocalStore store;
  final ApiClient api;
  final Duration _baseBackoff;
  final Duration _maxBackoff;
  final DateTime Function() _now;

  /// يحفظ الحدث في الصندوق فورًا (قبل أي محاولة إرسال) — design.md §6.2.
  Future<void> add(DeviceEvent event) async {
    await store.putOutboxEntry(OutboxEntry(event: event));
  }

  /// عدد الأحداث بانتظار الإرسال حاليًا.
  Future<int> pendingCount() async => (await store.getOutbox()).length;

  /// ق40: كل أحداث الصندوق بترتيب رقم تسلسل الجهاز (متجاوزًا مهلة التراجع)،
  /// بأوقاتها المحسوبة بالساعة الرتيبة كما سُجّلت — لرفعها عبر مسار المدير
  /// حين يكون الحساب موقوفًا.
  Future<List<DeviceEvent>> exportPending() async =>
      [for (final e in await store.getOutbox()) e.event];

  /// ق40: يرفع المدير (بجلسته هو على هذا الجهاز) كل أحداث الصندوق نيابةً عن
  /// الحساب الموقوف [staffId]. كل حدث عاد بنتيجة يُزال من الصندوق (كلها
  /// نهائية: طُبّق، أو تكرر، أو رُفض)؛ ما لم يرد في الرد يبقى. عند فشل الرفع
  /// (شبكة، `409 ACCOUNT_NOT_SUSPENDED`…) يُرمى `ApiError` ويبقى الصندوق كما هو.
  Future<RecoveryReport> uploadForRecovery(String staffId) async {
    final events = await exportPending();
    final report = await api.recoverStaffEvents(staffId: staffId, events: events);
    final answered = {for (final o in report.results) o.eventId};
    for (final e in events) {
      if (answered.contains(e.id)) await store.removeOutboxEntry(e.id);
    }
    return report;
  }

  Duration _backoffFor(int attempts) {
    final millis = _baseBackoff.inMilliseconds * (1 << attempts.clamp(0, 10));
    final capped = millis.clamp(0, _maxBackoff.inMilliseconds);
    return Duration(milliseconds: capped);
  }

  /// يحاول إرسال كل الأحداث المستحقة الآن (`nextRetryAt` فات موعده أو غير
  /// محدد)، بترتيب رقم تسلسل الجهاز. لا يُعيد المحاولة تلقائيًا هنا؛ المستدعي
  /// (`StaffSyncEngine`) يستدعيها دوريًا.
  ///
  /// `force: true` يرسل كل الصندوق متجاوزًا مهلة التراجع الأُسّي (تحديث يدوي
  /// أو عودة الاتصال).
  Future<OutboxFlushResult> flush({bool force = false}) async {
    final all = await store.getOutbox();
    final now = _now();
    final due = force
        ? all
        : all
            .where((e) =>
                e.nextRetryAt == null || !e.nextRetryAt!.isAfter(now))
            .toList();
    if (due.isEmpty) {
      return OutboxFlushResult(sent: 0, remaining: all.length);
    }

    var sent = 0;
    final received = <SyncEventOutcome>[];
    // حدّ السيرفر 200 حدث للدفعة؛ الدفعات بالترتيب، والتوقف عند أول فشل.
    for (var i = 0; i < due.length; i += 200) {
      final chunk = due.skip(i).take(200).toList();
      List<SyncEventOutcome> outcomes;
      try {
        outcomes = await api.pushSyncEvents(chunk.map((e) => e.event).toList());
      } on ApiError catch (e) {
        // فشل الإرسال — تراجع أُسّي لكل ما لم يُرسل بعد.
        for (final entry in due.skip(i)) {
          await store.putOutboxEntry(entry.copyWith(
            attempts: entry.attempts + 1,
            nextRetryAt: now.add(_backoffFor(entry.attempts + 1)),
          ));
        }
        final remaining = await store.getOutbox();
        return OutboxFlushResult(
            sent: sent,
            remaining: remaining.length,
            error: e,
            outcomes: received);
      }
      received.addAll(outcomes);
      sent += await _apply(chunk, outcomes, now);
    }
    final remaining = await store.getOutbox();
    return OutboxFlushResult(
        sent: sent, remaining: remaining.length, outcomes: received);
  }

  Future<int> _apply(
      List<OutboxEntry> chunk, List<SyncEventOutcome> outcomes, DateTime now) async {
    var sent = 0;
    final byId = {for (final o in outcomes) o.eventId: o};
    for (final entry in chunk) {
      final outcome = byId[entry.event.id];
      if (outcome == null) {
        // لم يرد ذكر هذا الحدث في الرد — يُعامل كفشل مؤقت، يُعاد لاحقًا.
        await store.putOutboxEntry(entry.copyWith(
          attempts: entry.attempts + 1,
          nextRetryAt: now.add(_backoffFor(entry.attempts + 1)),
        ));
        continue;
      }
      switch (outcome.result) {
        case SyncEventResult.applied:
        case SyncEventResult.duplicate:
          await store.removeOutboxEntry(entry.event.id);
          sent++;
        case SyncEventResult.rejected:
          // انتقال غير صالح — السيرفر يسجّله للمدير (design.md §6.2)؛ لا فائدة
          // من إعادة إرسال نفس الحدث.
          await store.removeOutboxEntry(entry.event.id);
      }
    }
    return sent;
  }
}

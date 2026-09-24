import '../api_client.dart';
import '../models/models.dart';
import 'local_store.dart';

/// نتيجة محاولة إرسال (flush) واحدة.
class OutboxFlushResult {
  const OutboxFlushResult({
    required this.sent,
    required this.remaining,
    this.error,
  });

  /// عدد الأحداث التي طُبّقت أو تكررت (أُزيلت من الصندوق).
  final int sent;

  /// عدد الأحداث المتبقية في الصندوق بعد المحاولة.
  final int remaining;

  final ApiError? error;

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

  Duration _backoffFor(int attempts) {
    final millis = _baseBackoff.inMilliseconds * (1 << attempts.clamp(0, 10));
    final capped = millis.clamp(0, _maxBackoff.inMilliseconds);
    return Duration(milliseconds: capped);
  }

  /// يحاول إرسال كل الأحداث المستحقة الآن (`nextRetryAt` فات موعده أو غير
  /// محدد)، بترتيب رقم تسلسل الجهاز. لا يُعيد المحاولة تلقائيًا هنا؛ المستدعي
  /// (`StaffSyncEngine`) يستدعيها دوريًا.
  Future<OutboxFlushResult> flush() async {
    final all = await store.getOutbox();
    final now = _now();
    final due = all.where((e) => e.nextRetryAt == null || !e.nextRetryAt!.isAfter(now)).toList();
    if (due.isEmpty) {
      return OutboxFlushResult(sent: 0, remaining: all.length);
    }

    List<SyncEventOutcome> outcomes;
    try {
      outcomes = await api.pushSyncEvents(due.map((e) => e.event).toList());
    } on ApiError catch (e) {
      // فشل الإرسال بالكامل — تراجع أُسّي لكل الأحداث المستحقة.
      for (final entry in due) {
        await store.putOutboxEntry(entry.copyWith(
          attempts: entry.attempts + 1,
          nextRetryAt: now.add(_backoffFor(entry.attempts + 1)),
        ));
      }
      final remaining = await store.getOutbox();
      return OutboxFlushResult(sent: 0, remaining: remaining.length, error: e);
    }

    var sent = 0;
    final byId = {for (final o in outcomes) o.eventId: o};
    for (final entry in due) {
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
    final remaining = await store.getOutbox();
    return OutboxFlushResult(sent: sent, remaining: remaining.length);
  }
}

import 'package:saloni_api/saloni_api.dart' as sa;

import 'models.dart';

/// منطق محلي نقي لتطبيق أحداث الحلاق على الطابور فورًا (دون انتظار الشبكة —
/// design.md §6). الحقيقة النهائية من السيرفر تحل محل هذه النتيجة عند
/// المزامنة التالية؛ الأحداث التي لم تُرسل بعد يُعاد تطبيقها فوقها.

/// ترتيب العرض: في الخدمة ← المستدعى ← المنتظرون حسب الترتيب.
List<QueueEntry> activeOrdered(List<QueueEntry> all) {
  int rank(QueueEntry e) => switch (e.status) {
        sa.BookingStatus.inService => 0,
        sa.BookingStatus.called => 1,
        _ => 2,
      };
  final list = all.where((e) => e.isActive).toList();
  list.sort((a, b) {
    final r = rank(a).compareTo(rank(b));
    if (r != 0) return r;
    final p = a.position.compareTo(b.position);
    if (p != 0) return p;
    return a.eta.compareTo(b.eta);
  });
  return list;
}

QueueEntry? currentInService(List<QueueEntry> all) {
  for (final e in all) {
    if (e.status == sa.BookingStatus.inService) return e;
  }
  return null;
}

/// نافذة تمنع الجدولة فيها: استراحة حقيقية، أو فترة «حاضرون فقط» (ق33) التي
/// تمنع حجوزات التطبيق فقط وتبقى مفتوحة للحاضرين — تطابق `blockingBreaks`/
/// `fitAroundBreaks` في محرك السيرفر (`packages/engine/src/timeline.ts`).
class _BlockWindow {
  const _BlockWindow(this.start, this.end, {this.walkInOnly = false});
  final DateTime start;
  final DateTime end;
  final bool walkInOnly;
}

List<_BlockWindow> _windows(List<sa.BreakPeriod> breaks, List<sa.TimeWindow> walkInOnly) => [
      for (final b in breaks) _BlockWindow(b.start, b.end),
      for (final w in walkInOnly) _BlockWindow(w.start, w.end, walkInOnly: true),
    ];

/// النوافذ التي تحجز على هذا الحجز: الحاضر يتجاوز فترات «حاضرون فقط» (ق33).
List<_BlockWindow> _blocking(List<_BlockWindow> windows, bool isWalkIn) =>
    isWalkIn ? windows.where((w) => !w.walkInOnly).toList() : windows;

/// أبكر بدء ≥ `from` تتسع فيه خدمة بمدة [durationMin] كاملة خارج كل نافذة
/// حاجبة — الخدمة لا تتقاطع أبدًا مع استراحة (design.md §5.1).
DateTime _fitAroundBreaks(DateTime from, int durationMin, List<_BlockWindow> windows) {
  var start = from;
  var moved = true;
  while (moved) {
    moved = false;
    for (final w in windows) {
      final end = start.add(Duration(minutes: durationMin));
      if (start.isBefore(w.end) && end.isAfter(w.start)) {
        start = w.end;
        moved = true;
      }
    }
  }
  return start;
}

/// يعيد حساب الأوقات المتوقعة محليًا بعد إجراء (تقديري حتى تصل أوقات
/// السيرفر) — يحاكي محرك الجدولة (design.md §5.1): لا تتقاطع خدمة مع
/// استراحة، وفترات «حاضرون فقط» (ق33) تحجب حجوزات التطبيق فقط.
List<QueueEntry> recomputeEtas(
  List<QueueEntry> all,
  DateTime now, {
  List<sa.BreakPeriod> breaks = const [],
  List<sa.TimeWindow> walkInOnly = const [],
}) {
  final windows = _windows(breaks, walkInOnly);
  final ordered = activeOrdered(all);
  final updated = <String, QueueEntry>{};
  var t = now;
  var pos = 1;
  for (final e in ordered) {
    if (e.status == sa.BookingStatus.inService) {
      final start = e.actualStart ?? now;
      var end = start.add(Duration(minutes: e.durationMin));
      if (end.isBefore(now)) end = now;
      t = end;
      updated[e.id] = e.copyWith(position: 0);
      continue;
    }
    var start = t;
    if (e.requestedAt != null && e.requestedAt!.isAfter(start)) {
      start = e.requestedAt!;
    }
    start = _fitAroundBreaks(start, e.durationMin, _blocking(windows, e.walkIn));
    updated[e.id] = e.copyWith(eta: start, position: pos++);
    t = start.add(Duration(minutes: e.durationMin));
  }
  return [for (final e in all) updated[e.id] ?? e];
}

/// يطبّق حدث جهاز على الطابور المحلي. [breaks]/[walkInOnly]: يوم الحلاق
/// الحالي (design.md §5.1، ق33) لإعادة الحساب دون تقاطع الخدمات معها.
List<QueueEntry> applyEvent(
  List<QueueEntry> all,
  sa.DeviceEvent event,
  List<sa.Service> services,
  DateTime now, {
  List<sa.BreakPeriod> breaks = const [],
  List<sa.TimeWindow> walkInOnly = const [],
}) {
  final id = event.bookingId;
  QueueEntry? target;
  for (final e in all) {
    if (e.id == id) target = e;
  }
  List<QueueEntry> replace(QueueEntry updated) =>
      [for (final e in all) e.id == updated.id ? updated : e];
  List<QueueEntry> recompute(List<QueueEntry> list) =>
      recomputeEtas(list, now, breaks: breaks, walkInOnly: walkInOnly);

  switch (event.type) {
    case sa.DeviceEventType.serviceStarted:
      if (target == null) return all;
      final list = [
        for (final e in all)
          if (e.id == target.id)
            e.copyWith(status: sa.BookingStatus.inService, actualStart: event.occurredAt)
          // ق22: بدء زبون قبل المستدعى = تأجيل للمستدعى بدور.
          else if (e.status == sa.BookingStatus.called)
            e.copyWith(status: sa.BookingStatus.waiting, postponementUsed: true)
          else
            e,
      ];
      return recompute(list);

    case sa.DeviceEventType.serviceFinished:
      if (target == null) return all;
      final done = target.copyWith(
        status: sa.BookingStatus.done,
        actualEnd: event.occurredAt,
        payment: target.payment ?? sa.PaymentStatus.awaitingConfirmation,
      );
      return recompute(replace(done));

    case sa.DeviceEventType.servicesChanged:
      if (target == null) return all;
      final ids = (event.payload['serviceIds'] as List?)?.cast<String>() ?? target.serviceIds;
      final dur = sumDuration(ids, services);
      final price = sumPrice(ids, services);
      return recompute(
        replace(target.copyWith(
          serviceIds: ids,
          durationMin: dur > 0 ? dur : target.durationMin,
          priceCents: price > 0 ? price : target.priceCents,
        )),
      );

    case sa.DeviceEventType.postponed:
      if (target == null) return all;
      final steps = (event.payload['steps'] as num?)?.toInt() ?? 1;
      return recompute(_postpone(all, target, steps));

    case sa.DeviceEventType.noShow:
      if (target == null) return all;
      return recompute(replace(target.copyWith(status: sa.BookingStatus.noShow)));

    case sa.DeviceEventType.closingDecision:
      if (target == null) return all;
      final cancel = event.payload['decision'] == sa.ClosingDecision.cancel.toWire();
      return recompute(
        replace(target.copyWith(
          status: cancel ? sa.BookingStatus.cancelled : null,
          closingDecided: true,
        )),
      );

    case sa.DeviceEventType.paymentConfirmed:
      if (target == null) return all;
      return replace(target.copyWith(payment: sa.PaymentStatus.confirmed));

    case sa.DeviceEventType.waited:
    case sa.DeviceEventType.breakStarted:
    case sa.DeviceEventType.breakEnded:
    case sa.DeviceEventType.absentToday:
      return all;
  }
}

/// ق21: التأجيل مرة واحدة بعدد أدوار، ثم يُستدعى التالي فورًا.
List<QueueEntry> _postpone(List<QueueEntry> all, QueueEntry target, int steps) {
  final waiting = activeOrdered(all)
      .where((e) => e.status != sa.BookingStatus.inService)
      .toList();
  final idx = waiting.indexWhere((e) => e.id == target.id);
  if (idx < 0) return all;
  waiting.removeAt(idx);
  final insertAt = (idx + steps).clamp(0, waiting.length);
  waiting.insert(
    insertAt,
    target.copyWith(status: sa.BookingStatus.waiting, postponementUsed: true),
  );
  final hasCalled = waiting.any((e) => e.status == sa.BookingStatus.called);
  final byId = <String, QueueEntry>{};
  for (var i = 0; i < waiting.length; i++) {
    var e = waiting[i].copyWith(position: i + 1);
    if (!hasCalled && i == 0 && e.id != target.id) {
      e = e.copyWith(status: sa.BookingStatus.called);
    }
    byId[e.id] = e;
  }
  return [for (final e in all) byId[e.id] ?? e];
}

/// مجموع العمل المعروف المتبقي بالدقائق (لقاعدة ق3 عند الانقطاع).
int remainingWorkMinutes(List<QueueEntry> all, DateTime now) {
  var total = 0;
  for (final e in activeOrdered(all)) {
    if (e.status == sa.BookingStatus.inService) {
      final end = (e.actualStart ?? now).add(Duration(minutes: e.durationMin));
      final left = end.difference(now).inMinutes;
      total += left > 0 ? left : 0;
    } else {
      total += e.durationMin;
    }
  }
  return total;
}

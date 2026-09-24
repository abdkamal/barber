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

/// يعيد حساب الأوقات المتوقعة محليًا بعد إجراء (تقديري حتى تصل أوقات السيرفر).
List<QueueEntry> recomputeEtas(List<QueueEntry> all, DateTime now) {
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
    updated[e.id] = e.copyWith(eta: start, position: pos++);
    t = start.add(Duration(minutes: e.durationMin));
  }
  return [for (final e in all) updated[e.id] ?? e];
}

/// يطبّق حدث جهاز على الطابور المحلي.
List<QueueEntry> applyEvent(
  List<QueueEntry> all,
  sa.DeviceEvent event,
  List<sa.Service> services,
  DateTime now,
) {
  final id = event.bookingId;
  QueueEntry? target;
  for (final e in all) {
    if (e.id == id) target = e;
  }
  List<QueueEntry> replace(QueueEntry updated) =>
      [for (final e in all) e.id == updated.id ? updated : e];

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
      return recomputeEtas(list, now);

    case sa.DeviceEventType.serviceFinished:
      if (target == null) return all;
      final done = target.copyWith(
        status: sa.BookingStatus.done,
        actualEnd: event.occurredAt,
        payment: target.payment ?? sa.PaymentStatus.awaitingConfirmation,
      );
      return recomputeEtas(replace(done), now);

    case sa.DeviceEventType.servicesChanged:
      if (target == null) return all;
      final ids = (event.payload['serviceIds'] as List?)?.cast<String>() ?? target.serviceIds;
      final dur = sumDuration(ids, services);
      final price = sumPrice(ids, services);
      return recomputeEtas(
        replace(target.copyWith(
          serviceIds: ids,
          durationMin: dur > 0 ? dur : target.durationMin,
          priceCents: price > 0 ? price : target.priceCents,
        )),
        now,
      );

    case sa.DeviceEventType.postponed:
      if (target == null) return all;
      final steps = (event.payload['steps'] as num?)?.toInt() ?? 1;
      return recomputeEtas(_postpone(all, target, steps), now);

    case sa.DeviceEventType.noShow:
      if (target == null) return all;
      return recomputeEtas(
          replace(target.copyWith(status: sa.BookingStatus.noShow)), now);

    case sa.DeviceEventType.closingDecision:
      if (target == null) return all;
      final cancel = event.payload['decision'] == sa.ClosingDecision.cancel.toWire();
      return recomputeEtas(
        replace(target.copyWith(
          status: cancel ? sa.BookingStatus.cancelled : null,
          closingDecided: true,
        )),
        now,
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

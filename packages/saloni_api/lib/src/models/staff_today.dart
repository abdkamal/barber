import 'booking.dart';
import 'enums.dart';
import 'json_utils.dart';
import 'service.dart';

/// استراحة (راحة/صلاة/طارئة) — design.md §2 (`breaks`).
class BreakPeriod {
  const BreakPeriod({
    required this.id,
    required this.kind,
    required this.start,
    required this.end,
  });

  final String id;
  final BreakKind kind;
  final DateTime start;
  final DateTime end;

  factory BreakPeriod.fromJson(Map<String, dynamic> json) => BreakPeriod(
        id: json['id'] as String,
        kind: BreakKind.fromWire(json['kind'] as String),
        start: parseUtc(json['start'] as String),
        end: parseUtc(json['end'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.toWire(),
        'start': toIso(start),
        'end': toIso(end),
      };
}

/// استجابة `GET /staff/today`: طابور الحلاق + الخدمات + الاستراحات +
/// الإعدادات + وقت السيرفر ورقم المزامنة الحالي (نقطة بداية `GET /sync?since=`).
class StaffToday {
  const StaffToday({
    required this.queue,
    required this.services,
    required this.breaks,
    required this.settings,
    required this.serverTime,
    required this.seq,
  });

  final List<Booking> queue;
  final List<Service> services;
  final List<BreakPeriod> breaks;

  /// إعدادات الصالون/الحلاق ذات الصلة (القسم 11) — تُترك عامة لتفادي ربط
  /// النموذج بكل مفتاح إعداد قد يضيفه السيرفر لاحقًا.
  final Map<String, dynamic> settings;

  final DateTime serverTime;

  /// رقم المزامنة الحالي — يُستخدم كنقطة بداية لـ `GET /sync?since=`.
  final int seq;

  factory StaffToday.fromJson(Map<String, dynamic> json) => StaffToday(
        queue: parseList(json['queue'], Booking.fromJson),
        services: parseList(json['services'], Service.fromJson),
        breaks: parseList(json['breaks'], BreakPeriod.fromJson),
        settings: Map<String, dynamic>.from(
          json['settings'] as Map? ?? const {},
        ),
        serverTime: parseUtc(json['serverTime'] as String),
        seq: json['seq'] as int,
      );

  Map<String, dynamic> toJson() => {
        'queue': queue.map((e) => e.toJson()).toList(),
        'services': services.map((e) => e.toJson()).toList(),
        'breaks': breaks.map((e) => e.toJson()).toList(),
        'settings': settings,
        'serverTime': toIso(serverTime),
        'seq': seq,
      };
}

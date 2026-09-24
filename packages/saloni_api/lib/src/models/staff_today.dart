import 'booking.dart';
import 'enums.dart';
import 'json_utils.dart';
import 'service.dart';

/// استراحة (راحة/صلاة/طارئة) — design.md §2 (`breaks`)، كما في
/// `GET /staff/today`: `{id, kind, start, end, open}`.
class BreakPeriod {
  const BreakPeriod({
    required this.id,
    required this.kind,
    required this.start,
    required this.end,
    this.open = false,
  });

  final String id;
  final BreakKind kind;
  final DateTime start;
  final DateTime end;

  /// استراحة بدأها الحلاق ولم ينهها بعد.
  final bool open;

  factory BreakPeriod.fromJson(Map<String, dynamic> json) => BreakPeriod(
        id: json['id'] as String,
        kind: BreakKind.fromWire(json['kind'] as String),
        start: parseUtc(json['start'] as String),
        end: parseUtc(json['end'] as String),
        open: json['open'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': kind.toWire(),
        'start': toIso(start),
        'end': toIso(end),
        'open': open,
      };
}

/// فترة زمنية مسماة: `{id, start, end}` — مثل فترات «حاضرون فقط» (ق33).
class TimeWindow {
  const TimeWindow({required this.id, required this.start, required this.end});

  final String id;
  final DateTime start;
  final DateTime end;

  bool contains(DateTime t) => !t.isBefore(start) && t.isBefore(end);

  factory TimeWindow.fromJson(Map<String, dynamic> json) => TimeWindow(
        id: json['id'] as String,
        start: parseUtc(json['start'] as String),
        end: parseUtc(json['end'] as String),
      );

  Map<String, dynamic> toJson() =>
      {'id': id, 'start': toIso(start), 'end': toIso(end)};
}

/// يوم عمل حلاق: `{workDate, workStart, workEnd, state, firstConnectedAt}`.
class StaffDay {
  const StaffDay({
    required this.workDate,
    required this.workStart,
    required this.workEnd,
    required this.state,
    this.firstConnectedAt,
  });

  final String workDate;
  final DateTime workStart;
  final DateTime workEnd;
  final BarberDayState state;
  final DateTime? firstConnectedAt;

  bool get absentToday => state == BarberDayState.absentToday;

  factory StaffDay.fromJson(Map<String, dynamic> json) => StaffDay(
        workDate: json['workDate'] as String,
        workStart: parseUtc(json['workStart'] as String),
        workEnd: parseUtc(json['workEnd'] as String),
        state: BarberDayState.fromWire(json['state'] as String),
        firstConnectedAt: parseUtcOrNull(json['firstConnectedAt'] as String?),
      );

  Map<String, dynamic> toJson() => {
        'workDate': workDate,
        'workStart': toIso(workStart),
        'workEnd': toIso(workEnd),
        'state': state.toWire(),
        'firstConnectedAt': toIsoOrNull(firstConnectedAt),
      };
}

/// استجابة `GET /staff/today` (api.md، «أشكال مثبّتة»):
/// `{day | null, queue[Booking], services[], breaks[], walkInOnly[],
/// closingWarnings[bookingId], settings{…}, serverTime, seq}`.
class StaffToday {
  const StaffToday({
    this.day,
    required this.queue,
    required this.services,
    required this.breaks,
    this.walkInOnly = const [],
    this.closingWarnings = const [],
    required this.settings,
    required this.serverTime,
    required this.seq,
  });

  /// يوم العمل الحالي، أو `null` إن لم يكن للحلاق دوام الآن.
  final StaffDay? day;

  final List<Booking> queue;
  final List<Service> services;
  final List<BreakPeriod> breaks;

  /// فترات «حاضرون فقط» اليوم (ق33).
  final List<TimeWindow> walkInOnly;

  /// حجوزات متوقعة بعد الإغلاق تنتظر قرار الحلاق (ق24).
  final List<String> closingWarnings;

  /// إعدادات الصالون/الحلاق ذات الصلة (القسم 11): `callAheadMinutes`,
  /// `etaChangeNotifyMinutes`, `overrunAlertPercent`, `offerHoldMinutes`,
  /// `maxDisconnectWindowMinutes`, `bookingOpensBeforeMinutes`,
  /// `heartbeatSeconds`, `offlineAfterSeconds`, `timezone`, `currency`.
  final Map<String, dynamic> settings;

  final DateTime serverTime;

  /// رقم المزامنة الحالي — يُستخدم كنقطة بداية لـ `GET /sync?since=`.
  final int seq;

  bool get hasShift => day != null;

  BreakPeriod? get openBreak {
    for (final b in breaks) {
      if (b.open) return b;
    }
    return null;
  }

  factory StaffToday.fromJson(Map<String, dynamic> json) => StaffToday(
        day: json['day'] is Map ? StaffDay.fromJson(asMap(json['day'])) : null,
        queue: parseList(json['queue'], Booking.fromJson),
        services: parseList(json['services'], Service.fromJson),
        breaks: parseList(json['breaks'], BreakPeriod.fromJson),
        walkInOnly: parseList(json['walkInOnly'], TimeWindow.fromJson),
        closingWarnings: parseStringList(json['closingWarnings']),
        settings: asMap(json['settings']),
        serverTime: parseUtc(json['serverTime'] as String),
        seq: asIntOrNull(json['seq']) ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'day': day?.toJson(),
        'queue': queue.map((e) => e.toJson()).toList(),
        'services': services.map((e) => e.toJson()).toList(),
        'breaks': breaks.map((e) => e.toJson()).toList(),
        'walkInOnly': walkInOnly.map((e) => e.toJson()).toList(),
        'closingWarnings': closingWarnings,
        'settings': settings,
        'serverTime': toIso(serverTime),
        'seq': seq,
      };
}

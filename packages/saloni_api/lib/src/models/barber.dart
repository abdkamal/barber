import 'enums.dart';
import 'json_utils.dart';

/// حلاق كما يظهر في `GET /customer/today`: حالته وأقرب بدء متاح عنده
/// (design.md §4) وهل يقبل حجوزات الآن ودوامه اليوم.
class Barber {
  const Barber({
    required this.id,
    required this.name,
    this.photoUrl,
    required this.dayState,
    this.nextAvailableStart,
    this.queueLength = 0,
    this.accepting = true,
    this.workStart,
    this.workEnd,
  });

  final String id;
  final String name;
  final String? photoUrl;
  final BarberDayState dayState;

  /// أقرب وقت بدء متاح لزبون جديد عند هذا الحلاق (UTC)، إن وُجد.
  final DateTime? nextAvailableStart;

  final int queueLength;

  /// هل يقبل حجوزات عبر التطبيق الآن (لا: خارج الدوام، غائب، أو انقطاع طويل — ق3).
  final bool accepting;

  /// دوامه اليوم، أو `null` إن لم يكن له دوام.
  final DateTime? workStart;
  final DateTime? workEnd;

  factory Barber.fromJson(Map<String, dynamic> json) => Barber(
        id: json['id'] as String,
        name: json['name'] as String,
        photoUrl: json['photoUrl'] as String?,
        dayState: BarberDayState.fromWire(json['dayState'] as String),
        nextAvailableStart: parseUtcOrNull(json['nextAvailableStart'] as String?),
        queueLength: asIntOrNull(json['queueLength']) ?? 0,
        accepting: json['accepting'] as bool? ?? true,
        workStart: parseUtcOrNull(json['workStart'] as String?),
        workEnd: parseUtcOrNull(json['workEnd'] as String?),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'photoUrl': photoUrl,
        'dayState': dayState.toWire(),
        'nextAvailableStart': toIsoOrNull(nextAvailableStart),
        'queueLength': queueLength,
        'accepting': accepting,
        'workStart': toIsoOrNull(workStart),
        'workEnd': toIsoOrNull(workEnd),
      };
}

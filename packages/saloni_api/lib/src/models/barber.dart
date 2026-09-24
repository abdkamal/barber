import 'enums.dart';
import 'json_utils.dart';

/// حلاق كما يظهر في `GET /customer/today` أو `GET /staff/today`: حالته
/// وأقرب بدء متاح عنده (design.md §4).
class Barber {
  const Barber({
    required this.id,
    required this.name,
    this.photoUrl,
    required this.dayState,
    this.nextAvailableStart,
    this.queueLength = 0,
  });

  final String id;
  final String name;
  final String? photoUrl;
  final BarberDayState dayState;

  /// أقرب وقت بدء متاح لزبون جديد عند هذا الحلاق (UTC)، إن وُجد.
  final DateTime? nextAvailableStart;

  final int queueLength;

  factory Barber.fromJson(Map<String, dynamic> json) => Barber(
        id: json['id'] as String,
        name: json['name'] as String,
        photoUrl: json['photoUrl'] as String?,
        dayState: BarberDayState.fromWire(json['dayState'] as String),
        nextAvailableStart: parseUtcOrNull(json['nextAvailableStart'] as String?),
        queueLength: json['queueLength'] as int? ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'photoUrl': photoUrl,
        'dayState': dayState.toWire(),
        'nextAvailableStart': toIsoOrNull(nextAvailableStart),
        'queueLength': queueLength,
      };
}

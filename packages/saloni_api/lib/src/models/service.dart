import 'json_utils.dart';

/// خدمة قابلة للحجز — design.md §2 (`services`).
///
/// الشكل في `GET /customer/today` و`GET /staff/today`:
/// `{id, name, baseDurationMin, priceCents, active}`. يقبل `fromJson` أيضًا شكل
/// `/manager/services` (`durationMinutes`, `price`, `position`) وشكل الملف
/// العام (`durationMin`, `price`).
class Service {
  const Service({
    required this.id,
    required this.name,
    required this.baseDurationMin,
    required this.priceCents,
    this.active = true,
    this.position,
  });

  final String id;
  final String name;
  final int baseDurationMin;
  final int priceCents;
  final bool active;
  final int? position;

  factory Service.fromJson(Map<String, dynamic> json) => Service(
        id: json['id'] as String,
        name: json['name'] as String,
        baseDurationMin: asIntOrNull(json['baseDurationMin'] ??
                json['durationMinutes'] ??
                json['durationMin']) ??
            0,
        priceCents: asIntOrNull(json['priceCents'] ?? json['price']) ?? 0,
        active: json['active'] as bool? ?? true,
        position: asIntOrNull(json['position']),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'baseDurationMin': baseDurationMin,
        'priceCents': priceCents,
        'active': active,
        if (position != null) 'position': position,
      };
}

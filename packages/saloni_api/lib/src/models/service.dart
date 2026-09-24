/// خدمة قابلة للحجز — design.md §2 (`services`).
class Service {
  const Service({
    required this.id,
    required this.name,
    required this.baseDurationMin,
    required this.priceCents,
    this.active = true,
  });

  final String id;
  final String name;
  final int baseDurationMin;
  final int priceCents;
  final bool active;

  factory Service.fromJson(Map<String, dynamic> json) => Service(
        id: json['id'] as String,
        name: json['name'] as String,
        baseDurationMin: json['baseDurationMin'] as int,
        priceCents: json['priceCents'] as int,
        active: json['active'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'baseDurationMin': baseDurationMin,
        'priceCents': priceCents,
        'active': active,
      };
}

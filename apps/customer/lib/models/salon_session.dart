import 'package:saloni_api/saloni_api.dart';

/// حساب زبون محفوظ لصالون واحد على هذا الجهاز — الزبون قد يضيف أكثر من صالون
/// بحساب مستقل لكل منها (design.md §1، ق7).
class SalonSession {
  const SalonSession({
    required this.code,
    required this.name,
    required this.session,
  });

  final String code;
  final String name;
  final Session session;

  SalonSession copyWith({String? name, Session? session}) => SalonSession(
        code: code,
        name: name ?? this.name,
        session: session ?? this.session,
      );

  factory SalonSession.fromJson(Map<String, dynamic> json) => SalonSession(
        code: json['code'] as String,
        name: json['name'] as String,
        session: Session.fromJson(json['session'] as Map<String, dynamic>),
      );

  Map<String, dynamic> toJson() => {
        'code': code,
        'name': name,
        'session': session.toJson(),
      };
}

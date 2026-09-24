import 'enums.dart';

/// الجلسة كما تعيدها نقاط الدخول — api.md "الدخول":
/// `{accessToken (15 د), refreshToken, role, salon}`.
class Session {
  const Session({
    required this.accessToken,
    required this.refreshToken,
    required this.role,
    required this.salonCode,
  });

  final String accessToken;
  final String refreshToken;
  final UserRole role;

  /// رمز الصالون المرتبط بالجلسة (لعرضه فقط؛ لا يُرسل مع الطلبات — §7).
  final String salonCode;

  factory Session.fromJson(Map<String, dynamic> json) => Session(
        accessToken: json['accessToken'] as String,
        refreshToken: json['refreshToken'] as String,
        role: UserRole.fromWire(json['role'] as String),
        salonCode: json['salon'] as String,
      );

  Map<String, dynamic> toJson() => {
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'role': role.toWire(),
        'salon': salonCode,
      };

  Session copyWith({String? accessToken, String? refreshToken}) => Session(
        accessToken: accessToken ?? this.accessToken,
        refreshToken: refreshToken ?? this.refreshToken,
        role: role,
        salonCode: salonCode,
      );
}

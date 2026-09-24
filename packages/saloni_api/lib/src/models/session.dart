import 'enums.dart';

/// بيانات الصالون كما تعيدها نقاط الدخول والتجديد و`GET /auth/session`:
/// `{code, name, status, timezone, currency}`.
class SalonInfo {
  const SalonInfo({
    required this.code,
    this.name,
    this.status,
    this.timezone,
    this.currency,
  });

  final String code;
  final String? name;

  /// `pending_activation` / `active` / `suspended`.
  final String? status;
  final String? timezone;

  /// رمز العملة (ق34)، مثل `SAR`.
  final String? currency;

  bool get pendingActivation => status == 'pending_activation';
  bool get isActive => status == 'active';

  factory SalonInfo.fromJson(Map<String, dynamic> json) => SalonInfo(
        code: json['code'] as String,
        name: json['name'] as String?,
        status: json['status'] as String?,
        timezone: json['timezone'] as String?,
        currency: json['currency'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'code': code,
        'name': name,
        'status': status,
        'timezone': timezone,
        'currency': currency,
      };
}

/// صاحب الجلسة: `{id, name, status?}` — `status` للزبون فقط
/// (`pending` / `active`).
class AccountInfo {
  const AccountInfo({required this.id, this.name, this.status});

  final String id;
  final String? name;
  final String? status;

  bool get pending => status == 'pending';

  factory AccountInfo.fromJson(Map<String, dynamic> json) => AccountInfo(
        id: json['id'] as String,
        name: json['name'] as String?,
        status: json['status'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (status != null) 'status': status,
      };
}

/// الجلسة كما تعيدها نقاط الدخول — api.md "الدخول":
/// `{accessToken, accessTokenExpiresIn, refreshToken, role, salon{…}, account{…}}`.
class Session {
  const Session({
    required this.accessToken,
    required this.refreshToken,
    required this.role,
    required this.salon,
    this.account,
    this.accessTokenExpiresIn,
  });

  final String accessToken;
  final String refreshToken;
  final UserRole role;

  /// الصالون المرتبط بالجلسة (للعرض فقط؛ لا يُرسل مع الطلبات — §7).
  final SalonInfo salon;
  final AccountInfo? account;

  /// عمر رمز الوصول بالثواني (إن أرسله السيرفر).
  final int? accessTokenExpiresIn;

  String get salonCode => salon.code;

  factory Session.fromJson(Map<String, dynamic> json) {
    final rawSalon = json['salon'];
    return Session(
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String,
      role: UserRole.fromWire(json['role'] as String),
      // جلسات محفوظة بإصدار سابق كانت تخزّن الرمز نصًا.
      salon: rawSalon is Map
          ? SalonInfo.fromJson(Map<String, dynamic>.from(rawSalon))
          : SalonInfo(code: rawSalon as String),
      account: json['account'] is Map
          ? AccountInfo.fromJson(Map<String, dynamic>.from(json['account'] as Map))
          : null,
      accessTokenExpiresIn: (json['accessTokenExpiresIn'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() => {
        'accessToken': accessToken,
        'refreshToken': refreshToken,
        'role': role.toWire(),
        'salon': salon.toJson(),
        if (account != null) 'account': account!.toJson(),
        if (accessTokenExpiresIn != null)
          'accessTokenExpiresIn': accessTokenExpiresIn,
      };

  Session copyWith({
    String? accessToken,
    String? refreshToken,
    SalonInfo? salon,
    AccountInfo? account,
  }) =>
      Session(
        accessToken: accessToken ?? this.accessToken,
        refreshToken: refreshToken ?? this.refreshToken,
        role: role,
        salon: salon ?? this.salon,
        account: account ?? this.account,
        accessTokenExpiresIn: accessTokenExpiresIn,
      );
}

/// `GET /auth/session` — حالة الجلسة الحالية (لتحديث حالة الصالون/الحساب بعد
/// «الدخول تلقائيًا»، مثل انتهاء «بانتظار التفعيل»).
class SessionInfo {
  const SessionInfo({
    required this.role,
    required this.accountId,
    this.accountStatus,
    required this.salon,
  });

  final UserRole role;
  final String accountId;
  final String? accountStatus;
  final SalonInfo salon;

  factory SessionInfo.fromJson(Map<String, dynamic> json) => SessionInfo(
        role: UserRole.fromWire(json['role'] as String),
        accountId: json['accountId'] as String,
        accountStatus: json['accountStatus'] as String?,
        salon: SalonInfo.fromJson(Map<String, dynamic>.from(json['salon'] as Map)),
      );
}

/// نتيجة `POST /salons/register` (ق37): `{salon, session}` — المالك يدخل
/// كمدير مباشرة وصالونه `pending_activation`.
class SalonRegistration {
  const SalonRegistration({required this.salon, required this.session});

  final SalonInfo salon;
  final Session session;

  factory SalonRegistration.fromJson(Map<String, dynamic> json) =>
      SalonRegistration(
        salon: SalonInfo.fromJson(Map<String, dynamic>.from(json['salon'] as Map)),
        session:
            Session.fromJson(Map<String, dynamic>.from(json['session'] as Map)),
      );
}

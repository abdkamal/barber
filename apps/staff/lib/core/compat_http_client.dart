import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// غلاف `http.Client` بين `ApiClient` والشبكة، لسببين (انظر README → «تغييرات
/// مطلوبة في الحزم»):
///
/// 1. **توافق شكل الجلسة:** السيرفر يعيد `salon` ككائن
///    `{code, name, status, timezone, currency}` بينما `Session.fromJson` في
///    `saloni_api` يتوقع نصًا. نحوّله هنا إلى الرمز ونحتفظ بالكائن الكامل
///    (مع `account`) ليقرأه التطبيق — دون تعديل الحزمة.
/// 2. **حقول إضافية:** نماذج `saloni_api` (مثل `Booking`) لا تحمل اسم الزبون
///    ولا الوقت المتوقع الحالي. نحتفظ بآخر JSON خام لبعض المسارات ليستخرج
///    التطبيق هذه الحقول.
class CompatHttpClient extends http.BaseClient {
  CompatHttpClient(this._inner);

  final http.Client _inner;
  final Map<String, Object?> _raw = {};

  /// يُستدعى عند كل استجابة جلسة ناجحة (دخول، تجديد، تسجيل صالون).
  void Function(Map<String, dynamic>? salon, Map<String, dynamic>? account)?
      onSessionMeta;

  static const _sessionPaths = {
    '/auth/staff/login',
    '/auth/refresh',
    '/salons/register',
  };

  static const _tapPaths = {
    '/staff/today',
    '/staff/payments',
    '/staff/impact',
    '/staff/walk-ins',
  };

  /// آخر JSON خام لمسار (مثل `/staff/today`).
  Object? lastRaw(String path) => _raw[path];

  String? _key(Uri url) {
    var p = url.path;
    final i = p.indexOf('/v1/');
    if (i >= 0) p = p.substring(i + 3);
    if (_sessionPaths.contains(p) || _tapPaths.contains(p)) return p;
    return null;
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final res = await _inner.send(request);
    final key = _key(request.url);
    if (key == null || res.statusCode < 200 || res.statusCode >= 300) {
      return res;
    }
    final bytes = await res.stream.toBytes();
    List<int> out = bytes;
    try {
      final json = bytes.isEmpty ? null : jsonDecode(utf8.decode(bytes));
      if (_sessionPaths.contains(key) && json is Map<String, dynamic>) {
        final changed = normalizeSessionJson(json, onSessionMeta);
        if (changed) out = utf8.encode(jsonEncode(json));
      } else {
        _raw[key] = json;
      }
    } catch (_) {
      // استجابة غير JSON — تُمرَّر كما هي.
    }
    final headers = Map<String, String>.from(res.headers)
      ..remove('content-length');
    return http.StreamedResponse(
      Stream.value(out),
      res.statusCode,
      contentLength: out.length,
      request: res.request,
      headers: headers,
      reasonPhrase: res.reasonPhrase,
      isRedirect: res.isRedirect,
      persistentConnection: res.persistentConnection,
    );
  }

  @override
  void close() => _inner.close();
}

/// يحوّل `salon` (كائن) إلى رمز نصي في جسم جلسة، أو في `session` داخل رد
/// تسجيل الصالون. يعيد `true` إن تغيّر الجسم.
bool normalizeSessionJson(
  Map<String, dynamic> json,
  void Function(Map<String, dynamic>?, Map<String, dynamic>?)? onMeta,
) {
  var changed = false;
  Map<String, dynamic> target = json;
  if (json['session'] is Map<String, dynamic>) {
    target = json['session'] as Map<String, dynamic>;
  }
  final salon = target['salon'];
  Map<String, dynamic>? salonMeta;
  if (salon is Map) {
    salonMeta = Map<String, dynamic>.from(salon);
    target['salon'] = salonMeta['code'];
    changed = true;
  } else if (json['salon'] is Map) {
    salonMeta = Map<String, dynamic>.from(json['salon'] as Map);
  }
  final account = target['account'] is Map
      ? Map<String, dynamic>.from(target['account'] as Map)
      : null;
  onMeta?.call(salonMeta, account);
  return changed;
}

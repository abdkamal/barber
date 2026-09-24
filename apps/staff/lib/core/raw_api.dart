import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:saloni_api/saloni_api.dart' as sa;

/// طلبات لا يغطيها `ApiClient` في `saloni_api` حاليًا أو يرسلها بشكل مختلف
/// عن السيرفر (انظر README → «تغييرات مطلوبة في الحزم»):
/// - رفع الصور `multipart/form-data` (الحزمة ترسل JSON).
/// - `PUT /manager/schedules` (الحزمة ترسل POST) وحذف الدوام/الاستراحات/الإجازات.
/// - `GET /manager/phone-disputes`.
///
/// تستخدم رمز الوصول من مخزن الجلسة نفسه؛ عند 401 تستدعي طلبًا خفيفًا عبر
/// `ApiClient` ليجدد الجلسة (تجديد واحد متزامن داخل الحزمة) ثم تعيد المحاولة.
class RawApi {
  RawApi({required this.api, required this.http_, required String baseUrl})
      : base = Uri.parse(baseUrl.endsWith('/') ? '${baseUrl}v1' : '$baseUrl/v1');

  final sa.ApiClient api;
  final http.Client http_;
  final Uri base;

  Uri _uri(String path, [Map<String, String>? query]) =>
      base.replace(path: '${base.path}$path', queryParameters: query);

  Future<String?> _token() async => (await api.tokenStore.read())?.accessToken;

  Future<dynamic> send(
    String method,
    String path, {
    Object? json,
    Map<String, String>? query,
    List<int>? fileBytes,
    String? fileName,
    String? fileContentType,
  }) async {
    Future<http.Response> attempt() async {
      final token = await _token();
      if (token == null) throw sa.ApiError.signedOut();
      final headers = {
        'Accept': 'application/json',
        'Authorization': 'Bearer $token',
      };
      if (fileBytes != null) {
        final req = http.MultipartRequest(method, _uri(path, query))
          ..headers.addAll(headers)
          ..files.add(http.MultipartFile.fromBytes(
            'file',
            fileBytes,
            filename: fileName ?? 'image.jpg',
            contentType: _mediaType(fileContentType),
          ));
        return http.Response.fromStream(await http_.send(req));
      }
      final req = http.Request(method, _uri(path, query))..headers.addAll(headers);
      if (json != null) {
        req.headers['Content-Type'] = 'application/json; charset=utf-8';
        req.body = jsonEncode(json);
      }
      return http.Response.fromStream(await http_.send(req));
    }

    http.Response res;
    try {
      res = await attempt().timeout(const Duration(seconds: 30));
      if (res.statusCode == 401) {
        // يجدد الجلسة عبر الحزمة (أو يرمي SIGNED_OUT).
        await api.getManagerSettings();
        res = await attempt().timeout(const Duration(seconds: 30));
      }
    } on sa.ApiError {
      rethrow;
    } catch (e) {
      throw sa.ApiError.network(e.toString());
    }
    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (res.bodyBytes.isEmpty) return null;
      return jsonDecode(utf8.decode(res.bodyBytes));
    }
    try {
      final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
      throw sa.ApiError.fromJson(body, statusCode: res.statusCode);
    } on sa.ApiError {
      rethrow;
    } catch (_) {
      throw sa.ApiError(code: 'HTTP_${res.statusCode}', message: 'حدث خطأ غير متوقع', statusCode: res.statusCode);
    }
  }

  // ---------------- اختصارات ----------------

  Future<dynamic> uploadPhoto(List<int> bytes, String name, String type) =>
      send('POST', '/manager/photos', fileBytes: bytes, fileName: name, fileContentType: type);

  Future<dynamic> uploadLogo(List<int> bytes, String name, String type) =>
      send('POST', '/manager/profile/logo', fileBytes: bytes, fileName: name, fileContentType: type);

  Future<dynamic> uploadCatalogPhoto(String id, List<int> bytes, String name, String type) =>
      send('POST', '/manager/catalog/$id/photo', fileBytes: bytes, fileName: name, fileContentType: type);

  /// `staffId: null` = دوام الصالون الافتراضي لذلك اليوم (يظهر للزبائن).
  Future<dynamic> putSchedule({String? staffId, required int weekday, required String opensAt, required String closesAt}) =>
      send('PUT', '/manager/schedules', json: {
        'staffId': staffId,
        'weekday': weekday,
        'opensAt': opensAt,
        'closesAt': closesAt,
      });

  Future<dynamic> deleteSchedule(int weekday, {String? staffId}) => send(
        'DELETE',
        '/manager/schedules/$weekday',
        query: staffId == null ? null : {'staffId': staffId},
      );

  Future<dynamic> deleteBreak(String id) => send('DELETE', '/manager/breaks/$id');

  Future<dynamic> deleteAbsence(String id) => send('DELETE', '/manager/absences/$id');

  Future<dynamic> phoneDisputes() => send('GET', '/manager/phone-disputes');
}

/// الأيام: دارت (الاثنين=1 … الأحد=7) ← السيرفر (الأحد=0 … السبت=6).
int serverWeekday(int dartWeekday) => dartWeekday % 7;

MediaType? _mediaType(String? t) {
  if (t == null) return null;
  final parts = t.split('/');
  return MediaType(parts[0], parts.length > 1 ? parts[1] : 'octet-stream');
}

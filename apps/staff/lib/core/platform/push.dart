import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:saloni_api/saloni_api.dart';

import '../config.dart';

/// رسالة FCM مبسطة (api.md: `{type, bookingId, title, body}`).
class PushMessage {
  const PushMessage({required this.type, this.bookingId, this.title, this.body});
  final String type;
  final String? bookingId;
  final String? title;
  final String? body;
}

/// إشعارات Firebase — خلف العلم `FCM_ENABLED` (يتطلب google-services.json).
/// بدونه يعمل التطبيق كاملًا، وتبقى المزامنة الدورية والتنبيهات داخل التطبيق.
abstract class PushService {
  Stream<PushMessage> get messages;

  /// يهيّئ Firebase ويسجّل رمز الجهاز عند السيرفر. يعيد `false` إن تعذّر.
  Future<bool> register(ApiClient api, {required bool notificationsAllowed});
}

class NoopPushService implements PushService {
  @override
  Stream<PushMessage> get messages => const Stream.empty();
  @override
  Future<bool> register(ApiClient api, {required bool notificationsAllowed}) async =>
      false;
}

PushService defaultPushService() =>
    AppConfig.fcmEnabled && !kIsWeb ? FirebasePushService() : NoopPushService();

class FirebasePushService implements PushService {
  final _controller = StreamController<PushMessage>.broadcast();
  bool _listening = false;

  @override
  Stream<PushMessage> get messages => _controller.stream;

  @override
  Future<bool> register(ApiClient api, {required bool notificationsAllowed}) async {
    try {
      if (Firebase.apps.isEmpty) await Firebase.initializeApp();
      final fm = FirebaseMessaging.instance;
      final token = await fm.getToken();
      if (token == null) throw StateError('no token');
      await api.registerDevice(
        fcmToken: token,
        notificationsAllowed: notificationsAllowed,
        hasPlayServices: true,
      );
      if (!_listening) {
        _listening = true;
        FirebaseMessaging.onMessage.listen((m) {
          _controller.add(PushMessage(
            type: m.data['type']?.toString() ?? '',
            bookingId: m.data['bookingId']?.toString(),
            title: m.notification?.title ?? m.data['title']?.toString(),
            body: m.notification?.body ?? m.data['body']?.toString(),
          ));
        });
        fm.onTokenRefresh.listen((t) {
          api
              .registerDevice(
                fcmToken: t,
                notificationsAllowed: notificationsAllowed,
                hasPlayServices: true,
              )
              .catchError((_) {});
        });
      }
      return true;
    } catch (_) {
      // لا خدمات Google أو لا إعداد Firebase — نبلغ السيرفر إن أمكن (§8).
      try {
        await api.registerDevice(
          fcmToken: '',
          notificationsAllowed: notificationsAllowed,
          hasPlayServices: false,
        );
      } catch (_) {}
      return false;
    }
  }
}

import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:google_api_availability/google_api_availability.dart';
import 'package:permission_handler/permission_handler.dart';

import 'customer_api.dart';

/// نتيجة فحص التنبيهات عند أول تشغيل (design.md §8، ق31): إذن الإشعارات
/// وتوفر خدمات Google Play. يُعرض تحذير عربي واضح إن تعذر أي منهما.
class NotificationReadiness {
  const NotificationReadiness({
    required this.notificationsAllowed,
    required this.hasPlayServices,
    required this.fcmToken,
  });

  final bool notificationsAllowed;
  final bool hasPlayServices;
  final String? fcmToken;

  bool get isFullyReady => notificationsAllowed && hasPlayServices && fcmToken != null;
}

/// يغلّف Firebase Messaging — **يعمل التطبيق بلا `google-services.json`**:
/// كل استدعاء محاط بمعالجة أخطاء، وعند تعذّر التهيئة تُعاد نتيجة "غير جاهز"
/// بدل رمي استثناء يوقف التطبيق. راجع README لإعداد ملف Firebase الحقيقي.
class NotificationService {
  NotificationService(this._api);

  final CustomerApi _api;
  bool _firebaseReady = false;

  Future<void> _ensureFirebase() async {
    if (_firebaseReady) return;
    try {
      await Firebase.initializeApp();
      _firebaseReady = true;
    } catch (_) {
      // لا ملف google-services.json أو تهيئة غير متاحة — التطبيق يستمر بلا
      // إشعارات، مع تحذير للمستخدم (ق31).
      _firebaseReady = false;
    }
  }

  Future<bool> _hasPlayServices() async {
    try {
      final result = await GoogleApiAvailability.instance.checkGooglePlayServicesAvailability();
      return result == GooglePlayServicesAvailability.success;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _requestNotificationPermission() async {
    try {
      final status = await Permission.notification.request();
      return status.isGranted;
    } catch (_) {
      return false;
    }
  }

  /// يُنفَّذ عند أول تشغيل (وعند كل بدء تشغيل): يفحص الإذن وتوفر خدمات Google،
  /// ويسجّل الجهاز في السيرفر إن أمكن.
  Future<NotificationReadiness> initializeAndRegister() async {
    final hasPlay = await _hasPlayServices();
    final allowed = await _requestNotificationPermission();

    String? token;
    if (hasPlay) {
      await _ensureFirebase();
      if (_firebaseReady) {
        try {
          token = await FirebaseMessaging.instance.getToken();
        } catch (_) {
          token = null;
        }
      }
    }

    try {
      await _api.registerDevice(
        fcmToken: token ?? '',
        notificationsAllowed: allowed,
        hasPlayServices: hasPlay,
      );
    } catch (_) {
      // فشل تسجيل الجهاز لا يوقف التطبيق؛ يمكن إعادة المحاولة لاحقًا.
    }

    return NotificationReadiness(
      notificationsAllowed: allowed,
      hasPlayServices: hasPlay,
      fcmToken: token,
    );
  }

  /// يصدر حدثًا عند وصول رسالة FCM أثناء فتح التطبيق — تُستخدم لتحديث شاشة
  /// المتابعة فورًا (بدل انتظار الاستطلاع الدوري كل 30 ث).
  Stream<void> get onMessage {
    if (!_firebaseReady) return const Stream.empty();
    return FirebaseMessaging.onMessage.map((_) {});
  }
}

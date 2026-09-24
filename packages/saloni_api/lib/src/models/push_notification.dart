/// أنواع التنبيهات (FCM) — api.md «التنبيهات»، بأسماء الأسلاك.
enum NotificationKind {
  bookingConfirmed('booking_confirmed'),
  called('called'),
  etaChanged('eta_changed'),
  postponed('postponed'),
  noShow('no_show'),
  cancelledClosing('cancelled_closing'),

  /// نقل المدير الحجز إلى حلاق آخر (ق25) — `data`: `eta`, `barberId`.
  transferred('transferred'),

  /// للحلاق: تجاوزت الخدمة مدتها (ق27).
  overrun('overrun'),
  accountPending('account_pending'),

  /// للمدير.
  barberNotConnected('barber_not_connected'),
  barberAbsent('barber_absent'),
  syncConflict('sync_conflict'),

  /// للمدير: المدة الأساسية لخدمة تبدو غير واقعية مقارنة بالمدد الفعلية.
  baseDurationSuspect('base_duration_suspect'),

  /// نوع لا يعرفه هذا الإصدار من التطبيق.
  unknown('');

  const NotificationKind(this.wire);

  final String wire;

  static NotificationKind fromWire(String? value) => NotificationKind.values
      .firstWhere((k) => k.wire == value && k != unknown, orElse: () => unknown);

  /// تنبيهات تغيّر حالة الحجز أو الطابور — تستدعي تحديث العرض فورًا.
  bool get affectsQueue => switch (this) {
        bookingConfirmed ||
        called ||
        etaChanged ||
        postponed ||
        noShow ||
        cancelledClosing ||
        transferred ||
        barberAbsent =>
          true,
        _ => false,
      };

  /// تنبيهات موجهة للمدير.
  bool get forManager => switch (this) {
        barberNotConnected || barberAbsent || syncConflict || baseDurationSuspect => true,
        _ => false,
      };
}

/// حمولة `data` لتنبيه FCM: `{type, bookingId?, title, body, …}` — كل القيم نصية.
class PushNotification {
  const PushNotification({
    required this.kind,
    required this.type,
    this.bookingId,
    this.title,
    this.body,
    this.data = const {},
  });

  final NotificationKind kind;

  /// النوع كما ورد (مفيد لنوع غير معروف).
  final String type;
  final String? bookingId;
  final String? title;
  final String? body;
  final Map<String, String> data;

  factory PushNotification.fromData(
    Map<String, dynamic> data, {
    String? title,
    String? body,
  }) {
    final strings = {
      for (final e in data.entries)
        if (e.value != null) e.key: e.value.toString(),
    };
    final type = strings['type'] ?? '';
    return PushNotification(
      kind: NotificationKind.fromWire(type),
      type: type,
      bookingId: strings['bookingId'],
      title: title ?? strings['title'],
      body: body ?? strings['body'],
      data: strings,
    );
  }
}

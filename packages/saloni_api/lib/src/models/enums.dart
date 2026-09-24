/// تعدادات مشتركة، بأسماء الأسلاك (wire names) كما في `docs/api.md` و`design.md`.
library;

/// حالة الحجز — design.md §3.
enum BookingStatus {
  offered,
  waiting,
  called,
  inService,
  done,
  cancelled,
  noShow,

  /// عرض انتهت مدته أو رُفض (ق13) — لا يظهر في القوائم عادةً.
  expired;

  static BookingStatus fromWire(String value) => switch (value) {
        'offered' => BookingStatus.offered,
        'waiting' => BookingStatus.waiting,
        'called' => BookingStatus.called,
        'in_service' => BookingStatus.inService,
        'done' => BookingStatus.done,
        'cancelled' => BookingStatus.cancelled,
        'no_show' => BookingStatus.noShow,
        'expired' => BookingStatus.expired,
        _ => throw FormatException('Unknown BookingStatus: $value'),
      };

  String toWire() => switch (this) {
        BookingStatus.offered => 'offered',
        BookingStatus.waiting => 'waiting',
        BookingStatus.called => 'called',
        BookingStatus.inService => 'in_service',
        BookingStatus.done => 'done',
        BookingStatus.cancelled => 'cancelled',
        BookingStatus.noShow => 'no_show',
        BookingStatus.expired => 'expired',
      };
}

/// نوع الحجز: دور بالطابور أو ساعة محددة — api.md `POST /bookings/quote`.
enum BookingKind {
  queue,
  requested;

  static BookingKind fromWire(String value) => switch (value) {
        'queue' => BookingKind.queue,
        'requested' => BookingKind.requested,
        _ => throw FormatException('Unknown BookingKind: $value'),
      };

  String toWire() => switch (this) {
        BookingKind.queue => 'queue',
        BookingKind.requested => 'requested',
      };
}

/// مصدر الحجز: عبر التطبيق أو أدخله الحلاق (زبون حاضر).
enum BookingSource {
  app,
  barber;

  static BookingSource fromWire(String value) => switch (value) {
        'app' => BookingSource.app,
        'barber' => BookingSource.barber,
        _ => throw FormatException('Unknown BookingSource: $value'),
      };

  String toWire() => switch (this) {
        BookingSource.app => 'app',
        BookingSource.barber => 'barber',
      };
}

/// نتيجة طلب عرض السعر/الوقت — api.md `POST /bookings/quote`.
enum QuoteOutcome {
  accept,
  offer;

  static QuoteOutcome fromWire(String value) => switch (value) {
        'accept' => QuoteOutcome.accept,
        'offer' => QuoteOutcome.offer,
        _ => throw FormatException('Unknown QuoteOutcome: $value'),
      };

  String toWire() => switch (this) {
        QuoteOutcome.accept => 'accept',
        QuoteOutcome.offer => 'offer',
      };
}

/// حالة يوم الحلاق — design.md §4.
enum BarberDayState {
  notConnectedYet,
  connected,
  disconnected,
  absentToday;

  static BarberDayState fromWire(String value) => switch (value) {
        'not_connected_yet' => BarberDayState.notConnectedYet,
        'connected' => BarberDayState.connected,
        'disconnected' => BarberDayState.disconnected,
        'absent_today' => BarberDayState.absentToday,
        _ => throw FormatException('Unknown BarberDayState: $value'),
      };

  String toWire() => switch (this) {
        BarberDayState.notConnectedYet => 'not_connected_yet',
        BarberDayState.connected => 'connected',
        BarberDayState.disconnected => 'disconnected',
        BarberDayState.absentToday => 'absent_today',
      };
}

/// حالة الدفع — design.md §2 (`payments`)، مستقلة عن حالة الخدمة.
enum PaymentStatus {
  awaitingConfirmation,
  confirmed;

  static PaymentStatus fromWire(String value) => switch (value) {
        'awaiting_confirmation' => PaymentStatus.awaitingConfirmation,
        'confirmed' => PaymentStatus.confirmed,
        _ => throw FormatException('Unknown PaymentStatus: $value'),
      };

  String toWire() => switch (this) {
        PaymentStatus.awaitingConfirmation => 'awaiting_confirmation',
        PaymentStatus.confirmed => 'confirmed',
      };
}

/// دور الحساب — api.md "الجلسة".
enum UserRole {
  customer,
  barber,
  manager;

  static UserRole fromWire(String value) => switch (value) {
        'customer' => UserRole.customer,
        'barber' => UserRole.barber,
        'manager' => UserRole.manager,
        _ => throw FormatException('Unknown UserRole: $value'),
      };

  String toWire() => switch (this) {
        UserRole.customer => 'customer',
        UserRole.barber => 'barber',
        UserRole.manager => 'manager',
      };
}

/// نوع حدث الجهاز — api.md "أحداث الجهاز".
enum DeviceEventType {
  serviceStarted,
  serviceFinished,
  servicesChanged,
  paymentConfirmed,
  postponed,
  waited,
  noShow,
  closingDecision,
  breakStarted,
  breakEnded,
  absentToday;

  static DeviceEventType fromWire(String value) => switch (value) {
        'service_started' => DeviceEventType.serviceStarted,
        'service_finished' => DeviceEventType.serviceFinished,
        'services_changed' => DeviceEventType.servicesChanged,
        'payment_confirmed' => DeviceEventType.paymentConfirmed,
        'postponed' => DeviceEventType.postponed,
        'waited' => DeviceEventType.waited,
        'no_show' => DeviceEventType.noShow,
        'closing_decision' => DeviceEventType.closingDecision,
        'break_started' => DeviceEventType.breakStarted,
        'break_ended' => DeviceEventType.breakEnded,
        'absent_today' => DeviceEventType.absentToday,
        _ => throw FormatException('Unknown DeviceEventType: $value'),
      };

  String toWire() => switch (this) {
        DeviceEventType.serviceStarted => 'service_started',
        DeviceEventType.serviceFinished => 'service_finished',
        DeviceEventType.servicesChanged => 'services_changed',
        DeviceEventType.paymentConfirmed => 'payment_confirmed',
        DeviceEventType.postponed => 'postponed',
        DeviceEventType.waited => 'waited',
        DeviceEventType.noShow => 'no_show',
        DeviceEventType.closingDecision => 'closing_decision',
        DeviceEventType.breakStarted => 'break_started',
        DeviceEventType.breakEnded => 'break_ended',
        DeviceEventType.absentToday => 'absent_today',
      };
}

/// نوع الاستراحة كما في حمولة `break_started`/`break_ended` وفي
/// `/manager/breaks` (`type`). `walkInOnly` («حاضرون فقط»، ق33) فترة يديرها
/// المدير فقط: لا تُبدأ من جهاز الحلاق، و`GET /staff/today` يرسلها منفصلة في
/// `walkInOnly`.
enum BreakKind {
  rest,
  prayer,
  emergency,
  walkInOnly;

  static BreakKind fromWire(String value) => switch (value) {
        'rest' => BreakKind.rest,
        'prayer' => BreakKind.prayer,
        'emergency' => BreakKind.emergency,
        'walk_in_only' => BreakKind.walkInOnly,
        _ => throw FormatException('Unknown BreakKind: $value'),
      };

  String toWire() => switch (this) {
        BreakKind.rest => 'rest',
        BreakKind.prayer => 'prayer',
        BreakKind.emergency => 'emergency',
        BreakKind.walkInOnly => 'walk_in_only',
      };

  /// هل يمكن للحلاق بدؤها من جهازه (حدث `break_started`)؟
  bool get deviceStartable => this != BreakKind.walkInOnly;
}

/// قرار الحلاق عند تجاوز الإغلاق — حمولة `closing_decision` (ق24).
enum ClosingDecision {
  serveLate,
  cancel;

  static ClosingDecision fromWire(String value) => switch (value) {
        'serve_late' => ClosingDecision.serveLate,
        'cancel' => ClosingDecision.cancel,
        _ => throw FormatException('Unknown ClosingDecision: $value'),
      };

  String toWire() => switch (this) {
        ClosingDecision.serveLate => 'serve_late',
        ClosingDecision.cancel => 'cancel',
      };
}

/// نتيجة تطبيق حدث مُرسل عبر `POST /sync/events` — design.md §6.2.
enum SyncEventResult {
  applied,
  duplicate,
  rejected;

  static SyncEventResult fromWire(String value) => switch (value) {
        'applied' => SyncEventResult.applied,
        'duplicate' => SyncEventResult.duplicate,
        'rejected' => SyncEventResult.rejected,
        _ => throw FormatException('Unknown SyncEventResult: $value'),
      };
}

/// نوع عنصر الكتالوج — design.md §2 (`catalog_items`).
enum CatalogItemType {
  service,
  product;

  static CatalogItemType fromWire(String value) => switch (value) {
        'service' => CatalogItemType.service,
        'product' => CatalogItemType.product,
        _ => throw FormatException('Unknown CatalogItemType: $value'),
      };

  String toWire() => switch (this) {
        CatalogItemType.service => 'service',
        CatalogItemType.product => 'product',
      };
}

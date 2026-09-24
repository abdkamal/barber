import 'package:flutter/foundation.dart';
import 'package:saloni_api/saloni_api.dart' as sa;

/// نصوص الأخطاء المعروضة للطاقم (ملاحظات التجربة الأولى — المرحلة 11).
///
/// القاعدة: كل رمز خطأ معروف من السيرفر (`server/src`، `docs/api.md`) له نص
/// عربي واضح هنا؛ أخطاء التحقق تذكر الحقل والمشكلة؛ أخطاء الشبكة تميّز «لا
/// إنترنت» عن «السيرفر لا يُصل» عن «انتهت المهلة»؛ وغير المتوقع يُعرض برمز
/// يبلّغ به المستخدم: `S-xxxxxx` (آخر 6 محارف من معرّف طلب السيرفر — يطابق
/// سطر سجله) أو `C-<النوع>` لخطأ داخل التطبيق نفسه. والخطأ الأصلي يُطبع دائمًا
/// في سجل التطبيق (`debugPrint`) مع مكدّسه.
abstract final class ErrorTexts {
  static const unexpected = 'حدث خطأ غير متوقع';

  /// رموز أخطاء السيرفر (HTTP) ← نص عربي. ما ليس هنا تُعرض رسالة السيرفر
  /// العربية نفسها (مثل `WEAK_PASSWORD` بحدّها الأدنى).
  static const codes = <String, String>{
    // الدخول والجلسة
    'UNAUTHENTICATED': 'انتهت الجلسة — سجّل الدخول من جديد',
    'SIGNED_OUT': 'انتهت الجلسة — سجّل الدخول من جديد',
    'INVALID_CREDENTIALS': 'بيانات الدخول غير صحيحة — تحقق من رمز الصالون واسم المستخدم وكلمة المرور',
    'INVALID_REFRESH_TOKEN': 'انتهت الجلسة — سجّل الدخول من جديد',
    'REFRESH_TOKEN_REUSED': 'أُلغيت الجلسة لأسباب أمنية — سجّل الدخول من جديد',
    'FORBIDDEN': 'ليست لديك صلاحية لهذا الإجراء',
    'ACCOUNT_SUSPENDED': 'هذا الحساب موقوف — راجع مدير الصالون',
    'SALON_SUSPENDED': 'هذا الصالون موقوف حاليًا',
    'SALON_NOT_FOUND': 'لم نجد صالونًا بهذا الرمز — تحقق من رمز الصالون',
    'SALON_NOT_ACTIVE': 'الصالون بانتظار التفعيل — رفع الصور متاح بعد التفعيل',
    'INVALID_RESET_CODE': 'رمز إعادة التعيين غير صحيح أو منتهي — اطلب رمزًا جديدًا من المدير',
    'LOGIN_BACKOFF': 'محاولات دخول فاشلة متكررة — انتظر قليلًا ثم حاول',
    'RATE_LIMITED': 'محاولات كثيرة — انتظر قليلًا ثم حاول',
    'NOT_STAFF': 'هذا التطبيق للطاقم فقط. استخدم تطبيق «صالوني» للزبائن.',
    // التسجيل
    'REGISTRATION_FAILED': 'تعذّر إنشاء الحساب بهذه البيانات',
    'REGISTRATION_PAUSED': 'تسجيل الصالونات الجديدة متوقف مؤقتًا — حاول لاحقًا',
    'SALON_CODE_EXHAUSTED': 'تعذّر توليد رمز للصالون — جرّب اسمًا مختلفًا للصالون',
    'USERNAME_TAKEN': 'اسم المستخدم مستخدم مسبقًا — اختر اسمًا آخر',
    // الطاقم والزبائن
    'OWNER_PROTECTED': 'لا يمكن تخفيض صلاحية مالك الصالون أو إيقافه',
    'LAST_MANAGER': 'يجب أن يبقى للصالون مدير نشط واحد على الأقل',
    'CANNOT_CHANGE_OWN_ACCESS': 'لا يمكنك تغيير صلاحيتك أو إيقاف حسابك بنفسك',
    'ACCOUNT_NOT_SUSPENDED': 'الحساب غير موقوف — يرفع صاحبه إجراءاته بنفسه عند دخوله',
    'ACCOUNT_PENDING': 'حساب الزبون بانتظار اعتماد الصالون',
    'PHONE_IN_USE': 'الرقم مستخدم لحساب آخر',
    'PHONE_RELEASED': 'أُفرج عن رقم هذا الحساب — أسند له رقمًا آخر أولًا',
    'PHONE_MISMATCH': 'رقم سجل الحاضر لا يطابق رقم الحساب',
    'WALK_IN_ALREADY_LINKED': 'سجل الحاضر هذا مربوط بحساب آخر',
    // الخدمات والكتالوج والصور
    'SERVICE_IN_USE': 'الخدمة مستخدمة في حجوزات — أوقفها بدل حذفها',
    'SERVICE_UNAVAILABLE': 'إحدى الخدمات المختارة غير متاحة',
    'PHOTOS_LIMIT_REACHED': 'بلغت الحد الأقصى للصور (6) — احذف صورة أولًا',
    'PAYLOAD_TOO_LARGE': 'الملف كبير جدًا — اختر صورة أصغر',
    'UNSUPPORTED_MEDIA_TYPE': 'نوع الملف غير مدعوم — JPEG أو PNG أو WebP فقط',
    // الدوام والاستراحات
    'BREAK_OVERLAP': 'تتداخل هذه الفترة مع استراحة أو فترة أخرى لنفس الحلاق',
    'NOT_WORKING_NOW': 'لا دوام الآن — الإضافة خلال الدوام الجاري فقط',
    'NOT_WORKING': 'لا دوام الآن',
    // الحجز والنقل (ق25)
    'BARBER_NOT_FOUND': 'الحلاق غير موجود أو موقوف',
    'BARBER_NOT_WORKING': 'لا دوام لهذا الحلاق اليوم — اضبط دوامه من «الدوام» أولًا',
    'BARBER_ABSENT': 'الحلاق مسجّل «لن يعمل اليوم»',
    'BARBER_UNAVAILABLE': 'الحلاق لا يستقبل حجوزات الآن',
    'BOOKING_NOT_FOUND': 'الحجز غير موجود — ربما أُلغي أو انتهى',
    'BOOKING_NOT_ACTIVE': 'الحجز لم يعد قائمًا',
    'BOOKING_STARTED': 'بدأت خدمة هذا الزبون — لا يمكن نقله',
    'BOOKING_CALLED': 'استُدعي الزبون بالفعل',
    'BOOKING_CLOSED': 'الحجز مغلق لهذا اليوم',
    'BOOKING_NOT_UNFINISHED': 'هذه الخدمة ليست معلّقة من يوم سابق',
    'INVALID_END_TIME': 'وقت الانتهاء غير صالح — لا قبل بدء الخدمة ولا بعد الآن',
    'TRANSFER_SAME_BARBER': 'الحجز عند هذا الحلاق أصلًا',
    'TRANSFER_NO_SLOT': 'لا يتسع وقت الحلاق المختار لهذا الحجز',
    'NO_SLOT': 'لا وقت متاح',
    'SLOT_UNAVAILABLE': 'هذا الوقت لم يعد متاحًا',
    'OUTSIDE_WORKING_HOURS': 'خارج ساعات العمل',
    'PAST_CLOSING': 'يتجاوز وقت الإغلاق',
    'MAX_ACTIVE_BOOKINGS': 'بلغ الزبون الحد الأقصى للحجوزات النشطة',
    'OFFER_NOT_FOUND': 'العرض غير موجود',
    'OFFER_EXPIRED': 'انتهت مهلة العرض',
    'IDEMPOTENCY_KEY_REUSED': 'تكرر الطلب ببيانات مختلفة — أعد المحاولة',
    'NOT_FOUND': 'العنصر غير موجود — ربما حُذف. حدّث الشاشة',
    // محلية (التطبيق)
    'OFFLINE_WALK_IN_REFUSED': 'لا يمكن إضافة زبون حاضر دون اتصال بالإنترنت.',
    'DEVICE_HELD': 'على هذا الجهاز إجراءات لم تُرفع لحساب آخر — سلّم الجهاز للمدير.',
  };

  /// أسباب رفض أحداث المزامنة (`POST /sync/events` ← `rejected` + السبب).
  static const syncReasons = <String, String>{
    'BARBER_ABSENT': 'أنت مسجّل «لن أعمل اليوم»',
    'ABSENCE_SET_BY_MANAGER': 'سجّل المدير غيابك اليوم؛ التراجع عنه من المدير',
    'BREAK_ALREADY_OPEN': 'لديك استراحة مفتوحة',
    'NO_OPEN_BREAK': 'لا استراحة مفتوحة لإنهائها',
    'NOT_WORKING': 'لا دوام لك الآن',
    'NOT_YOUR_BOOKING': 'الحجز ليس في طابورك (ربما نقله المدير)',
    'BOOKING_NOT_FOUND': 'الحجز غير موجود',
    'BOOKING_NOT_ACTIVE': 'الحجز لم يعد قائمًا',
    'BOOKING_REQUIRED': 'الإجراء بلا حجز',
    'NOT_CONFIRMED': 'الحجز لم يُؤكَّد بعد',
    'ALREADY_STARTED': 'بدأت الخدمة مسبقًا',
    'ALREADY_FINISHED': 'انتهت الخدمة مسبقًا',
    'ANOTHER_IN_SERVICE': 'زبون آخر قيد الخدمة الآن',
    'IN_SERVICE': 'الزبون قيد الخدمة',
    'NOT_IN_SERVICE': 'الخدمة لم تبدأ',
    'NOT_POSTPONED': 'لم يُؤجَّل هذا الزبون',
    'POSTPONE_ALREADY_USED': 'استُخدم التأجيل مسبقًا لهذا الحجز',
    'NO_SHOW_BEFORE_POSTPONEMENT': '«لم يحضر» يُسجَّل بعد تأجيله أولًا',
    'PAYMENT_ALREADY_CONFIRMED': 'الدفع مؤكد مسبقًا',
    'NO_PAYMENT_YET': 'لا دفعة بعد لهذا الحجز',
    'SERVICE_UNAVAILABLE': 'إحدى الخدمات غير متاحة',
    'EVENT_TOO_OLD': 'الإجراء قديم جدًا',
    'INVALID_TIME': 'وقت الإجراء غير صالح',
    'INVALID_PAYLOAD': 'بيانات الإجراء غير صالحة',
    'UNKNOWN_EVENT_TYPE': 'نوع إجراء غير معروف (حدّث التطبيق)',
    'ACCOUNT_REVOKED': 'بعد إيقاف الحساب',
    'TOO_MANY_EVENTS': 'دفعة كبيرة جدًا',
  };

  /// أسماء الحقول في أخطاء التحقق (`details[].path` بلا الفهارس).
  static const fields = <String, String>{
    'salon.name': 'اسم الصالون',
    'salon.timezone': 'بلد الصالون (التوقيت)',
    'salon.currency': 'العملة',
    'salon.phone': 'هاتف الصالون',
    'salon.address': 'العنوان',
    'salon.about': 'النبذة',
    'owner.name': 'اسمك',
    'owner.username': 'اسم المستخدم',
    'owner.password': 'كلمة المرور',
    'salonCode': 'رمز الصالون',
    'username': 'اسم المستخدم',
    'password': 'كلمة المرور',
    'newPassword': 'كلمة المرور الجديدة',
    'identifier': 'اسم المستخدم',
    'code': 'الرمز',
    'name': 'الاسم',
    'role': 'الصلاحية',
    'active': 'الحالة',
    'callAheadMinutes': 'الاستدعاء المسبق',
    'durationMinutes': 'المدة',
    'price': 'السعر',
    'position': 'الترتيب',
    'kind': 'النوع',
    'description': 'الوصف',
    'features': 'المزايا',
    'visible': 'الظهور',
    'serviceId': 'الخدمة المرتبطة',
    'serviceIds': 'الخدمات',
    'about': 'النبذة',
    'address': 'العنوان',
    'location': 'الموقع',
    'location.lat': 'الموقع',
    'location.lng': 'الموقع',
    'phone': 'رقم الهاتف',
    'whatsapp': 'رقم واتساب',
    'socialLinks': 'روابط التواصل',
    'socialLinks.url': 'رابط التواصل',
    'socialLinks.platform': 'منصة التواصل',
    'staffId': 'الحلاق',
    'weekday': 'اليوم',
    'opensAt': 'وقت الافتتاح',
    'closesAt': 'وقت الإغلاق',
    'type': 'النوع',
    'startTime': 'وقت البداية',
    'endTime': 'وقت النهاية',
    'workDate': 'التاريخ',
    'startsAt': 'وقت البداية',
    'endsAt': 'وقت النهاية',
    'reason': 'السبب',
    'bookingId': 'الحجز',
    'toBarberId': 'الحلاق',
    'actualEnd': 'وقت الانتهاء',
    'walkInId': 'سجل الحاضر',
    'file': 'الملف',
    'from': 'بداية الفترة',
    'to': 'نهاية الفترة',
    'events': 'الإجراءات',
    'requireAccountApproval': 'اعتماد حسابات الزبائن',
    'maxActiveBookingsPerCustomer': 'الحجوزات النشطة لكل زبون',
    'bookingOpensBeforeMinutes': 'فتح الحجز قبل الافتتاح',
    'etaChangeNotifyMinutes': 'هامش التنبيه الإلزامي',
    'maxDisconnectWindowMinutes': 'نافذة الانقطاع القصوى',
    'gapMarginMinMinutes': 'هامش ملء الفراغ (أدنى)',
    'gapMarginPercent': 'هامش ملء الفراغ (نسبة)',
    'offerHoldMinutes': 'مدة حجز العرض',
    'barberNotConnectedAlertMinutes': 'تنبيه عدم اتصال الحلاق',
    'overrunAlertPercent': 'تنبيه تجاوز المدة',
    'dayCloseGraceMinutes': 'مهلة إغلاق اليوم',
  };

  /// رموز مشكلات التحقق (zod + رموز السيرفر الخاصة).
  static const issues = <String, String>{
    'too_small': 'قصير جدًا أو أقل من المسموح',
    'too_big': 'طويل جدًا أو أكبر من المسموح',
    'invalid_type': 'مفقود أو بصيغة غير صحيحة',
    'invalid_format': 'صيغته غير صحيحة',
    'invalid_string': 'صيغته غير صحيحة',
    'invalid_value': 'قيمة غير مقبولة',
    'invalid_enum_value': 'قيمة غير مقبولة',
    'invalid_union': 'صيغته غير صحيحة',
    'unrecognized_keys': 'حقل غير معروف (حدّث التطبيق)',
    'custom': 'قيمة غير مقبولة',
    'required': 'مطلوب',
    'empty': 'فارغ',
    'invalid': 'غير صالح',
    'invalid_uuid': 'غير صالح',
    'not_found': 'غير موجود',
    'invalid_timezone': 'منطقة زمنية غير مدعومة في السيرفر',
    'invalid_currency': 'عملة غير مدعومة في السيرفر',
    'invalid_username':
        'يبدأ بحرف لاتيني أو رقم، ثم 2–31 من الحروف اللاتينية الصغيرة أو الأرقام أو . _ -',
    'invalid_international_phone': 'يلزم رقم دولي كامل يبدأ بـ + أو 00 ثم رمز الدولة (مثل ‎+970599123456)',
    'invalid_phone': 'رقم هاتف غير صالح',
    'invalid_time': 'وقت غير صالح',
    'range_too_large': 'الفترة أطول من سنة',
    'too_large': 'كبير جدًا',
    'unsupported_image_type': 'ليس صورة JPEG أو PNG أو WebP',
    'not_a_walk_in': 'ليس سجل زبون حاضر',
  };

  static String _fieldName(String path) {
    final bare = path.split('.').where((p) => int.tryParse(p) == null).join('.');
    return fields[bare] ?? fields[bare.split('.').last] ?? (bare.isEmpty ? 'الطلب' : bare);
  }

  /// «البيانات غير صحيحة — اسم المستخدم: …؛ رقم واتساب: …».
  static String validation(List<sa.ValidationIssue> list) {
    if (list.isEmpty) return 'البيانات المدخلة غير صحيحة';
    final seen = <String>{};
    final parts = <String>[];
    for (final i in list) {
      final line = '${_fieldName(i.path)}: ${issues[i.code] ?? 'غير صالح'}';
      if (seen.add(line)) parts.add(line);
    }
    return 'البيانات غير صحيحة — ${parts.take(3).join('؛ ')}';
  }

  /// اسم نوع الخطأ للرمز `C-…` (دون «_» الداخلية).
  static String typeName(Object e) {
    final t = e.runtimeType.toString().replaceAll(RegExp(r'^_+'), '');
    final lt = t.indexOf('<');
    return lt > 0 ? t.substring(0, lt) : t;
  }

  /// خطأ من قاعدة الجهاز المحلية (SQLite/SQLCipher عبر Drift).
  static bool isLocalStoreError(Object e) {
    final t = e.runtimeType.toString();
    if (t.contains('Sqlite') || t.contains('Drift')) return true;
    final s = e.toString();
    return e is ArgumentError && (s.contains('.so') || s.contains('dynamic library'));
  }
}

/// نص عربي واضح لأي خطأ يُعرض للمستخدم؛ ويطبع الأصل ومكدّسه في سجل التطبيق.
String describeError(Object e, [StackTrace? stack]) {
  _log(e, stack);
  if (e is sa.ApiError) return _describeApi(e);
  if (e is StateError) return e.message;
  final code = 'C-${ErrorTexts.typeName(e)}';
  if (ErrorTexts.isLocalStoreError(e)) {
    return 'تعذّر الحفظ في ذاكرة الهاتف (قاعدة البيانات المحلية). أعد تشغيل التطبيق، '
        'وإن تكرر فأبلغنا بالرمز (رمز: $code)';
  }
  return '${ErrorTexts.unexpected} في التطبيق (رمز: $code)';
}

String _describeApi(sa.ApiError e) {
  switch (e.networkFailure) {
    case sa.NetworkFailure.noInternet:
      return 'لا اتصال بالإنترنت — تحقق من الشبكة وحاول مجددًا';
    case sa.NetworkFailure.serverUnreachable:
      return 'تعذّر الوصول للسيرفر — تحقق من الإنترنت أو حاول بعد قليل';
    case sa.NetworkFailure.timeout:
      return 'انتهت مهلة الاتصال بالسيرفر — الشبكة بطيئة أو السيرفر مشغول، حاول مجددًا';
    case null:
      break;
  }
  final ref = e.shortRequestId == null ? null : 'S-${e.shortRequestId}';
  if (e.code == 'VALIDATION_FAILED') {
    final text = ErrorTexts.validation(e.validationIssues);
    return e.validationIssues.isEmpty && ref != null ? '$text (رمز: $ref)' : text;
  }
  // رد ليس من السيرفر نفسه (صفحة من الوسيط): السيرفر متوقف أو يُعاد تشغيله.
  if (e.code.startsWith('HTTP_')) {
    final status = e.statusCode ?? int.tryParse(e.code.substring(5)) ?? 0;
    final tag = ref ?? 'HTTP-$status';
    if (status == 502 || status == 503 || status == 504) {
      return 'السيرفر لا يستجيب حاليًا — حاول بعد قليل (رمز: $tag)';
    }
    return '${ErrorTexts.unexpected} (رمز: $tag)';
  }
  final status = e.statusCode ?? 0;
  if (e.code == 'INTERNAL' || e.code == 'INTERNAL_ERROR' || status >= 500 && !ErrorTexts.codes.containsKey(e.code)) {
    return '${ErrorTexts.unexpected} في السيرفر (رمز: ${ref ?? 'HTTP-$status'})';
  }
  final known = ErrorTexts.codes[e.code];
  if (known != null) return known;
  // رمز لا يعرفه التطبيق: رسالة السيرفر العربية، ومعها الرمز إن كانت عامة.
  final generic = e.message.isEmpty ||
      e.message == ErrorTexts.unexpected ||
      e.message == 'طلب غير صالح' ||
      e.message == 'تعذر تنفيذ الطلب';
  if (!generic) return e.message;
  return '${e.message.isEmpty ? ErrorTexts.unexpected : e.message} (رمز: ${ref ?? e.code})';
}

void _log(Object e, StackTrace? stack) {
  final st = stack ?? (e is Error ? e.stackTrace : null);
  final extra = e is sa.ApiError
      ? ' [code=${e.code} http=${e.statusCode} request=${e.requestId} details=${e.details}]'
      : '';
  debugPrint('[saloni] error ${ErrorTexts.typeName(e)}: $e$extra${st == null ? '' : '\n$st'}');
}

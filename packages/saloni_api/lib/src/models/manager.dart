import 'booking.dart';
import 'json_utils.dart';
import 'staff_today.dart';

/// طابور حلاق واحد في `GET /manager/queues`:
/// `{id, name, role, day | null, accepting, queue[Booking]}`.
class ManagerBarberQueue {
  const ManagerBarberQueue({
    required this.id,
    required this.name,
    this.role,
    this.day,
    this.accepting = false,
    this.queue = const [],
  });

  final String id;
  final String name;
  final String? role;

  /// يومه الحالي، أو `null` إن لم يكن في دوامه.
  final StaffDay? day;
  final bool accepting;

  /// الحجوزات (بلا العروض المؤقتة)، بالحقول الكاملة مع `customerPhone`.
  final List<Booking> queue;

  factory ManagerBarberQueue.fromJson(Map<String, dynamic> json) =>
      ManagerBarberQueue(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        role: json['role'] as String?,
        day: json['day'] is Map ? StaffDay.fromJson(asMap(json['day'])) : null,
        accepting: json['accepting'] as bool? ?? false,
        queue: parseList(json['queue'], Booking.fromJson),
      );
}

/// `GET /manager/queues` — طوابير اليوم لكل الحلاقين (ق25):
/// `{serverTime, seq, barbers[]}`.
class ManagerQueues {
  const ManagerQueues({
    required this.serverTime,
    required this.seq,
    required this.barbers,
  });

  final DateTime serverTime;
  final int seq;
  final List<ManagerBarberQueue> barbers;

  factory ManagerQueues.fromJson(Map<String, dynamic> json) => ManagerQueues(
        serverTime: parseUtcOrNull(json['serverTime'] as String?) ??
            DateTime.now().toUtc(),
        seq: asIntOrNull(json['seq']) ?? 0,
        barbers: parseList(json['barbers'], ManagerBarberQueue.fromJson),
      );
}

/// سجل حاضر غير مربوط في نزاع رقم: `{id, name, createdAt}`.
class WalkInRecord {
  const WalkInRecord({required this.id, required this.name, this.createdAt});

  final String id;
  final String name;
  final DateTime? createdAt;

  factory WalkInRecord.fromJson(Map<String, dynamic> json) => WalkInRecord(
        id: json['id'] as String,
        name: json['name'] as String? ?? '',
        createdAt: parseUtcOrNull(json['createdAt'] as String?),
      );
}

/// `GET /manager/phone-disputes` (ق20): رقم له أكثر من سجل حاضر غير مربوط.
/// `{phone, accountId | null, walkIns[]}` — يُحل بـ
/// `POST /manager/phone-disputes/{accountId}/resolve {walkInId}`.
class PhoneDispute {
  const PhoneDispute({
    required this.phone,
    this.accountId,
    this.accountStatus,
    this.linkedWalkInId,
    this.proposedWalkInId,
    this.walkIns = const [],
  });

  final String phone;

  /// حساب التطبيق بنفس الرقم (إن وُجد) — لا يمكن الحل بدونه.
  final String? accountId;

  /// حالة ذلك الحساب (`pending`/`active`/`suspended`) — رقم لحساب معلَّق أو
  /// موقوف قد يظهر هنا أيضًا (مراجعة المرحلة 6).
  final String? accountStatus;

  /// سجل الحاضر المربوط فعليًا بالحساب حاليًا، إن وُجد.
  final String? linkedWalkInId;

  /// ربط مقترح (H2): يصبح فعليًا فقط بعد اعتماد الحساب.
  final String? proposedWalkInId;
  final List<WalkInRecord> walkIns;

  factory PhoneDispute.fromJson(Map<String, dynamic> json) => PhoneDispute(
        phone: json['phone'] as String? ?? '',
        accountId: json['accountId'] as String?,
        accountStatus: json['accountStatus'] as String?,
        linkedWalkInId: json['linkedWalkInId'] as String?,
        proposedWalkInId: json['proposedWalkInId'] as String?,
        walkIns: parseList(json['walkIns'], WalkInRecord.fromJson),
      );
}

/// صورة مرفوعة للصالون: `{id, url, position}` (+ `path`).
class SalonPhotoUpload {
  const SalonPhotoUpload({
    required this.id,
    this.url,
    this.path,
    this.position,
  });

  final String id;

  /// رابط العرض (`/v1/media/{code}/{file}`) — نسبي للسيرفر؛ انظر
  /// `ApiClient.resolveMediaUrl`.
  final String? url;
  final String? path;
  final int? position;

  factory SalonPhotoUpload.fromJson(Map<String, dynamic> json) =>
      SalonPhotoUpload(
        id: json['id'] as String,
        url: json['url'] as String?,
        path: json['path'] as String?,
        position: asIntOrNull(json['position']),
      );
}

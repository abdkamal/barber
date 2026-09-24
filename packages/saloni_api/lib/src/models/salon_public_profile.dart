import 'enums.dart';
import 'json_utils.dart';
import 'service.dart';

/// ساعات يوم واحد من الأسبوع (`weekday`: 0 = الأحد … 6 = السبت، اصطلاح
/// السيرفر)، بوقت الصالون المحلي `HH:MM`. `crossesMidnight` عندما
/// `closesAt <= opensAt` (ق30). الأيام غير المذكورة مغلقة.
class WorkingHoursEntry {
  const WorkingHoursEntry({
    required this.weekday,
    required this.opensAt,
    required this.closesAt,
    this.crossesMidnight = false,
  });

  final int weekday;
  final String opensAt;
  final String closesAt;
  final bool crossesMidnight;

  static int _minutes(String hhmm) {
    final parts = hhmm.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  /// دقائق منذ منتصف الليل للافتتاح.
  int get openMinutes => _minutes(opensAt);

  /// دقائق منذ منتصف الليل للإغلاق؛ تتجاوز 1440 إن عبر منتصف الليل.
  int get closeMinutes => _minutes(closesAt) + (crossesMidnight ? 1440 : 0);

  /// يوم الأسبوع باصطلاح Dart (`DateTime.monday` = 1 … `DateTime.sunday` = 7).
  int get dartWeekday => weekday == 0 ? DateTime.sunday : weekday;

  factory WorkingHoursEntry.fromJson(Map<String, dynamic> json) =>
      WorkingHoursEntry(
        weekday: asIntOrNull(json['weekday']) ?? 0,
        opensAt: json['opensAt'] as String,
        closesAt: json['closesAt'] as String,
        crossesMidnight: json['crossesMidnight'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'weekday': weekday,
        'opensAt': opensAt,
        'closesAt': closesAt,
        'crossesMidnight': crossesMidnight,
      };
}

/// رابط تواصل اجتماعي: `{platform, url}`.
class SocialLink {
  const SocialLink({required this.platform, required this.url});

  final String platform;
  final String url;

  factory SocialLink.fromJson(Map<String, dynamic> json) => SocialLink(
        platform: json['platform'] as String? ?? '',
        url: json['url'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {'platform': platform, 'url': url};
}

/// وسائل التواصل — كلها اختيارية (ق37): `{phone, whatsapp, social[]}`.
class SalonContactInfo {
  const SalonContactInfo({this.phone, this.whatsapp, this.socialLinks = const []});

  final String? phone;
  final String? whatsapp;
  final List<SocialLink> socialLinks;

  factory SalonContactInfo.fromJson(Map<String, dynamic> json) =>
      SalonContactInfo(
        phone: json['phone'] as String?,
        whatsapp: json['whatsapp'] as String?,
        socialLinks: parseList(json['social'] ?? json['socialLinks'], SocialLink.fromJson),
      );

  Map<String, dynamic> toJson() => {
        'phone': phone,
        'whatsapp': whatsapp,
        'social': socialLinks.map((e) => e.toJson()).toList(),
      };
}

/// صورة معرض الصالون: `{id, url, position}`.
class SalonPhoto {
  const SalonPhoto({this.id, required this.url, this.position = 0});

  final String? id;

  /// نسبي للسيرفر (`/v1/media/{code}/{file}`) — `ApiClient.resolveMediaUrl`.
  final String url;
  final int position;

  factory SalonPhoto.fromJson(Map<String, dynamic> json) => SalonPhoto(
        id: json['id'] as String?,
        url: json['url'] as String,
        position: asIntOrNull(json['position']) ?? 0,
      );

  Map<String, dynamic> toJson() => {'id': id, 'url': url, 'position': position};
}

/// عنصر كتالوج (خدمة أو منتج) — صفحة «حول الصالون» (ق37) و`/manager/catalog`:
/// `{id, kind, name, description, features[], price | null, photo, serviceId,
/// position?, visible?}`.
class CatalogItem {
  const CatalogItem({
    required this.id,
    required this.type,
    required this.name,
    this.description,
    this.features = const [],
    this.priceCents,
    this.photoUrl,
    this.position = 0,
    this.visible = true,
    this.serviceId,
  });

  final String id;
  final CatalogItemType type;
  final String name;
  final String? description;
  final List<String> features;

  /// السعر (قد يغيب لمنتج بلا سعر معلن).
  final int? priceCents;
  final String? photoUrl;
  final int position;
  final bool visible;

  /// معرّف الخدمة القابلة للحجز المرتبطة بهذا العنصر (إن كان نوعه خدمة).
  final String? serviceId;

  factory CatalogItem.fromJson(Map<String, dynamic> json) => CatalogItem(
        id: json['id'] as String,
        type: CatalogItemType.fromWire((json['kind'] ?? json['type']) as String),
        name: json['name'] as String,
        description: json['description'] as String?,
        features: parseStringList(json['features']),
        priceCents: asIntOrNull(json['price'] ?? json['priceCents']),
        photoUrl: (json['photo'] ?? json['photoUrl']) as String?,
        position: asIntOrNull(json['position']) ?? 0,
        visible: json['visible'] as bool? ?? true,
        serviceId: json['serviceId'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'kind': type.toWire(),
        'name': name,
        'description': description,
        'features': features,
        'price': priceCents,
        'photo': photoUrl,
        'position': position,
        'visible': visible,
        'serviceId': serviceId,
      };
}

/// ملف الصالون العام — `GET /salons/{code}` (ق37)، للصالونات المفعّلة فقط.
class SalonPublicProfile {
  const SalonPublicProfile({
    required this.code,
    required this.name,
    required this.currency,
    required this.timezone,
    this.about,
    this.logoUrl,
    this.address,
    this.latitude,
    this.longitude,
    this.contact = const SalonContactInfo(),
    this.photos = const [],
    this.hours = const [],
    this.openNow = false,
    this.services = const [],
    this.catalog = const [],
  });

  final String code;
  final String name;

  /// رمز العملة (ق34)، مثل `SAR`.
  final String currency;

  /// المنطقة الزمنية للصالون (design.md §2).
  final String timezone;

  /// النبذة.
  final String? about;

  /// نسبي للسيرفر — `ApiClient.resolveMediaUrl`.
  final String? logoUrl;
  final String? address;
  final double? latitude;
  final double? longitude;
  final SalonContactInfo contact;
  final List<SalonPhoto> photos;

  /// ساعات العمل الأسبوعية (الأيام الغائبة مغلقة).
  final List<WorkingHoursEntry> hours;
  final bool openNow;

  /// الخدمات القابلة للحجز.
  final List<Service> services;
  final List<CatalogItem> catalog;

  bool get hasLocation => latitude != null && longitude != null;

  factory SalonPublicProfile.fromJson(Map<String, dynamic> json) {
    final location = json['location'];
    return SalonPublicProfile(
      code: json['code'] as String,
      name: json['name'] as String,
      currency: json['currency'] as String? ?? 'SAR',
      timezone: json['timezone'] as String? ?? 'Asia/Riyadh',
      about: json['about'] as String?,
      logoUrl: json['logo'] as String?,
      address: json['address'] as String?,
      latitude: location is Map ? (location['lat'] as num?)?.toDouble() : null,
      longitude: location is Map ? (location['lng'] as num?)?.toDouble() : null,
      contact: json['contact'] is Map
          ? SalonContactInfo.fromJson(asMap(json['contact']))
          : const SalonContactInfo(),
      photos: parseList(json['photos'], SalonPhoto.fromJson),
      hours: parseList(json['hours'], WorkingHoursEntry.fromJson),
      openNow: json['openNow'] as bool? ?? false,
      services: parseList(json['services'], Service.fromJson),
      catalog: parseList(json['catalog'], CatalogItem.fromJson),
    );
  }

  Map<String, dynamic> toJson() => {
        'code': code,
        'name': name,
        'currency': currency,
        'timezone': timezone,
        'about': about,
        'logo': logoUrl,
        'address': address,
        'location': hasLocation ? {'lat': latitude, 'lng': longitude} : null,
        'contact': contact.toJson(),
        'photos': photos.map((e) => e.toJson()).toList(),
        'hours': hours.map((e) => e.toJson()).toList(),
        'openNow': openNow,
        'services': services
            .map((s) => {
                  'id': s.id,
                  'name': s.name,
                  'durationMin': s.baseDurationMin,
                  'price': s.priceCents,
                })
            .toList(),
        'catalog': catalog.map((e) => e.toJson()).toList(),
      };
}

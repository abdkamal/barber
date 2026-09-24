import 'enums.dart';
import 'json_utils.dart';

/// ساعات عمل يوم واحد من أيام الأسبوع (0 = الأحد ... حسب اصطلاح السيرفر).
/// `openMinutes`/`closeMinutes` دقائق منذ منتصف الليل؛ قد يتجاوز الإغلاق 1440
/// إذا امتد الدوام بعد منتصف الليل (design.md ق30).
class WorkingHoursEntry {
  const WorkingHoursEntry({
    required this.weekday,
    required this.openMinutes,
    required this.closeMinutes,
    this.closed = false,
  });

  final int weekday;
  final int openMinutes;
  final int closeMinutes;
  final bool closed;

  factory WorkingHoursEntry.fromJson(Map<String, dynamic> json) =>
      WorkingHoursEntry(
        weekday: json['weekday'] as int,
        openMinutes: json['openMinutes'] as int,
        closeMinutes: json['closeMinutes'] as int,
        closed: json['closed'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'weekday': weekday,
        'openMinutes': openMinutes,
        'closeMinutes': closeMinutes,
        'closed': closed,
      };
}

/// وسائل التواصل — كلها اختيارية (ق37).
class SalonContactInfo {
  const SalonContactInfo({this.phone, this.whatsapp, this.socialLinks = const []});

  final String? phone;
  final String? whatsapp;
  final List<String> socialLinks;

  factory SalonContactInfo.fromJson(Map<String, dynamic> json) =>
      SalonContactInfo(
        phone: json['phone'] as String?,
        whatsapp: json['whatsapp'] as String?,
        socialLinks: parseStringList(json['socialLinks']),
      );

  Map<String, dynamic> toJson() => {
        'phone': phone,
        'whatsapp': whatsapp,
        'socialLinks': socialLinks,
      };
}

class SalonPhoto {
  const SalonPhoto({required this.url, required this.order});

  final String url;
  final int order;

  factory SalonPhoto.fromJson(Map<String, dynamic> json) => SalonPhoto(
        url: json['url'] as String,
        order: json['order'] as int,
      );

  Map<String, dynamic> toJson() => {'url': url, 'order': order};
}

/// عنصر كتالوج (خدمة أو منتج) كما يظهر في صفحة «حول الصالون» (ق37).
class CatalogItem {
  const CatalogItem({
    required this.id,
    required this.type,
    required this.name,
    this.description,
    this.features = const [],
    required this.priceCents,
    this.photoUrl,
    required this.order,
    this.visible = true,
    this.serviceId,
  });

  final String id;
  final CatalogItemType type;
  final String name;
  final String? description;
  final List<String> features;
  final int priceCents;
  final String? photoUrl;
  final int order;
  final bool visible;

  /// معرّف الخدمة القابلة للحجز المرتبطة بهذا العنصر (إن كان نوعه خدمة).
  final String? serviceId;

  factory CatalogItem.fromJson(Map<String, dynamic> json) => CatalogItem(
        id: json['id'] as String,
        type: CatalogItemType.fromWire(json['type'] as String),
        name: json['name'] as String,
        description: json['description'] as String?,
        features: parseStringList(json['features']),
        priceCents: json['priceCents'] as int,
        photoUrl: json['photoUrl'] as String?,
        order: json['order'] as int,
        visible: json['visible'] as bool? ?? true,
        serviceId: json['serviceId'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type.toWire(),
        'name': name,
        'description': description,
        'features': features,
        'priceCents': priceCents,
        'photoUrl': photoUrl,
        'order': order,
        'visible': visible,
        'serviceId': serviceId,
      };
}

/// ملف الصالون العام — `GET /salons/{code}` (ق37).
class SalonPublicProfile {
  const SalonPublicProfile({
    required this.code,
    required this.name,
    this.logoUrl,
    this.bio,
    this.address,
    this.latitude,
    this.longitude,
    required this.currency,
    required this.timezone,
    required this.contact,
    this.photos = const [],
    this.workingHours = const [],
    this.catalog = const [],
  });

  final String code;
  final String name;
  final String? logoUrl;
  final String? bio;
  final String? address;
  final double? latitude;
  final double? longitude;

  /// رمز العملة (ق34)، مثل `SAR`.
  final String currency;

  /// المنطقة الزمنية للصالون (design.md §2، قاعدة الدليل).
  final String timezone;

  final SalonContactInfo contact;
  final List<SalonPhoto> photos;
  final List<WorkingHoursEntry> workingHours;
  final List<CatalogItem> catalog;

  factory SalonPublicProfile.fromJson(Map<String, dynamic> json) =>
      SalonPublicProfile(
        code: json['code'] as String,
        name: json['name'] as String,
        logoUrl: json['logoUrl'] as String?,
        bio: json['bio'] as String?,
        address: json['address'] as String?,
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        currency: json['currency'] as String,
        timezone: json['timezone'] as String,
        contact: json['contact'] == null
            ? const SalonContactInfo()
            : SalonContactInfo.fromJson(json['contact'] as Map<String, dynamic>),
        photos: parseList(json['photos'], SalonPhoto.fromJson),
        workingHours: parseList(json['workingHours'], WorkingHoursEntry.fromJson),
        catalog: parseList(json['catalog'], CatalogItem.fromJson),
      );

  Map<String, dynamic> toJson() => {
        'code': code,
        'name': name,
        'logoUrl': logoUrl,
        'bio': bio,
        'address': address,
        'latitude': latitude,
        'longitude': longitude,
        'currency': currency,
        'timezone': timezone,
        'contact': contact.toJson(),
        'photos': photos.map((e) => e.toJson()).toList(),
        'workingHours': workingHours.map((e) => e.toJson()).toList(),
        'catalog': catalog.map((e) => e.toJson()).toList(),
      };
}

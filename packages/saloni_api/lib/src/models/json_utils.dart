/// أدوات مساعدة لتحويل JSON — كل الأوقات ISO-8601 UTC (api.md، الفقرة الأولى).
library;

DateTime parseUtc(String value) => DateTime.parse(value).toUtc();

DateTime? parseUtcOrNull(String? value) =>
    value == null ? null : DateTime.parse(value).toUtc();

String toIso(DateTime value) => value.toUtc().toIso8601String();

String? toIsoOrNull(DateTime? value) => value == null ? null : toIso(value);

List<T> parseList<T>(
  Object? value,
  T Function(Map<String, dynamic>) fromJson,
) {
  if (value == null) return const [];
  return (value as List)
      .map((e) => fromJson(e as Map<String, dynamic>))
      .toList(growable: false);
}

List<String> parseStringList(Object? value) {
  if (value == null) return const [];
  return (value as List).map((e) => e as String).toList(growable: false);
}

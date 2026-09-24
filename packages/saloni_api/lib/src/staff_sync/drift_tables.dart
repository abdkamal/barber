import 'package:drift/drift.dart';

/// جدول عام مفتاح/قيمة (JSON نصي) — طابور اليوم، الخدمات، الاستراحات،
/// الإعدادات، مؤشر المزامنة، آخر وقت سيرفر، وعدّاد رقم تسلسل الجهاز
/// (design.md §2، §6.1). تبسيط متعمد لتفادي تكرار مخطط الحجز بالكامل محليًا
/// بينما تبقى القراءة والكتابة ذرّية عبر Drift.
class KeyValueEntries extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// صندوق أحداث الجهاز (design.md §6.2).
@DataClassName('OutboxRow')
class OutboxEntries extends Table {
  TextColumn get eventId => text()();
  IntColumn get deviceSeq => integer()();
  TextColumn get eventJson => text()();
  TextColumn get status => text().withDefault(const Constant('pending'))();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  DateTimeColumn get nextRetryAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {eventId};
}

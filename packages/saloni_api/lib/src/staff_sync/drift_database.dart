import 'package:drift/drift.dart';

import 'drift_tables.dart';

part 'drift_database.g.dart';

/// قاعدة بيانات SQLite محلية لتطبيق الطاقم (design.md §6.1).
///
/// التشفير: يُفتح هذا النوع عادة فوق [QueryExecutor] عادي (`NativeDatabase`)،
/// وهو ما يجعله قابلًا للاختبار بـ`dart test` بلا Flutter. التشفير بـ
/// SQLCipher (المفتاح من التخزين الآمن) يُضاف عبر منفّذ استعلام مختلف يُبنى
/// في `lib/staff_sync.dart` (الجزء المعتمد على Flutter)، باستخدام
/// `sqlcipher_flutter_libs` — انظر التعليق هناك وREADME للتفاصيل وما لم
/// يُختبر منها فعليًا على جهاز حقيقي (لا يوجد Android SDK في هذه البيئة).
@DriftDatabase(tables: [KeyValueEntries, OutboxEntries])
class StaffSyncDatabase extends _$StaffSyncDatabase {
  StaffSyncDatabase(super.executor);

  @override
  int get schemaVersion => 1;
}

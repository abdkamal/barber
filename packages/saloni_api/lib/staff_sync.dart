/// دعم عمل تطبيق الطاقم دون اتصال (design.md §6): تخزين محلي، صندوق أحداث،
/// ساعة رتيبة، ومحرك مزامنة. مكتبة منفصلة عن `saloni_api.dart` الأساسية
/// (تُستورد فقط من تطبيق الطاقم)، لكنها تبقى Dart نقيًا وقابلة للاختبار عبر
/// `dart test` — بما في ذلك تنفيذ Drift/SQLite، عبر `NativeDatabase` (FFI).
///
/// **التشفير (SQLCipher):** فتح قاعدة مشفّرة فعليًا يحتاج مكتبات
/// `sqlcipher_flutter_libs` (اعتماد Flutter)، لذا وُضع خلف
/// `openEncryptedStaffSyncExecutor` في `saloni_api/flutter.dart` بدل هذه
/// المكتبة — انظر التعليق هناك وREADME لما لم يُختبر منه فعليًا (لا يوجد
/// Android SDK في هذه البيئة).
library;

export 'src/staff_sync/connection_state.dart';
export 'src/staff_sync/drift_database.dart';
export 'src/staff_sync/drift_local_store.dart';
export 'src/staff_sync/local_store.dart';
export 'src/staff_sync/monotonic_clock.dart';
export 'src/staff_sync/outbox.dart';
export 'src/staff_sync/sync_engine.dart';

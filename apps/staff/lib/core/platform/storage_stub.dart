import 'storage.dart';

/// الويب: لا SQLite ولا تخزين آمن — ذاكرة فقط (نسخة الويب للفحص فقط؛ المنتج أندرويد).
StoragePlatform createStoragePlatform() => InMemoryStoragePlatform();

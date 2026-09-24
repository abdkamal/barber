import 'package:saloni_api/saloni_api.dart';
import 'package:saloni_api/staff_sync.dart';

import 'storage_stub.dart' if (dart.library.io) 'storage_native.dart' as impl;

/// مقبض التخزين المحلي للطاقم (design.md §6.1).
abstract class LocalStoreHandle {
  LocalStore get store;

  /// يغلق القاعدة دون حذف بياناتها.
  Future<void> close();

  /// يغلق القاعدة ويحذف ملفها ومفتاح تشفيرها (عند الخروج).
  Future<void> destroy();
}

/// مصنع التخزين المحلي ومخزن الجلسة — يُستبدل في الاختبارات.
abstract class StoragePlatform {
  Future<LocalStoreHandle> openLocalStore();
  TokenStore createTokenStore();
}

/// التنفيذ الافتراضي: SQLCipher + التخزين الآمن على الجهاز، وذاكرة على الويب.
StoragePlatform defaultStoragePlatform() => impl.createStoragePlatform();

/// مقبض في الذاكرة (للويب والاختبارات).
class InMemoryStoreHandle implements LocalStoreHandle {
  InMemoryStoreHandle([LocalStore? store]) : store = store ?? InMemoryLocalStore();
  @override
  final LocalStore store;
  @override
  Future<void> close() async {}
  @override
  Future<void> destroy() => store.wipe();
}

/// تخزين في الذاكرة يحاكي ملف قاعدة واحدًا: كل فتح يعيد نفس البيانات، و`destroy`
/// يمسحها.
class InMemoryStoragePlatform implements StoragePlatform {
  InMemoryStoragePlatform({TokenStore? tokenStore})
      : _tokens = tokenStore ?? InMemoryTokenStore();
  final TokenStore _tokens;
  final LocalStore shared = InMemoryLocalStore();
  @override
  Future<LocalStoreHandle> openLocalStore() async => InMemoryStoreHandle(shared);
  @override
  TokenStore createTokenStore() => _tokens;
}

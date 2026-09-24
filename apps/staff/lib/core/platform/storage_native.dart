import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:saloni_api/flutter.dart';
import 'package:saloni_api/saloni_api.dart';
import 'package:saloni_api/staff_sync.dart';

import 'storage.dart';

const _dbFile = 'saloni_staff_sync.db';

StoragePlatform createStoragePlatform() => _NativeStoragePlatform();

class _NativeStoragePlatform implements StoragePlatform {
  @override
  TokenStore createTokenStore() => SecureStorageTokenStore();

  @override
  Future<LocalStoreHandle> openLocalStore() async {
    final key = await staffSyncEncryptionKey();
    final db = StaffSyncDatabase(
      openEncryptedStaffSyncExecutor(fileName: _dbFile, encryptionKey: key),
    );
    return _NativeHandle(db);
  }
}

class _NativeHandle implements LocalStoreHandle {
  _NativeHandle(this._db) : store = DriftLocalStore(_db);
  final StaffSyncDatabase _db;
  @override
  final LocalStore store;

  bool _closed = false;

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _db.close();
  }

  @override
  Future<void> destroy() async {
    try {
      await store.wipe();
    } catch (_) {}
    await close();
    try {
      final dir = await getApplicationSupportDirectory();
      final f = File('${dir.path}/$_dbFile');
      if (await f.exists()) await f.delete();
    } catch (_) {}
    // المفتاح يُمسح مع الملف (README saloni_api: «الخروج وإيقاف الحساب»).
    await wipeStaffSyncEncryptionKey();
  }
}

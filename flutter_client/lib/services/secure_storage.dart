import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:m3u_tv/services/async_lifecycle.dart';
import 'package:m3u_tv/services/persistent_store.dart';

/// Secure storage abstraction for persisting sensitive data like credentials.
///
/// Production implementations should use platform-specific encrypted storage
/// (e.g., flutter_secure_storage). The in-memory implementation is for tests.
abstract class SecureStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

extension ConditionalSecureStorageWrite on SecureStorage {
  Future<bool> writeIfCurrent(
    String key,
    String value,
    bool Function() shouldCommit,
  ) async {
    final storage = this;
    if (storage is InMemorySecureStorage) {
      return storage.writeIf(key, value, shouldCommit);
    }
    if (storage is FlutterSecureStorageAdapter) {
      return storage.writeIf(key, value, shouldCommit);
    }
    if (storage is FileSecureStorage) {
      return storage.writeIf(key, value, shouldCommit);
    }
    return writeStringIfCurrent(
      shouldCommit: shouldCommit,
      read: () => read(key),
      write: (v) => write(key, v),
      delete: () => delete(key),
      value: value,
    );
  }
}

/// Writes [value], but rolls back to whatever was previously stored if
/// [shouldCommit] is rejected either before the write or right after it
/// (e.g. ownership changed while the write was in flight).
Future<bool> writeStringIfCurrent({
  required bool Function() shouldCommit,
  required Future<String?> Function() read,
  required Future<void> Function(String value) write,
  required Future<void> Function() delete,
  required String value,
}) async {
  if (!shouldCommit()) return false;
  final previous = await read();
  if (!shouldCommit()) return false;
  await write(value);
  if (shouldCommit()) return true;
  if (previous == null) {
    await delete();
  } else {
    await write(previous);
  }
  return false;
}

/// In-memory secure storage for tests. Does NOT log or expose stored values
/// through toString to prevent credential leakage in test output.
class InMemorySecureStorage implements SecureStorage {
  final Map<String, String> _store = {};

  @override
  Future<String?> read(String key) async => _store[key];

  @override
  Future<void> write(String key, String value) async {
    _store[key] = value;
  }

  Future<bool> writeIf(
    String key,
    String value,
    bool Function() shouldCommit,
  ) async {
    if (!shouldCommit()) return false;
    _store[key] = value;
    return true;
  }

  @override
  Future<void> delete(String key) async {
    _store.remove(key);
  }

  @override
  String toString() => 'InMemorySecureStorage(${_store.length} keys)';
}

/// Secure storage backed by platform secure storage via flutter_secure_storage.
/// Use on Android, iOS, tvOS, Linux, and Windows.
class FlutterSecureStorageAdapter implements SecureStorage {
  FlutterSecureStorageAdapter() : _storage = const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  /// One queue per key so operations on unrelated keys don't serialize
  /// behind each other — only same-key ordering needs to be guaranteed.
  final Map<String, SerialQueue> _queues = {};

  SerialQueue _queueFor(String key) =>
      _queues.putIfAbsent(key, SerialQueue.new);

  @override
  Future<String?> read(String key) => _queueFor(key).run(
    () => _storage.read(key: key),
  );

  @override
  Future<void> write(String key, String value) => _queueFor(key).run(
    () => _storage.write(key: key, value: value),
  );

  Future<bool> writeIf(
    String key,
    String value,
    bool Function() shouldCommit,
  ) => _queueFor(key).run(
    () => writeStringIfCurrent(
      shouldCommit: shouldCommit,
      read: () => _storage.read(key: key),
      write: (v) => _storage.write(key: key, value: v),
      delete: () => _storage.delete(key: key),
      value: value,
    ),
  );

  @override
  Future<void> delete(String key) => _queueFor(key).run(
    () => _storage.delete(key: key),
  );
}

class FileSecureStorage implements SecureStorage {
  FileSecureStorage({PersistentJsonStore? store})
    : _store = store ?? PersistentJsonStore();

  final PersistentJsonStore _store;

  @override
  Future<String?> read(String key) async {
    final value = await _store.read(key);
    return value is String ? value : null;
  }

  @override
  Future<void> write(String key, String value) async {
    await _store.write(key, value);
  }

  Future<bool> writeIf(
    String key,
    String value,
    bool Function() shouldCommit,
  ) => _store.writeIf(key, value, shouldCommit);

  @override
  Future<void> delete(String key) async {
    await _store.delete(key);
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/persistent_store.dart';
import 'package:m3u_tv/services/production_storage.dart';
import 'package:m3u_tv/services/secure_storage.dart';

void main() {
  const credentialsKey = 'm3ue_tv_credentials';

  test('migration moves credentials out of plaintext app state', () async {
    final directory = await Directory.systemTemp.createTemp('m3u-tv-storage-');
    final stateFile = File('${directory.path}/app_state.json');
    final store = PersistentJsonStore(file: stateFile);
    final credentialStorage = InMemorySecureStorage();
    addTearDown(() => directory.delete(recursive: true));
    const usernameSentinel = 'plaintext-user-sentinel';
    const passwordSentinel = 'plaintext-password-sentinel';
    final credentialPayload = jsonEncode(<String, String>{
      'server': 'https://fixture.example',
      'username': usernameSentinel,
      'password': passwordSentinel,
    });
    await store.write(credentialsKey, credentialPayload);
    await store.write('m3ue_favorites', <int>[42]);

    await migrateLegacyCredentials(
      appStateStore: store,
      credentialStorage: credentialStorage,
    );

    expect(await credentialStorage.read(credentialsKey), credentialPayload);
    expect(await store.read(credentialsKey), isNull);
    expect(await store.read('m3ue_favorites'), <int>[42]);
    final appStateJson = await stateFile.readAsString();
    expect(appStateJson, isNot(contains(credentialsKey)));
    expect(appStateJson, isNot(contains(usernameSentinel)));
    expect(appStateJson, isNot(contains(passwordSentinel)));
  });

  test(
    'existing secure credentials win and stale plaintext is removed',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'm3u-tv-storage-',
      );
      final stateFile = File('${directory.path}/app_state.json');
      final store = PersistentJsonStore(file: stateFile);
      final credentialStorage = InMemorySecureStorage();
      addTearDown(() => directory.delete(recursive: true));
      await store.write(credentialsKey, 'stale-plaintext-credential');
      await credentialStorage.write(credentialsKey, 'secure-credential');

      await migrateLegacyCredentials(
        appStateStore: store,
        credentialStorage: credentialStorage,
      );

      expect(await credentialStorage.read(credentialsKey), 'secure-credential');
      expect(await store.read(credentialsKey), isNull);
      expect(
        await stateFile.readAsString(),
        isNot(contains('stale-plaintext-credential')),
      );
    },
  );

  test(
    'migration removes plaintext credentials if secure storage rejects them',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'm3u-tv-storage-',
      );
      final stateFile = File('${directory.path}/app_state.json');
      final store = PersistentJsonStore(file: stateFile);
      addTearDown(() => directory.delete(recursive: true));
      const usernameSentinel = 'rejected-user-sentinel';
      const passwordSentinel = 'rejected-password-sentinel';
      final credentialPayload = jsonEncode(<String, String>{
        'username': usernameSentinel,
        'password': passwordSentinel,
      });
      await store.write(credentialsKey, credentialPayload);
      await store.write('m3ue_favorites', <int>[42]);

      await migrateLegacyCredentials(
        appStateStore: store,
        credentialStorage: _FailingSecureStorage(),
      );

      expect(await store.read(credentialsKey), isNull);
      expect(await store.read('m3ue_favorites'), <int>[42]);
      final appStateJson = await stateFile.readAsString();
      expect(appStateJson, isNot(contains(credentialsKey)));
      expect(appStateJson, isNot(contains(usernameSentinel)));
      expect(appStateJson, isNot(contains(passwordSentinel)));
    },
  );

  group('ResilientSecureStorage', () {
    test('uses the primary storage when it works', () async {
      final primary = InMemorySecureStorage();
      final fallback = InMemorySecureStorage();
      final storage = ResilientSecureStorage(
        primary: primary,
        fallback: fallback,
      );

      await storage.write('key', 'value');

      expect(await primary.read('key'), 'value');
      expect(await fallback.read('key'), isNull);
    });

    test(
      'falls back permanently after the primary throws, and reports it',
      () async {
        final fallback = InMemorySecureStorage();
        final primary = InMemorySecureStorage();
        Object? reportedError;
        final storage = ResilientSecureStorage(
          primary: _OnceFailingSecureStorage(primary),
          fallback: fallback,
          onFallback: (error) => reportedError = error,
        );

        await storage.write('key', 'value');
        expect(await fallback.read('key'), 'value');
        expect(reportedError, isA<StateError>());

        // Primary would now succeed (it only fails its first call), but the
        // fallback decision is permanent for this instance -- a second write
        // must still land in fallback, not primary.
        await storage.write('other', 'value2');
        expect(await fallback.read('other'), 'value2');
        expect(await primary.read('other'), isNull);
      },
    );
  });
}

/// Delegates to [delegate], but throws once on the first call and never
/// again -- used to prove a caller's fallback decision, once made, is not
/// re-evaluated even after the primary would start succeeding again.
class _OnceFailingSecureStorage implements SecureStorage {
  _OnceFailingSecureStorage(this.delegate);

  final SecureStorage delegate;
  bool _hasFailed = false;

  @override
  Future<String?> read(String key) => delegate.read(key);

  @override
  Future<void> write(String key, String value) async {
    if (!_hasFailed) {
      _hasFailed = true;
      throw StateError('storage unavailable');
    }
    await delegate.write(key, value);
  }

  @override
  Future<void> delete(String key) => delegate.delete(key);
}

class _FailingSecureStorage implements SecureStorage {
  @override
  Future<void> delete(String key) async {}

  @override
  Future<String?> read(String key) async => null;

  @override
  Future<void> write(String key, String value) async {
    throw StateError('storage unavailable');
  }
}

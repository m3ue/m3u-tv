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

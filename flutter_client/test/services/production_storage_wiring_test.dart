import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/persistent_store.dart';
import 'package:m3u_tv/services/production_storage.dart';
import 'package:m3u_tv/services/secure_storage.dart';

void main() {
  for (final operatingSystem in <String>[
    'android',
    'ios',
    'tvos',
    'linux',
    'windows',
  ]) {
    test('$operatingSystem startup injects secure credential storage', () {
      final store = PersistentJsonStore();

      final storage = createProductionStorage(
        operatingSystem: operatingSystem,
        persistentStore: store,
      );

      expect(storage.credentialStorage, isA<FlutterSecureStorageAdapter>());
      expect(storage.appStateStore, same(store));
    });
  }

  test('desktop startup migrates Linux and Windows credentials', () {
    expect(shouldMigrateLegacyCredentials('linux'), isTrue);
    expect(shouldMigrateLegacyCredentials('windows'), isTrue);
    expect(shouldMigrateLegacyCredentials('android'), isFalse);
  });

  test('desktop builds bundle secure storage and Linux installs libsecret', () {
    final linuxPlugins = File(
      'linux/flutter/generated_plugins.cmake',
    ).readAsStringSync();
    final windowsPlugins = File(
      'windows/flutter/generated_plugins.cmake',
    ).readAsStringSync();
    final releaseWorkflow = File(
      '../.github/workflows/release.yml',
    ).readAsStringSync();

    expect(linuxPlugins, contains('flutter_secure_storage_linux'));
    expect(windowsPlugins, contains('flutter_secure_storage_windows'));
    expect(releaseWorkflow, contains('libsecret-1-dev'));
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/introdb_settings.dart';
import 'package:m3u_tv/services/persistent_store.dart';

void main() {
  group('IntroDbSettings', () {
    test('defaults to enabled with no persisted store', () {
      final settings = IntroDbSettings();

      expect(settings.enabled, isTrue);
    });

    test('load() with no persisted value keeps the default enabled', () async {
      final dir = await Directory.systemTemp.createTemp('introdb_settings');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/store.json');

      final settings = IntroDbSettings(
        store: PersistentJsonStore(file: file),
      );
      await settings.load();

      expect(settings.enabled, isTrue);
    });

    test(
      'round-trips a disabled preference through the persistent store',
      () async {
        final dir = await Directory.systemTemp.createTemp('introdb_settings');
        addTearDown(() => dir.delete(recursive: true));
        final file = File('${dir.path}/store.json');

        final store = PersistentJsonStore(file: file);
        final settings = IntroDbSettings(store: store);
        await settings.setEnabled(enabled: false);

        final restored = IntroDbSettings(
          store: PersistentJsonStore(file: file),
        );
        await restored.load();

        expect(restored.enabled, isFalse);
      },
    );

    test(
      'round-trips a re-enabled preference through the persistent store',
      () async {
        final dir = await Directory.systemTemp.createTemp('introdb_settings');
        addTearDown(() => dir.delete(recursive: true));
        final file = File('${dir.path}/store.json');

        final store = PersistentJsonStore(file: file);
        final settings = IntroDbSettings(store: store);
        await settings.setEnabled(enabled: false);
        await settings.setEnabled(enabled: true);

        final restored = IntroDbSettings(
          store: PersistentJsonStore(file: file),
        );
        await restored.load();

        expect(restored.enabled, isTrue);
      },
    );
  });
}

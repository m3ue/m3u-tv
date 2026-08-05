import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/comskip_settings.dart';
import 'package:m3u_tv/services/persistent_store.dart';

void main() {
  group('ComskipSettings', () {
    test('defaults auto-skip to enabled with no persisted store', () {
      final settings = ComskipSettings();

      expect(settings.autoSkipEnabled, isTrue);
    });

    test('load() with no persisted value keeps the default enabled', () async {
      final dir = await Directory.systemTemp.createTemp('comskip_settings');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/store.json');

      final settings = ComskipSettings(
        store: PersistentJsonStore(file: file),
      );
      await settings.load();

      expect(settings.autoSkipEnabled, isTrue);
    });

    test(
      'round-trips a disabled preference through the persistent store',
      () async {
        final dir = await Directory.systemTemp.createTemp('comskip_settings');
        addTearDown(() => dir.delete(recursive: true));
        final file = File('${dir.path}/store.json');

        final store = PersistentJsonStore(file: file);
        final settings = ComskipSettings(store: store);
        await settings.setAutoSkipEnabled(enabled: false);

        final restored = ComskipSettings(
          store: PersistentJsonStore(file: file),
        );
        await restored.load();

        expect(restored.autoSkipEnabled, isFalse);
      },
    );

    test(
      'round-trips a re-enabled preference through the persistent store',
      () async {
        final dir = await Directory.systemTemp.createTemp('comskip_settings');
        addTearDown(() => dir.delete(recursive: true));
        final file = File('${dir.path}/store.json');

        final store = PersistentJsonStore(file: file);
        final settings = ComskipSettings(store: store);
        await settings.setAutoSkipEnabled(enabled: false);
        await settings.setAutoSkipEnabled(enabled: true);

        final restored = ComskipSettings(
          store: PersistentJsonStore(file: file),
        );
        await restored.load();

        expect(restored.autoSkipEnabled, isTrue);
      },
    );
  });
}

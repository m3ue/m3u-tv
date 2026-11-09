import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/client_config.dart';
import 'package:m3u_tv/services/persistent_store.dart';
import 'package:m3u_tv/services/view_settings_service.dart';

ClientConfig _config(
  Map<String, Map<String, Object?>> settings, {
  String revision = 'rev-1',
  String? profile = 'Kids',
}) => ClientConfig.fromJson({
  'revision': revision,
  'profile': profile,
  'settings': settings,
});

void main() {
  group('ClientConfigCapability', () {
    test('reads a v1 block', () {
      final capability = ClientConfigCapability.tryFromJson({
        'api_version': 1,
        'revision': 'abc',
        'action': 'get_client_config',
      });
      expect(capability?.revision, 'abc');
      expect(capability?.action, 'get_client_config');
    });

    test('ignores newer API versions and blocks without a revision', () {
      expect(
        ClientConfigCapability.tryFromJson({'api_version': 2, 'revision': 'a'}),
        isNull,
      );
      expect(ClientConfigCapability.tryFromJson({'api_version': 1}), isNull);
    });
  });

  group('ClientConfig', () {
    test('keeps only default and enforced entries with a value', () {
      final config = _config({
        'deinterlace': {'mode': 'enforced', 'value': true},
        'prebuffer_live': {'mode': 'default', 'value': false},
        'live_tv_layout': {'mode': 'sometimes', 'value': 'grid'},
        'epg_start_view': {'mode': 'default', 'value': null},
      });

      expect(config.settings.keys, ['deinterlace', 'prebuffer_live']);
      expect(config.settings['deinterlace']?.enforced, isTrue);
      expect(config.settings['prebuffer_live']?.enforced, isFalse);
    });

    test('round-trips through JSON', () {
      final config = _config({
        'vod_player': {'mode': 'enforced', 'value': 'mpv'},
      });
      final restored = ClientConfig.fromJson(config.toJson());

      expect(restored.revision, config.revision);
      expect(restored.profileName, 'Kids');
      expect(restored.settings, config.settings);
    });
  });

  group('ViewSettingsService managed settings', () {
    late ViewSettingsService service;

    setUp(() => service = ViewSettingsService());

    test('a server default only fills in for an unset setting', () async {
      await service.applyClientConfig(
        _config({
          'live_tv_layout': {'mode': 'default', 'value': 'grid'},
          'prebuffer_live': {'mode': 'default', 'value': true},
        }),
      );

      expect(await service.liveTvLayout(), LiveTvLayout.grid);
      expect(service.prebufferLiveSync, isTrue);
      expect(service.isEnforced(ViewSettingsService.liveTvLayoutKey), isFalse);

      await service.setLiveTvLayout(LiveTvLayout.timeline);
      expect(await service.liveTvLayout(), LiveTvLayout.timeline);
    });

    test("an enforced value wins over the user's choice", () async {
      await service.setDeinterlace(false);
      await service.setDefaultStartPage(DefaultStartPage.search);
      await service.applyClientConfig(
        _config({
          'deinterlace': {'mode': 'enforced', 'value': true},
          'default_start_page': {'mode': 'enforced', 'value': 'movies'},
        }),
      );

      expect(service.deinterlaceSync, isTrue);
      expect(await service.defaultStartPage(), DefaultStartPage.movies);
      expect(service.isEnforced(ViewSettingsService.deinterlaceKey), isTrue);
      expect(service.managedProfileName, 'Kids');

      await service.applyClientConfig(null);
      expect(service.deinterlaceSync, isFalse);
      expect(await service.defaultStartPage(), DefaultStartPage.search);
      expect(service.managedProfileName, isNull);
    });

    test(
      'ignores unknown keys and values this version does not know',
      () async {
        await service.applyClientConfig(
          _config({
            'some_future_setting': {'mode': 'enforced', 'value': true},
            'home_screen_style': {'mode': 'enforced', 'value': 'holographic'},
            'deinterlace': {'mode': 'enforced', 'value': 'yes'},
            'epg_preview_delay_seconds': {'mode': 'enforced', 'value': 7},
          }),
        );

        expect(await service.homeScreenStyle(), HomeScreenStyle.rich);
        expect(service.deinterlaceSync, isFalse);
        expect(
          await service.epgPreviewDelay(),
          const Duration(
            seconds: ViewSettingsService.defaultEpgPreviewDelaySeconds,
          ),
        );
        expect(service.managedProfileName, isNull);
      },
    );

    test('notifies only when the managed settings change', () async {
      var notifications = 0;
      service.addListener(() => notifications += 1);
      final config = _config({
        'deinterlace': {'mode': 'enforced', 'value': true},
      });

      await service.applyClientConfig(config);
      await service.applyClientConfig(config);
      expect(notifications, 1);

      await service.applyClientConfig(null);
      expect(notifications, 2);
    });

    test('survives a restart through the store', () async {
      final dir = await Directory.systemTemp.createTemp('client-config-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/s.json');

      await ViewSettingsService(
        store: PersistentJsonStore(file: file),
      ).applyClientConfig(
        _config({
          'default_start_page': {'mode': 'enforced', 'value': 'liveTv'},
        }),
      );

      final restored = ViewSettingsService(
        store: PersistentJsonStore(file: file),
      );
      await restored.loadManagedSettings();

      expect(await restored.defaultStartPage(), DefaultStartPage.liveTv);
      expect(
        restored.isEnforced(ViewSettingsService.defaultStartPageKey),
        isTrue,
      );
    });
  });

  group('ClientConfigStore', () {
    test("keeps each playlist's config apart", () async {
      final dir = await Directory.systemTemp.createTemp('client-config-store-');
      addTearDown(() => dir.delete(recursive: true));
      final store = ClientConfigStore(
        store: PersistentJsonStore(file: File('${dir.path}/s.json')),
      );

      await store.writeFor(null, _config(const {}, revision: 'first'));
      await store.writeFor('2', _config(const {}, revision: 'second'));

      expect((await store.readFor(null))?.revision, 'first');
      expect((await store.readFor('2'))?.revision, 'second');

      await store.clearPlaylistState('2');
      expect(await store.readFor('2'), isNull);
      expect((await store.readFor(null))?.revision, 'first');
    });
  });
}

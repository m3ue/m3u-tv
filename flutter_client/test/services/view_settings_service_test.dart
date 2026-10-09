import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/navigation/route_names.dart';
import 'package:m3u_tv/services/persistent_store.dart';
import 'package:m3u_tv/services/view_settings_service.dart';

void main() {
  group('ViewSettingsService', () {
    late Map<String, Object?> memory;
    late ViewSettingsService service;

    setUp(() {
      memory = <String, Object?>{};
      service = ViewSettingsService(memory: memory);
    });

    test('default values when no persisted settings exist', () async {
      expect(await service.liveTvLayout(), LiveTvLayout.list);
      expect(await service.epgStartView(), EpgStartView.currentTime);
      expect(await service.rememberMediaSort(), isFalse);
      expect(await service.vodSortOption(), MediaSortOption.defaultOrder);
      expect(await service.seriesSortOption(), MediaSortOption.defaultOrder);
      expect(await service.defaultStartPage(), DefaultStartPage.home);
    });

    test('persists and restores the default start page', () async {
      for (final page in DefaultStartPage.values) {
        await service.setDefaultStartPage(page);
        expect(await service.defaultStartPage(), page);
        expect(service.defaultStartPageSync, page);
      }
    });

    test('start page enum maps to the matching router location', () {
      expect(DefaultStartPage.home.route, RouteNames.home);
      expect(DefaultStartPage.search.route, RouteNames.search);
      expect(DefaultStartPage.liveTv.route, RouteNames.liveTv);
      expect(DefaultStartPage.movies.route, RouteNames.vod);
      expect(DefaultStartPage.series.route, RouteNames.series);
    });

    test(
      'ignores unknown persisted start page and falls back to Home',
      () async {
        memory[ViewSettingsService.defaultStartPageKey] = 'dashboard';
        expect(await service.defaultStartPage(), DefaultStartPage.home);
      },
    );

    test('persists and restores live TV layout', () async {
      for (final layout in LiveTvLayout.values) {
        await service.setLiveTvLayout(layout);
        expect(await service.liveTvLayout(), layout);
      }
    });

    test('persists and restores EPG preview playback and delay', () async {
      expect(await service.epgPreviewPlayback(), EpgPreviewPlayback.off);
      expect(await service.epgPreviewDelay(), const Duration(seconds: 5));
      for (final mode in EpgPreviewPlayback.values) {
        await service.setEpgPreviewPlayback(mode);
        expect(await service.epgPreviewPlayback(), mode);
      }
      await service.setEpgPreviewDelay(const Duration(seconds: 8));
      expect(await service.epgPreviewDelay(), const Duration(seconds: 8));
    });

    test('persists and restores EPG start view', () async {
      for (final view in EpgStartView.values) {
        await service.setEpgStartView(view);
        expect(await service.epgStartView(), view);
      }
    });

    test(
      'persists and restores rememberMediaSort with bool semantics',
      () async {
        // Defaults to false (conservative; not the always-true hdrEnabled
        // default - preserves today's "reset each launch" behavior).
        expect(await service.rememberMediaSort(), isFalse);
        await service.setRememberMediaSort(true);
        expect(await service.rememberMediaSort(), isTrue);
        await service.setRememberMediaSort(false);
        expect(await service.rememberMediaSort(), isFalse);
      },
    );

    test(
      'favorites-first defaults on and persists independently per screen',
      () async {
        expect(await service.vodFavoritesFirst(), isTrue);
        expect(await service.seriesFavoritesFirst(), isTrue);
        expect(await service.liveTvFavoritesFirst(), isTrue);

        await service.setVodFavoritesFirst(false);
        expect(await service.vodFavoritesFirst(), isFalse);
        expect(await service.seriesFavoritesFirst(), isTrue);
        expect(await service.liveTvFavoritesFirst(), isTrue);

        await service.setLiveTvFavoritesFirst(false);
        final recreated = ViewSettingsService(memory: memory);
        expect(await recreated.vodFavoritesFirst(), isFalse);
        expect(await recreated.seriesFavoritesFirst(), isTrue);
        expect(await recreated.liveTvFavoritesFirst(), isFalse);
      },
    );

    test('favorites-first sync getters default on before any load', () {
      expect(service.vodFavoritesFirstSync, isTrue);
      expect(service.seriesFavoritesFirstSync, isTrue);
      expect(service.liveTvFavoritesFirstSync, isTrue);
    });

    test('persists and restores VOD sort option', () async {
      for (final option in MediaSortOption.values) {
        await service.setVodSortOption(option);
        expect(await service.vodSortOption(), option);
      }
    });

    test(
      'persists and restores Series sort option independently of VOD',
      () async {
        for (final option in MediaSortOption.values) {
          await service.setSeriesSortOption(option);
          expect(await service.seriesSortOption(), option);
        }
        await service.setVodSortOption(MediaSortOption.ratingDesc);
        await service.setSeriesSortOption(MediaSortOption.defaultOrder);
        expect(await service.vodSortOption(), MediaSortOption.ratingDesc);
        expect(await service.seriesSortOption(), MediaSortOption.defaultOrder);
      },
    );

    test(
      'sort option survives with rememberMediaSort=false (still persisted, ignored at read time)',
      () async {
        // Stored independently - toggling rememberMediaSort off doesn't
        // clear the sort key; the screen just refuses to read it.
        await service.setVodSortOption(MediaSortOption.ratingDesc);
        expect(await service.rememberMediaSort(), isFalse);
        expect(await service.vodSortOption(), MediaSortOption.ratingDesc);
      },
    );

    test(
      'deinterlace defaults off and persists, sync getter included',
      () async {
        expect(service.deinterlaceSync, isFalse);
        expect(await service.deinterlace(), isFalse);

        await service.setDeinterlace(true);
        expect(await service.deinterlace(), isTrue);
        expect(service.deinterlaceSync, isTrue);

        final recreated = ViewSettingsService(memory: memory);
        expect(recreated.deinterlaceSync, isTrue);
        expect(await recreated.deinterlace(), isTrue);
      },
    );

    test('values survive service recreation with same store', () async {
      await service.setLiveTvLayout(LiveTvLayout.grid);
      await service.setEpgStartView(EpgStartView.primeTime);
      await service.setRememberMediaSort(true);
      await service.setVodSortOption(MediaSortOption.ratingDesc);

      final recreated = ViewSettingsService(memory: memory);
      expect(await recreated.liveTvLayout(), LiveTvLayout.grid);
      expect(await recreated.epgStartView(), EpgStartView.primeTime);
      expect(await recreated.rememberMediaSort(), isTrue);
      expect(await recreated.vodSortOption(), MediaSortOption.ratingDesc);
    });

    test(
      'ignores unknown persisted layout and falls back to default',
      () async {
        memory[ViewSettingsService.liveTvLayoutKey] = 'unknown_layout';
        expect(await service.liveTvLayout(), LiveTvLayout.list);
      },
    );

    test(
      'ignores unknown persisted EPG view and falls back to default',
      () async {
        memory[ViewSettingsService.epgStartViewKey] = 'unknown_view';
        expect(await service.epgStartView(), EpgStartView.currentTime);
      },
    );
    test(
      'persists and restores navigationSoundEnabled, defaulting to true',
      () async {
        expect(await service.navigationSoundEnabled(), isTrue);
        expect(service.navigationSoundEnabledSync, isTrue);
        await service.setNavigationSoundEnabled(false);
        expect(await service.navigationSoundEnabled(), isFalse);
        expect(service.navigationSoundEnabledSync, isFalse);
        await service.setNavigationSoundEnabled(true);
        expect(await service.navigationSoundEnabled(), isTrue);
      },
    );

    test(
      'persists and restores volume, defaulting to full volume',
      () async {
        expect(await service.volume(), 1.0);
        expect(service.volumeSync, 1.0);
        await service.setVolume(0.4);
        expect(await service.volume(), 0.4);
        expect(service.volumeSync, 0.4);
      },
    );

    test('clamps volume to the 0.0-1.0 range', () async {
      await service.setVolume(1.5);
      expect(await service.volume(), 1.0);
      await service.setVolume(-0.5);
      expect(await service.volume(), 0.0);
    });

    test('synchronous getters reflect in-memory cache', () async {
      await service.setLiveTvLayout(LiveTvLayout.timeline);
      await service.setEpgStartView(EpgStartView.primeTime);
      expect(service.liveTvLayoutSync, LiveTvLayout.timeline);
      expect(service.epgStartViewSync, EpgStartView.primeTime);
    });

    test('new sync getters reflect loaded values', () async {
      await service.setLiveTvLayout(LiveTvLayout.timeline);
      await service.setEpgStartView(EpgStartView.primeTime);
      await service.setRememberMediaSort(true);
      await service.setVodSortOption(MediaSortOption.ratingDesc);
      await service.setSeriesSortOption(MediaSortOption.ratingDesc);

      expect(service.rememberMediaSortSync, isTrue);
      expect(service.vodSortOptionSync, MediaSortOption.ratingDesc);
      expect(service.seriesSortOptionSync, MediaSortOption.ratingDesc);
    });

    test(
      'ignores unknown persisted VOD sort and falls back to default',
      () async {
        memory[ViewSettingsService.vodSortOptionKey] = 'unknown_sort';
        expect(await service.vodSortOption(), MediaSortOption.defaultOrder);
      },
    );

    test(
      'ignores unknown persisted Series sort and falls back to default',
      () async {
        memory[ViewSettingsService.seriesSortOptionKey] = 'unknown_sort';
        expect(await service.seriesSortOption(), MediaSortOption.defaultOrder);
      },
    );

    test(
      'sync getters reflect values loaded from disk via the async getters',
      () async {
        final dir = await Directory.systemTemp.createTemp(
          'view_settings_service',
        );
        addTearDown(() => dir.delete(recursive: true));
        final file = File('${dir.path}/view_settings.json');

        final writer = ViewSettingsService(
          store: PersistentJsonStore(file: file),
        );
        await writer.setLiveTvLayout(LiveTvLayout.grid);
        await writer.setEpgStartView(EpgStartView.primeTime);

        final reader = ViewSettingsService(
          store: PersistentJsonStore(file: file),
        );
        expect(await reader.liveTvLayout(), LiveTvLayout.grid);
        expect(await reader.epgStartView(), EpgStartView.primeTime);

        expect(reader.liveTvLayoutSync, LiveTvLayout.grid);
        expect(reader.epgStartViewSync, EpgStartView.primeTime);
      },
    );

    test(
      'window bounds default to null before anything is persisted',
      () async {
        expect(await service.windowBounds(), isNull);
      },
    );

    test('persists and restores window bounds', () async {
      await service.setWindowBounds(
        const WindowBounds(
          x: 120,
          y: 64,
          width: 1280,
          height: 800,
          maximized: false,
        ),
      );

      final restored = await ViewSettingsService(memory: memory).windowBounds();
      expect(restored, isNotNull);
      expect(restored!.x, 120);
      expect(restored.y, 64);
      expect(restored.width, 1280);
      expect(restored.height, 800);
      expect(restored.maximized, isFalse);
    });

    test('rejects degenerate or absurd saved window sizes', () {
      expect(
        WindowBounds.fromJson({
          'x': 0,
          'y': 0,
          'width': 40,
          'height': 30,
          'maximized': false,
        }),
        isNull,
      );
      expect(
        WindowBounds.fromJson({'x': 0, 'y': 0, 'width': 1024}),
        isNull,
      );
      expect(WindowBounds.fromJson('not a map'), isNull);
    });
  });
}

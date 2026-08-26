import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
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
      expect(await service.rememberVodSort(), isFalse);
      expect(await service.vodSortOption(), VodSortOption.defaultOrder);
    });

    test('persists and restores live TV layout', () async {
      for (final layout in LiveTvLayout.values) {
        await service.setLiveTvLayout(layout);
        expect(await service.liveTvLayout(), layout);
      }
    });

    test('persists and restores EPG start view', () async {
      for (final view in EpgStartView.values) {
        await service.setEpgStartView(view);
        expect(await service.epgStartView(), view);
      }
    });

    test('persists and restores rememberVodSort with bool semantics', () async {
      // Defaults to false (conservative; not the always-true hdrEnabled
      // default — preserves today's "reset each launch" behavior).
      expect(await service.rememberVodSort(), isFalse);
      await service.setRememberVodSort(true);
      expect(await service.rememberVodSort(), isTrue);
      await service.setRememberVodSort(false);
      expect(await service.rememberVodSort(), isFalse);
    });

    test('persists and restores VOD sort option', () async {
      for (final option in VodSortOption.values) {
        await service.setVodSortOption(option);
        expect(await service.vodSortOption(), option);
      }
    });

    test(
      'sort option survives with rememberVodSort=false (still persisted, ignored at read time)',
      () async {
        // Stored independently — toggling rememberVodSort off doesn't
        // clear the sort key; the screen just refuses to read it.
        await service.setVodSortOption(VodSortOption.ratingDesc);
        expect(await service.rememberVodSort(), isFalse);
        expect(await service.vodSortOption(), VodSortOption.ratingDesc);
      },
    );

    test('values survive service recreation with same store', () async {
      await service.setLiveTvLayout(LiveTvLayout.grid);
      await service.setEpgStartView(EpgStartView.primeTime);
      await service.setRememberVodSort(true);
      await service.setVodSortOption(VodSortOption.ratingDesc);

      final recreated = ViewSettingsService(memory: memory);
      expect(await recreated.liveTvLayout(), LiveTvLayout.grid);
      expect(await recreated.epgStartView(), EpgStartView.primeTime);
      expect(await recreated.rememberVodSort(), isTrue);
      expect(await recreated.vodSortOption(), VodSortOption.ratingDesc);
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
    test('synchronous getters reflect in-memory cache', () async {
      await service.setLiveTvLayout(LiveTvLayout.timeline);
      await service.setEpgStartView(EpgStartView.primeTime);
      expect(service.liveTvLayoutSync, LiveTvLayout.timeline);
      expect(service.epgStartViewSync, EpgStartView.primeTime);
    });

    test('new sync getters reflect loaded values', () async {
      await service.setLiveTvLayout(LiveTvLayout.timeline);
      await service.setEpgStartView(EpgStartView.primeTime);
      await service.setRememberVodSort(true);
      await service.setVodSortOption(VodSortOption.ratingDesc);

      expect(service.rememberVodSortSync, isTrue);
      expect(service.vodSortOptionSync, VodSortOption.ratingDesc);
    });

    test(
      'ignores unknown persisted VOD sort and falls back to default',
      () async {
        memory[ViewSettingsService.vodSortOptionKey] = 'unknown_sort';
        expect(await service.vodSortOption(), VodSortOption.defaultOrder);
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
  });
}

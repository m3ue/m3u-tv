import 'package:flutter_test/flutter_test.dart';
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

    test('values survive service recreation with same store', () async {
      await service.setLiveTvLayout(LiveTvLayout.grid);
      await service.setEpgStartView(EpgStartView.primeTime);

      final recreated = ViewSettingsService(memory: memory);
      expect(await recreated.liveTvLayout(), LiveTvLayout.grid);
      expect(await recreated.epgStartView(), EpgStartView.primeTime);
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
  });
}

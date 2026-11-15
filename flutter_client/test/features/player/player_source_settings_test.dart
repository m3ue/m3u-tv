import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/player/player_source_settings.dart';
import 'package:m3u_tv/playback/player_adapter.dart';
import 'package:m3u_tv/services/view_settings_service.dart';

void main() {
  const vod = PlaybackSource(uri: 'https://example.test/movie.mkv');
  const catchup = PlaybackSource(
    uri: 'https://example.test/catchup.ts',
    isCatchup: true,
  );
  const live = PlaybackSource(
    uri: 'https://example.test/live.ts',
    isLive: true,
  );

  group('preferMpv', () {
    test('stays off by default', () {
      expect(
        applyPlayerSourceSettings(vod, ViewSettingsService()).preferMpv,
        isFalse,
      );
      expect(applyPlayerSourceSettings(vod, null).preferMpv, isFalse);
    });

    test('applies to non-live content but never to live', () async {
      final settings = ViewSettingsService();
      await settings.setVodPlayer(VodPlayerPreference.mpv);

      expect(applyPlayerSourceSettings(vod, settings).preferMpv, isTrue);
      expect(applyPlayerSourceSettings(catchup, settings).preferMpv, isTrue);
      expect(applyPlayerSourceSettings(live, settings).preferMpv, isFalse);
    });
  });
}

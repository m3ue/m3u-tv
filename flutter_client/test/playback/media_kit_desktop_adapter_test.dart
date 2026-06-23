import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/playback/media_kit_desktop_adapter.dart';
import 'package:m3u_tv/playback/player_adapter.dart';
import 'package:media_kit/media_kit.dart' as mk;

void main() {
  group('MediaKitDesktopAdapter track mapping', () {
    test('maps real media_kit audio tracks and hides auto/no sentinels', () {
      final tracks = mediaKitAudioTracksToPlaybackTracks(const <mk.AudioTrack>[
        mk.AudioTrack('auto', null, null),
        mk.AudioTrack('no', null, null),
        mk.AudioTrack('1', 'English', 'eng'),
        mk.AudioTrack('2', null, 'jpn'),
      ]);

      expect(tracks, hasLength(2));
      expect(
        tracks.first,
        isA<PlaybackTrack>()
            .having((track) => track.id, 'id', '1')
            .having((track) => track.label, 'label', 'English')
            .having((track) => track.language, 'language', 'eng'),
      );
      expect(tracks.last.id, '2');
      expect(tracks.last.label, 'jpn');
    });

    test('maps real media_kit subtitle tracks and hides auto/no sentinels', () {
      final tracks = mediaKitSubtitleTracksToPlaybackTracks(
        const <mk.SubtitleTrack>[
          mk.SubtitleTrack('auto', null, null),
          mk.SubtitleTrack('no', null, null),
          mk.SubtitleTrack('3', 'English CC', 'eng'),
          mk.SubtitleTrack('4', null, null),
        ],
      );

      expect(tracks, hasLength(2));
      expect(tracks.first.id, '3');
      expect(tracks.first.label, 'English CC');
      expect(tracks.last.id, '4');
      expect(tracks.last.label, 'Track 4');
    });

    test('resolves automatic audio selection to the first real track', () {
      final selectedTrackId = selectedMediaKitAudioTrackId(
        mk.AudioTrack.auto(),
        const <mk.AudioTrack>[
          mk.AudioTrack('auto', null, null),
          mk.AudioTrack('no', null, null),
          mk.AudioTrack('1', null, 'de'),
          mk.AudioTrack('2', null, 'en'),
        ],
      );

      expect(selectedTrackId, '1');
    });

    test('keeps disabled audio selection disabled', () {
      final selectedTrackId = selectedMediaKitAudioTrackId(
        mk.AudioTrack.no(),
        const <mk.AudioTrack>[
          mk.AudioTrack('auto', null, null),
          mk.AudioTrack('no', null, null),
          mk.AudioTrack('1', null, 'de'),
        ],
      );

      expect(selectedTrackId, isNull);
    });
  });
}

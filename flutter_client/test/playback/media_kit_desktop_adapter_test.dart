import 'dart:io';

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

    test('resolves automatic subtitle selection to the first real track', () {
      final selection = selectedMediaKitSubtitleTrack(
        mk.SubtitleTrack.auto(),
        const <mk.SubtitleTrack>[
          mk.SubtitleTrack('auto', null, null),
          mk.SubtitleTrack('no', null, null),
          mk.SubtitleTrack('3', null, 'de'),
          mk.SubtitleTrack('4', null, 'en'),
        ],
      );

      expect(selection.selectedTrackId, '3');
      expect(selection.isKnown, isTrue);
    });

    test('keeps disabled subtitle selection confirmed disabled', () {
      final selection = selectedMediaKitSubtitleTrack(
        mk.SubtitleTrack.no(),
        const <mk.SubtitleTrack>[
          mk.SubtitleTrack('auto', null, null),
          mk.SubtitleTrack('no', null, null),
          mk.SubtitleTrack('3', null, 'de'),
        ],
      );

      expect(selection.selectedTrackId, isNull);
      expect(selection.isKnown, isTrue);
    });

    test('keeps a real subtitle selection unchanged and known', () {
      final selection = selectedMediaKitSubtitleTrack(
        const mk.SubtitleTrack('4', null, 'en'),
        const <mk.SubtitleTrack>[
          mk.SubtitleTrack('auto', null, null),
          mk.SubtitleTrack('no', null, null),
          mk.SubtitleTrack('3', null, 'de'),
          mk.SubtitleTrack('4', null, 'en'),
        ],
      );

      expect(selection.selectedTrackId, '4');
      expect(selection.isKnown, isTrue);
    });

    test('keeps automatic subtitle selection unknown without a real track', () {
      final selection = selectedMediaKitSubtitleTrack(
        mk.SubtitleTrack.auto(),
        const <mk.SubtitleTrack>[
          mk.SubtitleTrack('auto', null, null),
          mk.SubtitleTrack('no', null, null),
        ],
      );

      expect(selection.selectedTrackId, isNull);
      expect(selection.isKnown, isFalse);
    });

    test('both MediaKit track streams use subtitle selection semantics', () {
      for (final path in <String>[
        'lib/playback/media_kit_desktop_adapter.dart',
        'lib/playback/media_kit_ios_adapter.dart',
      ]) {
        final source = File(path).readAsStringSync();
        final handlerStart = source.indexOf('_player.stream.track.listen');
        final handlerEnd = source.indexOf(
          '_player.stream.completed.listen',
          handlerStart,
        );
        final handler = source.substring(handlerStart, handlerEnd);

        expect(handler, contains('selectedMediaKitSubtitleTrack('));
        expect(
          handler,
          contains(
            'isSubtitleTrackSelectionKnown: subtitleSelection.isKnown',
          ),
        );
      }
    });

    test('passes playback source start position to media_kit media', () {
      final media = mediaKitMediaFromPlaybackSource(
        const PlaybackSource(
          uri: 'https://example.com/movie.mkv',
          title: 'Resume Fixture',
          startPosition: Duration(minutes: 43, seconds: 13),
          headers: <String, String>{'User-Agent': 'm3u-tv'},
        ),
      );

      expect(media.uri, 'https://example.com/movie.mkv');
      expect(media.start, const Duration(minutes: 43, seconds: 13));
      expect(media.httpHeaders, <String, String>{'User-Agent': 'm3u-tv'});
    });

    test('maps video params aspect ratio with display size fallback', () {
      expect(
        mediaKitVideoAspectRatio(
          const mk.VideoParams(aspect: 4 / 3, w: 720, h: 576),
        ),
        closeTo(4 / 3, 0.0001),
      );
      expect(
        mediaKitVideoAspectRatio(const mk.VideoParams(dw: 1024, dh: 576)),
        closeTo(16 / 9, 0.0001),
      );
      expect(
        mediaKitVideoAspectRatio(const mk.VideoParams(w: 720, h: 576)),
        closeTo(1.25, 0.0001),
      );
      expect(mediaKitVideoAspectRatio(const mk.VideoParams()), isNull);
    });
  });
}

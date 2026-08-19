import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/player/epg_overlay.dart';
import 'package:m3u_tv/features/player/format_time.dart';
import 'package:m3u_tv/features/player/now_playing_overlay.dart';
import 'package:m3u_tv/features/player/playback_controls.dart';
import 'package:m3u_tv/features/player/player_screen.dart';
import 'package:m3u_tv/features/player/resume_prompt.dart';
import 'package:m3u_tv/features/player/track_selector.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/navigation/app_router.dart';
import 'package:m3u_tv/playback/playback_capabilities.dart';
import 'package:m3u_tv/playback/playback_orchestrator.dart';
import 'package:m3u_tv/playback/player_adapter.dart';
import 'package:m3u_tv/services/comskip_settings.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/epg_service.dart';
import 'package:m3u_tv/services/xtream_service.dart';

import 'fake_player_adapter.dart';
import 'fake_transcode_gateway.dart';

/// Minimal `HttpClient` fake for testing the comskip EDL fetch — every
/// request returns the same canned body/status, regardless of URL. Only
/// [getUrl] and [close] are implemented; anything else falls through to
/// [noSuchMethod], which is fine since `_initComskip` never touches it.
class _FakeHttpClient implements HttpClient {
  _FakeHttpClient(this._body);

  final String _body;
  final List<Uri> requestedUrls = <Uri>[];

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    requestedUrls.add(url);
    return _FakeHttpClientRequest(_body, HttpStatus.ok);
  }

  @override
  void close({bool force = false}) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpClientRequest implements HttpClientRequest {
  _FakeHttpClientRequest(this._body, this._statusCode);

  final String _body;
  final int _statusCode;

  @override
  Future<HttpClientResponse> close() async =>
      _FakeHttpClientResponse(_body, _statusCode);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpClientResponse extends Stream<List<int>>
    implements HttpClientResponse {
  _FakeHttpClientResponse(String body, this.statusCode)
    : _stream = Stream.value(utf8.encode(body));

  final Stream<List<int>> _stream;

  @override
  final int statusCode;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _stream.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('formatTime', () {
    test('formats seconds as M:SS', () {
      expect(formatTime(Duration.zero), '0:00');
      expect(formatTime(const Duration(seconds: 5)), '0:05');
      expect(formatTime(const Duration(minutes: 5, seconds: 30)), '5:30');
    });

    test('formats hours as H:MM:SS', () {
      expect(formatTime(const Duration(hours: 1, minutes: 30)), '1:30:00');
      expect(
        formatTime(const Duration(hours: 2, minutes: 15, seconds: 45)),
        '2:15:45',
      );
    });

    test('handles zero duration', () {
      expect(formatTime(Duration.zero), '0:00');
    });
  });

  group('PlaybackControls', () {
    testWidgets('shows play button when paused', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PlaybackControls(
            isPlaying: false,
            isLive: false,
            canSeek: true,
            currentPosition: Duration.zero,
            duration: const Duration(hours: 1),
            onPlayPause: () {},
            onSeek: (_) {},
            onBack: () {},
          ),
        ),
      );
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    });

    testWidgets('shows pause button when playing', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PlaybackControls(
            isPlaying: true,
            isLive: false,
            canSeek: true,
            currentPosition: const Duration(minutes: 5),
            duration: const Duration(hours: 1),
            onPlayPause: () {},
            onSeek: (_) {},
            onBack: () {},
          ),
        ),
      );
      expect(find.byIcon(Icons.pause), findsOneWidget);
    });

    testWidgets('calls onPlayPause when play/pause button tapped', (
      tester,
    ) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: PlaybackControls(
            isPlaying: false,
            isLive: false,
            canSeek: true,
            currentPosition: Duration.zero,
            duration: const Duration(hours: 1),
            onPlayPause: () => tapped = true,
            onSeek: (_) {},
            onBack: () {},
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.play_arrow));
      expect(tapped, isTrue);
    });

    testWidgets('hides seek controls for live content', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PlaybackControls(
            isPlaying: true,
            isLive: true,
            canSeek: false,
            currentPosition: Duration.zero,
            duration: Duration.zero,
            onPlayPause: () {},
            onSeek: (_) {},
            onBack: () {},
          ),
        ),
      );
      expect(find.byIcon(Icons.replay_10), findsNothing);
      expect(find.byIcon(Icons.forward_10), findsNothing);
    });

    testWidgets('hides channel controls for live content by default', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PlaybackControls(
            isPlaying: true,
            isLive: true,
            canSeek: false,
            currentPosition: Duration.zero,
            duration: Duration.zero,
            onPlayPause: () {},
            onSeek: (_) {},
            onBack: () {},
          ),
        ),
      );
      expect(find.byIcon(Icons.skip_previous), findsNothing);
      expect(find.byIcon(Icons.skip_next), findsNothing);
    });

    testWidgets('hides channel controls for non-live content', (
      tester,
    ) async {
      var nextPressed = false;
      var previousPressed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: PlaybackControls(
            isPlaying: true,
            isLive: false,
            canSeek: true,
            currentPosition: Duration.zero,
            duration: const Duration(hours: 1),
            onPlayPause: () {},
            onSeek: (_) {},
            onBack: () {},
            onNextChannel: () => nextPressed = true,
            onPreviousChannel: () => previousPressed = true,
          ),
        ),
      );
      expect(find.byIcon(Icons.skip_previous), findsNothing);
      expect(find.byIcon(Icons.skip_next), findsNothing);
      expect(nextPressed, isFalse);
      expect(previousPressed, isFalse);
    });

    testWidgets('shows and calls next/previous channel controls for live '
        'content', (tester) async {
      var nextPressed = false;
      var previousPressed = false;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: PlaybackControls(
            isPlaying: true,
            isLive: true,
            canSeek: false,
            currentPosition: Duration.zero,
            duration: Duration.zero,
            onPlayPause: () {},
            onSeek: (_) {},
            onBack: () {},
            onNextChannel: () => nextPressed = true,
            onPreviousChannel: () => previousPressed = true,
          ),
        ),
      );
      expect(find.byIcon(Icons.skip_previous), findsOneWidget);
      expect(find.byIcon(Icons.skip_next), findsOneWidget);

      await tester.tap(find.byIcon(Icons.skip_next));
      expect(nextPressed, isTrue);

      await tester.tap(find.byIcon(Icons.skip_previous));
      expect(previousPressed, isTrue);
    });

    testWidgets(
      'exposes previous/next channel tooltips for accessibility',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: PlaybackControls(
              isPlaying: true,
              isLive: true,
              canSeek: false,
              currentPosition: Duration.zero,
              duration: Duration.zero,
              onPlayPause: () {},
              onSeek: (_) {},
              onBack: () {},
              onNextChannel: () {},
              onPreviousChannel: () {},
            ),
          ),
        );

        expect(find.bySemanticsLabel('Previous channel'), findsOneWidget);
        expect(find.bySemanticsLabel('Next channel'), findsOneWidget);
      },
    );

    testWidgets('shows seek controls for VOD content', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PlaybackControls(
            isPlaying: true,
            isLive: false,
            canSeek: true,
            currentPosition: const Duration(minutes: 5),
            duration: const Duration(hours: 1),
            onPlayPause: () {},
            onSeek: (_) {},
            onBack: () {},
          ),
        ),
      );
      expect(find.byIcon(Icons.replay_10), findsOneWidget);
      expect(find.byIcon(Icons.forward_10), findsOneWidget);
    });

    testWidgets('orders VOD seek controls around play pause', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PlaybackControls(
            isPlaying: true,
            isLive: false,
            canSeek: true,
            currentPosition: const Duration(minutes: 5),
            duration: const Duration(hours: 1),
            onPlayPause: () {},
            onSeek: (_) {},
            onBack: () {},
          ),
        ),
      );

      final replayCenter = tester.getCenter(find.byIcon(Icons.replay_10));
      final playPauseCenter = tester.getCenter(find.byIcon(Icons.pause));
      final forwardCenter = tester.getCenter(find.byIcon(Icons.forward_10));

      expect(replayCenter.dx, lessThan(playPauseCenter.dx));
      expect(playPauseCenter.dx, lessThan(forwardCenter.dx));
    });

    testWidgets('keeps transport controls stable when tracks appear later', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1200, 800));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: PlaybackControls(
            isPlaying: true,
            isLive: false,
            canSeek: true,
            currentPosition: const Duration(minutes: 5),
            duration: const Duration(hours: 1),
            onPlayPause: () {},
            onSeek: (_) {},
            onBack: () {},
          ),
        ),
      );

      final playPauseBefore = tester.getCenter(find.byIcon(Icons.pause));

      await tester.pumpWidget(
        MaterialApp(
          home: PlaybackControls(
            isPlaying: true,
            isLive: false,
            canSeek: true,
            currentPosition: const Duration(minutes: 5),
            duration: const Duration(hours: 1),
            audioTracks: const <PlaybackTrack>[
              PlaybackTrack(id: 'audio-eng', label: 'English'),
            ],
            subtitleTracks: const <PlaybackTrack>[
              PlaybackTrack(id: 'sub-eng', label: 'English CC'),
            ],
            selectedAudioTrackId: 'audio-eng',
            selectedSubtitleTrackId: 'sub-eng',
            onPlayPause: () {},
            onSeek: (_) {},
            onBack: () {},
            onAudioTrackSelected: (_) {},
            onSubtitleTrackSelected: (_) {},
          ),
        ),
      );

      final replayRect = tester.getRect(find.byIcon(Icons.replay_10));
      final pauseRect = tester.getRect(find.byIcon(Icons.pause));
      final forwardRect = tester.getRect(find.byIcon(Icons.forward_10));
      final audioRect = tester.getRect(find.byIcon(Icons.audiotrack));
      final subtitleRect = tester.getRect(find.byIcon(Icons.subtitles));

      expect(replayRect.overlaps(audioRect), isFalse);
      expect(pauseRect.overlaps(audioRect), isFalse);
      expect(forwardRect.overlaps(audioRect), isFalse);
      expect(forwardRect.overlaps(subtitleRect), isFalse);
      expect(tester.getCenter(find.byIcon(Icons.pause)), playPauseBefore);
    });

    testWidgets(
      'stacks track selectors below transport controls on narrow portrait screens',
      (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(430, 932));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          MaterialApp(
            home: PlaybackControls(
              isPlaying: true,
              isLive: false,
              canSeek: true,
              currentPosition: const Duration(seconds: 35),
              duration: const Duration(hours: 1, minutes: 48),
              audioTracks: const <PlaybackTrack>[
                PlaybackTrack(id: 'audio-eng', label: 'English'),
              ],
              subtitleTracks: const <PlaybackTrack>[
                PlaybackTrack(id: 'sub-eng', label: 'English CC'),
              ],
              selectedAudioTrackId: 'audio-eng',
              selectedSubtitleTrackId: 'sub-eng',
              onPlayPause: () {},
              onSeek: (_) {},
              onBack: () {},
              onAudioTrackSelected: (_) {},
              onSubtitleTrackSelected: (_) {},
            ),
          ),
        );

        expect(tester.takeException(), isNull);
        expect(find.text('Audio'), findsOneWidget);
        expect(find.text('Subtitles'), findsOneWidget);

        final audioRect = tester.getRect(find.byIcon(Icons.audiotrack));
        final subtitleRect = tester.getRect(find.byIcon(Icons.subtitles));
        final replayRect = tester.getRect(find.byIcon(Icons.replay_10));
        final pauseRect = tester.getRect(find.byIcon(Icons.pause));
        final forwardRect = tester.getRect(find.byIcon(Icons.forward_10));

        expect(audioRect.top, greaterThan(forwardRect.bottom));
        expect(subtitleRect.top, greaterThan(forwardRect.bottom));
        expect(replayRect.overlaps(audioRect), isFalse);
        expect(pauseRect.overlaps(audioRect), isFalse);
        expect(forwardRect.overlaps(subtitleRect), isFalse);
      },
    );

    testWidgets(
      'keeps audio and subtitle selectors visible without transport overlap in landscape',
      (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(932, 430));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          MaterialApp(
            home: PlaybackControls(
              isPlaying: true,
              isLive: false,
              canSeek: true,
              currentPosition: const Duration(seconds: 35),
              duration: const Duration(hours: 1, minutes: 48),
              audioTracks: const <PlaybackTrack>[
                PlaybackTrack(id: 'audio-eng', label: 'English'),
              ],
              subtitleTracks: const <PlaybackTrack>[
                PlaybackTrack(id: 'sub-eng', label: 'English CC'),
              ],
              selectedAudioTrackId: 'audio-eng',
              selectedSubtitleTrackId: 'sub-eng',
              onPlayPause: () {},
              onSeek: (_) {},
              onBack: () {},
              onAudioTrackSelected: (_) {},
              onSubtitleTrackSelected: (_) {},
            ),
          ),
        );

        expect(tester.takeException(), isNull);
        expect(find.text('Audio'), findsOneWidget);
        expect(find.text('Subtitles'), findsOneWidget);

        final audioRect = tester.getRect(find.byIcon(Icons.audiotrack));
        final subtitleRect = tester.getRect(find.byIcon(Icons.subtitles));
        final replayRect = tester.getRect(find.byIcon(Icons.replay_10));
        final pauseRect = tester.getRect(find.byIcon(Icons.pause));
        final forwardRect = tester.getRect(find.byIcon(Icons.forward_10));

        expect(replayRect.overlaps(audioRect), isFalse);
        expect(pauseRect.overlaps(audioRect), isFalse);
        expect(forwardRect.overlaps(audioRect), isFalse);
        expect(forwardRect.overlaps(subtitleRect), isFalse);
      },
    );

    testWidgets('labels track controls by type only', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PlaybackControls(
            isPlaying: true,
            isLive: false,
            canSeek: true,
            currentPosition: const Duration(minutes: 5),
            duration: const Duration(hours: 1),
            audioTracks: const <PlaybackTrack>[
              PlaybackTrack(id: 'audio-eng', label: 'English'),
            ],
            subtitleTracks: const <PlaybackTrack>[
              PlaybackTrack(id: 'sub-eng', label: 'English CC'),
            ],
            selectedAudioTrackId: 'audio-eng',
            selectedSubtitleTrackId: 'sub-eng',
            onPlayPause: () {},
            onSeek: (_) {},
            onBack: () {},
            onAudioTrackSelected: (_) {},
            onSubtitleTrackSelected: (_) {},
          ),
        ),
      );

      expect(find.text('Audio'), findsOneWidget);
      expect(find.text('Subtitles'), findsOneWidget);
      expect(find.text('Audio: English'), findsNothing);
      expect(find.text('Subs: English CC'), findsNothing);

      final audioButtonRect = tester.getRect(
        find.ancestor(
          of: find.text('Audio'),
          matching: find.byType(DpadFocusable),
        ),
      );
      final audioIconRect = tester.getRect(find.byIcon(Icons.audiotrack));
      final audioTextRect = tester.getRect(find.text('Audio'));
      final audioContentCenter = (audioIconRect.left + audioTextRect.right) / 2;
      expect(
        (audioContentCenter - audioButtonRect.center.dx).abs(),
        lessThan(1),
      );
    });

    testWidgets(
      'marks first audio track active while selected track is unknown',
      (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: PlaybackControls(
              isPlaying: true,
              isLive: false,
              canSeek: true,
              currentPosition: const Duration(minutes: 5),
              duration: const Duration(hours: 1),
              audioTracks: const <PlaybackTrack>[
                PlaybackTrack(id: 'audio-de', label: 'de'),
                PlaybackTrack(id: 'audio-en', label: 'en'),
              ],
              onPlayPause: () {},
              onSeek: (_) {},
              onBack: () {},
              onAudioTrackSelected: (_) {},
              onSubtitleTrackSelected: (_) {},
            ),
          ),
        );

        expect(find.text('Audio'), findsOneWidget);

        await tester.tap(find.byIcon(Icons.audiotrack));
        await tester.pumpAndSettle();

        final disableTile = tester.widget<ListTile>(
          find.widgetWithText(ListTile, 'Disable'),
        );
        final deTile = tester.widget<ListTile>(
          find.widgetWithText(ListTile, 'de'),
        );
        expect(disableTile.selected, isFalse);
        expect(deTile.selected, isTrue);
      },
    );

    testWidgets('calls onSeek with 10 second replay target', (tester) async {
      Duration? seekTarget;
      await tester.pumpWidget(
        MaterialApp(
          home: PlaybackControls(
            isPlaying: true,
            isLive: false,
            canSeek: true,
            currentPosition: const Duration(seconds: 30),
            duration: const Duration(minutes: 1),
            onPlayPause: () {},
            onSeek: (target) => seekTarget = target,
            onBack: () {},
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.replay_10));

      expect(seekTarget, const Duration(seconds: 20));
    });

    testWidgets('calls onSeek with 10 second forward target', (tester) async {
      Duration? seekTarget;
      await tester.pumpWidget(
        MaterialApp(
          home: PlaybackControls(
            isPlaying: true,
            isLive: false,
            canSeek: true,
            currentPosition: const Duration(seconds: 30),
            duration: const Duration(minutes: 1),
            onPlayPause: () {},
            onSeek: (target) => seekTarget = target,
            onBack: () {},
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.forward_10));

      expect(seekTarget, const Duration(seconds: 40));
    });

    testWidgets('clamps seek controls to media bounds', (tester) async {
      final seekTargets = <Duration>[];
      await tester.pumpWidget(
        MaterialApp(
          home: PlaybackControls(
            isPlaying: true,
            isLive: false,
            canSeek: true,
            currentPosition: const Duration(seconds: 5),
            duration: const Duration(seconds: 8),
            onPlayPause: () {},
            onSeek: seekTargets.add,
            onBack: () {},
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.replay_10));
      await tester.tap(find.byIcon(Icons.forward_10));

      expect(seekTargets, [Duration.zero, const Duration(seconds: 8)]);
    });

    testWidgets('clicking seekbar track seeks to clicked position', (
      tester,
    ) async {
      Duration? seekTarget;
      await tester.pumpWidget(
        MaterialApp(
          home: PlaybackControls(
            isPlaying: true,
            isLive: false,
            canSeek: true,
            currentPosition: Duration.zero,
            duration: const Duration(seconds: 100),
            onPlayPause: () {},
            onSeek: (target) => seekTarget = target,
            onBack: () {},
          ),
        ),
      );

      final track = find.byKey(const Key('playback-seekbar-track'));
      final rect = tester.getRect(track);

      await tester.tapAt(Offset(rect.left + rect.width * 0.5, rect.center.dy));
      await tester.pump();

      expect(seekTarget, const Duration(seconds: 50));
      expect(find.byKey(const Key('playback-seekbar-thumb')), findsOneWidget);
    });

    testWidgets('dragging seekbar track seeks to dragged position', (
      tester,
    ) async {
      final seekTargets = <Duration>[];
      await tester.pumpWidget(
        MaterialApp(
          home: PlaybackControls(
            isPlaying: true,
            isLive: false,
            canSeek: true,
            currentPosition: Duration.zero,
            duration: const Duration(seconds: 100),
            onPlayPause: () {},
            onSeek: seekTargets.add,
            onBack: () {},
          ),
        ),
      );

      final rect = tester.getRect(
        find.byKey(const Key('playback-seekbar-track')),
      );
      final gesture = await tester.startGesture(
        Offset(rect.left + rect.width * 0.25, rect.center.dy),
      );
      await gesture.moveTo(
        Offset(rect.left + rect.width * 0.75, rect.center.dy),
      );
      await gesture.up();

      expect(seekTargets, isNotEmpty);
      expect(seekTargets.last, const Duration(seconds: 75));
    });

    testWidgets('displays formatted time', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PlaybackControls(
            isPlaying: true,
            isLive: false,
            canSeek: true,
            currentPosition: const Duration(minutes: 5, seconds: 30),
            duration: const Duration(hours: 1, minutes: 30),
            onPlayPause: () {},
            onSeek: (_) {},
            onBack: () {},
          ),
        ),
      );
      expect(find.text('5:30'), findsOneWidget);
      expect(find.text('1:30:00'), findsOneWidget);
    });

    testWidgets('calls onBack when back button tapped', (tester) async {
      var backPressed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: PlaybackControls(
            isPlaying: true,
            isLive: false,
            canSeek: true,
            currentPosition: Duration.zero,
            duration: const Duration(hours: 1),
            onPlayPause: () {},
            onSeek: (_) {},
            onBack: () => backPressed = true,
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.arrow_back));
      expect(backPressed, isTrue);
    });

    testWidgets('shows fallback reason badge when provided', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: PlaybackControls(
            isPlaying: true,
            isLive: false,
            canSeek: true,
            currentPosition: Duration.zero,
            duration: const Duration(hours: 1),
            onPlayPause: () {},
            onSeek: (_) {},
            onBack: () {},
            fallbackReason: 'Server transcode active',
          ),
        ),
      );
      expect(find.text('Server transcode active'), findsOneWidget);
    });
  });

  group('TrackSelector', () {
    testWidgets('shows audio track selector button', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TrackSelector(
            audioTracks: const [
              PlaybackTrack(id: '1', label: 'English'),
              PlaybackTrack(id: '2', label: 'Spanish'),
            ],
            subtitleTracks: const [],
            selectedAudioTrackId: '1',
            selectedSubtitleTrackId: null,
            onAudioTrackSelected: (_) {},
            onSubtitleTrackSelected: (_) {},
          ),
        ),
      );
      expect(find.byIcon(Icons.audiotrack), findsOneWidget);
    });

    testWidgets('shows subtitle track selector button', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TrackSelector(
            audioTracks: const [],
            subtitleTracks: const [
              PlaybackTrack(id: '1', label: 'English'),
            ],
            selectedAudioTrackId: null,
            selectedSubtitleTrackId: null,
            onAudioTrackSelected: (_) {},
            onSubtitleTrackSelected: (_) {},
          ),
        ),
      );
      expect(find.byIcon(Icons.subtitles), findsOneWidget);
    });

    testWidgets('opens audio track dialog on tap', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TrackSelector(
            audioTracks: const [
              PlaybackTrack(id: '1', label: 'English'),
              PlaybackTrack(id: '2', label: 'Spanish'),
            ],
            subtitleTracks: const [],
            selectedAudioTrackId: '1',
            selectedSubtitleTrackId: null,
            onAudioTrackSelected: (_) {},
            onSubtitleTrackSelected: (_) {},
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.audiotrack));
      await tester.pumpAndSettle();
      expect(find.text('English'), findsWidgets);
    });

    testWidgets('marks Disable selected after audio disable is confirmed', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TrackSelector(
            audioTracks: const [
              PlaybackTrack(id: '1', label: 'English'),
              PlaybackTrack(id: '2', label: 'Spanish'),
            ],
            subtitleTracks: const [],
            selectedAudioTrackId: null,
            selectedSubtitleTrackId: null,
            isAudioTrackSelectionKnown: true,
            onAudioTrackSelected: (_) {},
            onSubtitleTrackSelected: (_) {},
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.audiotrack));
      await tester.pumpAndSettle();

      final disableTile = tester.widget<ListTile>(
        find.widgetWithText(ListTile, 'Disable'),
      );
      final englishTile = tester.widget<ListTile>(
        find.widgetWithText(ListTile, 'English'),
      );
      expect(disableTile.selected, isTrue);
      expect(englishTile.selected, isFalse);
    });

    testWidgets('opens subtitle track dialog on tap', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TrackSelector(
            audioTracks: const [],
            subtitleTracks: const [
              PlaybackTrack(id: '1', label: 'English CC'),
              PlaybackTrack(id: '2', label: 'Spanish Subs'),
            ],
            selectedAudioTrackId: null,
            selectedSubtitleTrackId: null,
            onAudioTrackSelected: (_) {},
            onSubtitleTrackSelected: (_) {},
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.subtitles));
      await tester.pumpAndSettle();
      expect(find.text('English CC'), findsWidgets);
    });

    testWidgets(
      'does not mark Off selected while subtitle selection is unknown',
      (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            home: TrackSelector(
              audioTracks: const [],
              subtitleTracks: const [
                PlaybackTrack(id: '1', label: 'English CC'),
              ],
              selectedAudioTrackId: null,
              selectedSubtitleTrackId: null,
              onAudioTrackSelected: (_) {},
              onSubtitleTrackSelected: (_) {},
            ),
          ),
        );

        await tester.tap(find.byIcon(Icons.subtitles));
        await tester.pumpAndSettle();

        final offTile = tester.widget<ListTile>(
          find.widgetWithText(ListTile, 'Off'),
        );
        final englishTile = tester.widget<ListTile>(
          find.widgetWithText(ListTile, 'English CC'),
        );
        expect(offTile.selected, isFalse);
        expect(englishTile.selected, isFalse);
      },
    );

    testWidgets('marks Off selected after subtitle disable is confirmed', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TrackSelector(
            audioTracks: const [],
            subtitleTracks: const [
              PlaybackTrack(id: '1', label: 'English CC'),
            ],
            selectedAudioTrackId: null,
            selectedSubtitleTrackId: null,
            isSubtitleTrackSelectionKnown: true,
            onAudioTrackSelected: (_) {},
            onSubtitleTrackSelected: (_) {},
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.subtitles));
      await tester.pumpAndSettle();

      final offTile = tester.widget<ListTile>(
        find.widgetWithText(ListTile, 'Off'),
      );
      final englishTile = tester.widget<ListTile>(
        find.widgetWithText(ListTile, 'English CC'),
      );
      expect(offTile.selected, isTrue);
      expect(englishTile.selected, isFalse);
    });

    testWidgets('calls onAudioTrackSelected when track chosen', (tester) async {
      String? selectedTrack;
      await tester.pumpWidget(
        MaterialApp(
          home: TrackSelector(
            audioTracks: const [
              PlaybackTrack(id: '1', label: 'English'),
              PlaybackTrack(id: '2', label: 'Spanish'),
            ],
            subtitleTracks: const [],
            selectedAudioTrackId: '1',
            selectedSubtitleTrackId: null,
            onAudioTrackSelected: (id) => selectedTrack = id,
            onSubtitleTrackSelected: (_) {},
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.audiotrack));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Spanish').last);
      await tester.pumpAndSettle();
      expect(selectedTrack, '2');
    });

    testWidgets('audio track dialog scrolls instead of overflowing', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(320, 360));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          home: TrackSelector(
            audioTracks: List<PlaybackTrack>.generate(
              12,
              (index) => PlaybackTrack(
                id: '$index',
                label: 'Language $index',
              ),
            ),
            subtitleTracks: const [],
            selectedAudioTrackId: '0',
            selectedSubtitleTrackId: null,
            onAudioTrackSelected: (_) {},
            onSubtitleTrackSelected: (_) {},
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.audiotrack));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(Scrollable), findsWidgets);
      expect(find.text('Language 11'), findsNothing);

      await tester.drag(find.byType(Scrollable).last, const Offset(0, -1000));
      await tester.pumpAndSettle();

      expect(find.text('Language 11'), findsOneWidget);
    });
  });

  group('EpgOverlay', () {
    testWidgets('shows LIVE badge for live content', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: EpgOverlay(
            currentTitle: 'Live News',
            currentProgress: 0.5,
            nextTitle: 'Weather Update',
          ),
        ),
      );
      expect(find.text('LIVE'), findsOneWidget);
      expect(find.text('Live News'), findsOneWidget);
    });

    testWidgets('shows progress bar', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: EpgOverlay(
            currentTitle: 'Live Show',
            currentProgress: 0.75,
            nextTitle: 'Next Show',
          ),
        ),
      );
      expect(find.byType(EpgProgressBar), findsOneWidget);
    });

    testWidgets('shows next program title', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: EpgOverlay(
            currentTitle: 'Current Show',
            currentProgress: 0.3,
            nextTitle: 'Up Next Show',
          ),
        ),
      );
      expect(find.text('Next: Up Next Show'), findsOneWidget);
    });

    testWidgets('hides next title when null', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: EpgOverlay(
            currentTitle: 'Current Show',
            currentProgress: 0.3,
          ),
        ),
      );
      expect(find.byType(EpgOverlay), findsOneWidget);
      expect(find.textContaining('Next:'), findsNothing);
    });
  });

  group('NowPlayingOverlay', () {
    testWidgets('shows badge and title for a movie', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: NowPlayingOverlay(badgeLabel: 'Movie', title: 'Some Movie'),
        ),
      );
      expect(find.text('Movie'), findsOneWidget);
      expect(find.text('Some Movie'), findsOneWidget);
    });

    testWidgets('shows season/episode subtitle for series', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: NowPlayingOverlay(
            badgeLabel: 'Series',
            title: 'Some Show',
            subtitle: 'S2 · E5 — Episode Title',
          ),
        ),
      );
      expect(find.text('Some Show'), findsOneWidget);
      expect(find.text('S2 · E5 — Episode Title'), findsOneWidget);
    });

    testWidgets('shows description when present', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: NowPlayingOverlay(
            badgeLabel: 'Movie',
            title: 'Some Movie',
            description: 'A thrilling adventure.',
          ),
        ),
      );
      expect(find.text('A thrilling adventure.'), findsOneWidget);
    });

    testWidgets('hides description when empty', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: NowPlayingOverlay(
            badgeLabel: 'Movie',
            title: 'Some Movie',
            description: '',
          ),
        ),
      );
      expect(find.byType(NowPlayingOverlay), findsOneWidget);
    });
  });

  group('ResumePrompt', () {
    testWidgets('shows resume and start over options', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ResumePrompt(
            position: const Duration(minutes: 5, seconds: 30),
            onResume: () {},
            onStartOver: () {},
          ),
        ),
      );
      expect(find.text('Resume'), findsOneWidget);
      expect(find.text('Start Over'), findsOneWidget);
    });

    testWidgets('shows formatted position in prompt', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: ResumePrompt(
            position: const Duration(minutes: 5, seconds: 30),
            onResume: () {},
            onStartOver: () {},
          ),
        ),
      );
      expect(find.textContaining('5:30'), findsOneWidget);
    });

    testWidgets('calls onResume when resume button tapped', (tester) async {
      var resumed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: ResumePrompt(
            position: const Duration(minutes: 5),
            onResume: () => resumed = true,
            onStartOver: () {},
          ),
        ),
      );
      await tester.tap(find.text('Resume'));
      expect(resumed, isTrue);
    });

    testWidgets('calls onStartOver when start over button tapped', (
      tester,
    ) async {
      var startedOver = false;
      await tester.pumpWidget(
        MaterialApp(
          home: ResumePrompt(
            position: const Duration(minutes: 5),
            onResume: () {},
            onStartOver: () => startedOver = true,
          ),
        ),
      );
      await tester.tap(find.text('Start Over'));
      expect(startedOver, isTrue);
    });
  });

  group('PlayerScreen', () {
    testWidgets(
      'hides visible controls when the overlay background is tapped',
      (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(const Size(1200, 800));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final adapter = FakePlayerAdapter(
          capabilities: PlaybackCapabilities.desktopLibmpv,
          textureId: 42,
        );
        final orchestrator = PlaybackOrchestrator(
          platform: PlaybackPlatform.desktop,
          adapters: <PlaybackBackend, PlayerAdapter>{
            PlaybackBackend.desktopLibmpv: adapter,
          },
          transcodeGateway: FakeTranscodeGateway(),
        );
        addTearDown(orchestrator.dispose);

        await tester.pumpWidget(
          MaterialApp(
            home: PlayerScreen(
              args: const PlayerArgs(
                streamUrl: 'https://example.com/live.m3u8',
                title: 'Overlay Fixture',
                type: 'live',
              ),
              orchestrator: orchestrator,
              epgService: EpgService(clock: () => DateTime.utc(2026)),
            ),
          ),
        );
        await tester.pump();
        expect(find.byType(PlaybackControls), findsOneWidget);

        await tester.tapAt(const Offset(1100, 400));
        await tester.pump();

        expect(find.byType(PlaybackControls), findsNothing);
      },
    );

    testWidgets('keeps visible controls open when play pause is tapped', (
      tester,
    ) async {
      final adapter = FakePlayerAdapter(
        capabilities: PlaybackCapabilities.desktopLibmpv,
        textureId: 42,
      );
      final orchestrator = PlaybackOrchestrator(
        platform: PlaybackPlatform.desktop,
        adapters: <PlaybackBackend, PlayerAdapter>{
          PlaybackBackend.desktopLibmpv: adapter,
        },
        transcodeGateway: FakeTranscodeGateway(),
      );
      addTearDown(orchestrator.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: PlayerScreen(
            args: const PlayerArgs(
              streamUrl: 'https://example.com/live.m3u8',
              title: 'Control Fixture',
              type: 'live',
            ),
            orchestrator: orchestrator,
            epgService: EpgService(clock: () => DateTime.utc(2026)),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.play_arrow));
      await tester.pump();

      expect(adapter.playCallCount, 1);
      expect(find.byType(PlaybackControls), findsOneWidget);
    });

    testWidgets('hides visible controls when the live EPG overlay is tapped', (
      tester,
    ) async {
      final now = DateTime.utc(2026, 1, 1, 12);
      final adapter = FakePlayerAdapter(
        capabilities: PlaybackCapabilities.desktopLibmpv,
        textureId: 42,
      );
      final orchestrator = PlaybackOrchestrator(
        platform: PlaybackPlatform.desktop,
        adapters: <PlaybackBackend, PlayerAdapter>{
          PlaybackBackend.desktopLibmpv: adapter,
        },
        transcodeGateway: FakeTranscodeGateway(),
      );
      addTearDown(orchestrator.dispose);
      final epgService = EpgService(clock: () => now)
        ..loadPrograms(<EpgProgram>[
          EpgProgram(
            channelId: 'bbc.one',
            title: 'Current News',
            description: 'Fixture bulletin',
            start: now.subtract(const Duration(minutes: 10)),
            end: now.add(const Duration(minutes: 20)),
          ),
        ]);

      await tester.pumpWidget(
        MaterialApp(
          home: PlayerScreen(
            args: const PlayerArgs(
              streamUrl: 'https://example.com/live.m3u8',
              title: 'EPG Tap Fixture',
              type: 'live',
              epgChannelId: 'bbc.one',
            ),
            orchestrator: orchestrator,
            epgService: epgService,
          ),
        ),
      );
      await tester.pump();
      adapter.emitState(
        const PlaybackState(
          backend: PlaybackBackend.desktopLibmpv,
          status: PlaybackStatus.ready,
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.byType(EpgOverlay), findsOneWidget);

      await tester.tap(find.byType(EpgOverlay));
      await tester.pump();

      expect(find.byType(PlaybackControls), findsNothing);
    });

    testWidgets(
      'hides visible controls when the Now Playing overlay is tapped',
      (
        tester,
      ) async {
        final adapter = FakePlayerAdapter(
          capabilities: PlaybackCapabilities.desktopLibmpv,
          textureId: 42,
        );
        final orchestrator = PlaybackOrchestrator(
          platform: PlaybackPlatform.desktop,
          adapters: <PlaybackBackend, PlayerAdapter>{
            PlaybackBackend.desktopLibmpv: adapter,
          },
          transcodeGateway: FakeTranscodeGateway(),
        );
        addTearDown(orchestrator.dispose);

        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: PlayerScreen(
              args: const PlayerArgs(
                streamUrl: 'https://example.com/movie.mkv',
                title: 'Now Playing Tap Fixture',
                type: 'vod',
              ),
              orchestrator: orchestrator,
              epgService: EpgService(clock: () => DateTime.utc(2026)),
            ),
          ),
        );
        await tester.pump();
        expect(find.byType(NowPlayingOverlay), findsOneWidget);

        await tester.tap(find.byType(NowPlayingOverlay));
        await tester.pump();

        expect(find.byType(PlaybackControls), findsNothing);
      },
    );

    testWidgets('renders desktop libmpv texture when backend is ready', (
      tester,
    ) async {
      final adapter = FakePlayerAdapter(
        capabilities: PlaybackCapabilities.desktopLibmpv,
        textureId: 42,
      );
      final orchestrator = PlaybackOrchestrator(
        platform: PlaybackPlatform.desktop,
        adapters: <PlaybackBackend, PlayerAdapter>{
          PlaybackBackend.desktopLibmpv: adapter,
        },
        transcodeGateway: FakeTranscodeGateway(),
      );
      addTearDown(orchestrator.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: PlayerScreen(
            args: const PlayerArgs(
              streamUrl: 'https://example.com/live.m3u8',
              title: 'Texture Fixture',
              type: 'live',
            ),
            orchestrator: orchestrator,
            epgService: EpgService(clock: () => DateTime.utc(2026)),
          ),
        ),
      );
      await tester.pump();
      expect(adapter.loadCalls, hasLength(1));

      adapter.emitState(
        const PlaybackState(
          backend: PlaybackBackend.desktopLibmpv,
          status: PlaybackStatus.ready,
        ),
      );
      await tester.pump();
      await tester.pump();

      final texture = tester.widget<Texture>(find.byType(Texture));
      expect(texture.textureId, 42);
    });

    testWidgets('seeks to resume position after backend load', (tester) async {
      final adapter = FakePlayerAdapter(
        capabilities: PlaybackCapabilities.desktopLibmpv,
        textureId: 42,
      );
      final orchestrator = PlaybackOrchestrator(
        platform: PlaybackPlatform.desktop,
        adapters: <PlaybackBackend, PlayerAdapter>{
          PlaybackBackend.desktopLibmpv: adapter,
        },
        transcodeGateway: FakeTranscodeGateway(),
      );
      addTearDown(orchestrator.dispose);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: PlayerScreen(
            args: const PlayerArgs(
              streamUrl: 'https://example.com/movie.mkv',
              title: 'Resume Fixture',
              type: 'vod',
              startPosition: 47,
            ),
            orchestrator: orchestrator,
            epgService: EpgService(clock: () => DateTime.utc(2026)),
          ),
        ),
      );
      await tester.pump();

      expect(
        adapter.loadCalls.single.startPosition,
        const Duration(seconds: 47),
      );
      expect(adapter.seekCalls, <Duration>[const Duration(seconds: 47)]);
    });

    testWidgets('reports VOD progress immediately when seeking', (
      tester,
    ) async {
      final adapter = FakePlayerAdapter(
        capabilities: PlaybackCapabilities.desktopLibmpv,
        textureId: 42,
      );
      final orchestrator = PlaybackOrchestrator(
        platform: PlaybackPlatform.desktop,
        adapters: <PlaybackBackend, PlayerAdapter>{
          PlaybackBackend.desktopLibmpv: adapter,
        },
        transcodeGateway: FakeTranscodeGateway(),
      );
      addTearDown(orchestrator.dispose);
      final reports = <Progress>[];

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: PlayerScreen(
            args: const PlayerArgs(
              streamUrl: 'https://example.com/movie.mkv',
              title: 'Progress Fixture',
              type: 'vod',
              streamId: 201,
            ),
            orchestrator: orchestrator,
            epgService: EpgService(clock: () => DateTime.utc(2026)),
            viewerId: 'viewer-1',
            progressReporter: reports.add,
          ),
        ),
      );
      await tester.pump();
      adapter.emitState(
        const PlaybackState(
          backend: PlaybackBackend.desktopLibmpv,
          status: PlaybackStatus.ready,
          duration: Duration(minutes: 10),
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.forward_10));
      await tester.pump();

      expect(adapter.seekCalls.last, const Duration(seconds: 10));
      expect(reports, hasLength(1));
      expect(reports.single.viewerId, 'viewer-1');
      expect(reports.single.contentType, ContentType.vod);
      expect(reports.single.streamId, 201);
      expect(reports.single.positionSeconds, 10);
      expect(reports.single.durationSeconds, 600);
    });

    testWidgets('keeps the overlay visible indefinitely while paused', (
      tester,
    ) async {
      final adapter = FakePlayerAdapter(
        capabilities: PlaybackCapabilities.desktopLibmpv,
        textureId: 42,
      );
      final orchestrator = PlaybackOrchestrator(
        platform: PlaybackPlatform.desktop,
        adapters: <PlaybackBackend, PlayerAdapter>{
          PlaybackBackend.desktopLibmpv: adapter,
        },
        transcodeGateway: FakeTranscodeGateway(),
      );
      addTearDown(orchestrator.dispose);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: PlayerScreen(
            args: const PlayerArgs(
              streamUrl: 'https://example.com/movie.mkv',
              title: 'Pause Fixture',
              type: 'vod',
            ),
            orchestrator: orchestrator,
            epgService: EpgService(clock: () => DateTime.utc(2026)),
          ),
        ),
      );
      await tester.pump();

      adapter.emitState(
        const PlaybackState(
          backend: PlaybackBackend.desktopLibmpv,
          status: PlaybackStatus.playing,
          duration: Duration(minutes: 10),
        ),
      );
      await tester.pump();

      adapter.emitState(
        const PlaybackState(
          backend: PlaybackBackend.desktopLibmpv,
          status: PlaybackStatus.paused,
          duration: Duration(minutes: 10),
        ),
      );
      await tester.pump();

      // Overlay timeout is 8s - wait well past it while paused.
      await tester.pump(const Duration(seconds: 9));
      expect(find.byType(NowPlayingOverlay), findsOneWidget);
      expect(find.byType(PlaybackControls), findsOneWidget);

      // Resuming playback restarts the countdown, so the overlay now hides.
      adapter.emitState(
        const PlaybackState(
          backend: PlaybackBackend.desktopLibmpv,
          status: PlaybackStatus.playing,
          duration: Duration(minutes: 10),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 9));
      expect(find.byType(NowPlayingOverlay), findsNothing);
      expect(find.byType(PlaybackControls), findsNothing);
    });

    testWidgets(
      'still times out the overlay despite repeated playing position ticks',
      (tester) async {
        final adapter = FakePlayerAdapter(
          capabilities: PlaybackCapabilities.desktopLibmpv,
          textureId: 42,
        );
        final orchestrator = PlaybackOrchestrator(
          platform: PlaybackPlatform.desktop,
          adapters: <PlaybackBackend, PlayerAdapter>{
            PlaybackBackend.desktopLibmpv: adapter,
          },
          transcodeGateway: FakeTranscodeGateway(),
        );
        addTearDown(orchestrator.dispose);

        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: PlayerScreen(
              args: const PlayerArgs(
                streamUrl: 'https://example.com/movie.mkv',
                title: 'Tick Fixture',
                type: 'vod',
              ),
              orchestrator: orchestrator,
              epgService: EpgService(clock: () => DateTime.utc(2026)),
            ),
          ),
        );
        await tester.pump();

        adapter.emitState(
          const PlaybackState(
            backend: PlaybackBackend.desktopLibmpv,
            status: PlaybackStatus.playing,
            duration: Duration(minutes: 10),
          ),
        );
        await tester.pump();

        // Simulate position-tick updates that resend `playing` every second,
        // the way the real player adapters do - these must not keep
        // re-arming the hide timer.
        for (var i = 1; i <= 9; i++) {
          await tester.pump(const Duration(seconds: 1));
          adapter.emitState(
            PlaybackState(
              backend: PlaybackBackend.desktopLibmpv,
              status: PlaybackStatus.playing,
              duration: const Duration(minutes: 10),
              position: Duration(seconds: i),
            ),
          );
        }

        expect(find.byType(NowPlayingOverlay), findsNothing);
        expect(find.byType(PlaybackControls), findsNothing);
      },
    );

    testWidgets(
      'preserves reported source aspect ratio for the video surface',
      (
        tester,
      ) async {
        final adapter = FakePlayerAdapter(
          capabilities: PlaybackCapabilities.desktopLibmpv,
          textureId: 42,
        );
        final orchestrator = PlaybackOrchestrator(
          platform: PlaybackPlatform.desktop,
          adapters: <PlaybackBackend, PlayerAdapter>{
            PlaybackBackend.desktopLibmpv: adapter,
          },
          transcodeGateway: FakeTranscodeGateway(),
        );
        addTearDown(orchestrator.dispose);

        await tester.binding.setSurfaceSize(const Size(1600, 900));
        addTearDown(() => tester.binding.setSurfaceSize(null));

        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            home: PlayerScreen(
              args: const PlayerArgs(
                streamUrl: 'https://example.com/four-three.m3u8',
                title: '4:3 Fixture',
                type: 'vod',
              ),
              orchestrator: orchestrator,
              epgService: EpgService(clock: () => DateTime.utc(2026)),
            ),
          ),
        );
        await tester.pump();

        adapter.emitState(
          const PlaybackState(
            backend: PlaybackBackend.desktopLibmpv,
            status: PlaybackStatus.ready,
            videoAspectRatio: 16 / 9,
          ),
        );
        await tester.pump();
        await tester.pump();

        final initialTextureSize = tester.getSize(find.byType(Texture));
        expect(initialTextureSize.width, moreOrLessEquals(1600));
        expect(initialTextureSize.height, moreOrLessEquals(900));

        adapter.emitState(
          const PlaybackState(
            backend: PlaybackBackend.desktopLibmpv,
            status: PlaybackStatus.ready,
            videoAspectRatio: 4 / 3,
          ),
        );
        await tester.pump();
        await tester.pump();

        final fourThreeTextureSize = tester.getSize(find.byType(Texture));
        expect(fourThreeTextureSize.width, moreOrLessEquals(1200));
        expect(fourThreeTextureSize.height, moreOrLessEquals(900));

        adapter.emitState(
          const PlaybackState(
            backend: PlaybackBackend.desktopLibmpv,
            status: PlaybackStatus.ready,
            videoAspectRatio: 3840 / 1608,
          ),
        );
        await tester.pump();
        await tester.pump();

        final ultrawideTextureSize = tester.getSize(find.byType(Texture));
        expect(ultrawideTextureSize.width, moreOrLessEquals(1600));
        expect(
          ultrawideTextureSize.height,
          moreOrLessEquals(670, epsilon: 0.01),
        );
      },
    );

    testWidgets('shows live EPG as soon as playback is ready', (tester) async {
      final now = DateTime.utc(2026, 1, 1, 12);
      final adapter = FakePlayerAdapter(
        capabilities: PlaybackCapabilities.desktopLibmpv,
        textureId: 42,
      );
      final orchestrator = PlaybackOrchestrator(
        platform: PlaybackPlatform.desktop,
        adapters: <PlaybackBackend, PlayerAdapter>{
          PlaybackBackend.desktopLibmpv: adapter,
        },
        transcodeGateway: FakeTranscodeGateway(),
      );
      addTearDown(orchestrator.dispose);
      final epgService = EpgService(clock: () => now)
        ..loadPrograms(
          <EpgProgram>[
            EpgProgram(
              channelId: 'bbc.one',
              title: 'Current News',
              description: 'Fixture bulletin',
              start: now.subtract(const Duration(minutes: 10)),
              end: now.add(const Duration(minutes: 20)),
            ),
          ],
        );

      await tester.pumpWidget(
        MaterialApp(
          home: PlayerScreen(
            args: const PlayerArgs(
              streamUrl: 'https://example.com/live.m3u8',
              title: 'EPG Fixture',
              type: 'live',
              epgChannelId: 'bbc.one',
            ),
            orchestrator: orchestrator,
            epgService: epgService,
          ),
        ),
      );
      await tester.pump();
      expect(adapter.loadCalls, hasLength(1));

      adapter.emitState(
        const PlaybackState(
          backend: PlaybackBackend.desktopLibmpv,
          status: PlaybackStatus.ready,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Current News'), findsOneWidget);
    });

    testWidgets('fetches short EPG when player cache misses', (tester) async {
      final now = DateTime.utc(2026, 1, 1, 12);
      final adapter = FakePlayerAdapter(
        capabilities: PlaybackCapabilities.desktopLibmpv,
        textureId: 42,
      );
      final orchestrator = PlaybackOrchestrator(
        platform: PlaybackPlatform.desktop,
        adapters: <PlaybackBackend, PlayerAdapter>{
          PlaybackBackend.desktopLibmpv: adapter,
        },
        transcodeGateway: FakeTranscodeGateway(),
      );
      addTearDown(orchestrator.dispose);
      final requests = <XtreamRequest>[];
      final xtreamService = XtreamService(
        transport: (request) async {
          requests.add(request);
          if (request.action == null) {
            return {
              'user_info': {'auth': 1, 'status': 'Active'},
              'm3u_editor': {'version': 'fixture'},
            };
          }
          if (request.action == 'get_short_epg') {
            return {
              'epg_listings': [
                {
                  'channel_id': 'bbc.one',
                  'title': 'Fetched News',
                  'description': 'Fetched bulletin',
                  'start': now
                      .subtract(const Duration(minutes: 10))
                      .toIso8601String(),
                  'end': now.add(const Duration(minutes: 20)).toIso8601String(),
                },
              ],
            };
          }
          return <String, Object?>{};
        },
      );
      await xtreamService.authenticate(
        const UserCredentials(
          server: 'https://xtream.example',
          username: 'demo',
          password: 'secret',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: PlayerScreen(
            args: const PlayerArgs(
              streamUrl: 'https://example.com/live.m3u8',
              title: 'EPG Fetch Fixture',
              type: 'live',
              streamId: 101,
              epgChannelId: 'bbc.one',
            ),
            orchestrator: orchestrator,
            epgService: EpgService(clock: () => now),
            xtreamService: xtreamService,
          ),
        ),
      );
      await tester.pump();
      expect(adapter.loadCalls, hasLength(1));

      adapter.emitState(
        const PlaybackState(
          backend: PlaybackBackend.desktopLibmpv,
          status: PlaybackStatus.ready,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Fetched News'), findsOneWidget);
      expect(requests.last.action, 'get_short_epg');
      expect(requests.last.params, {'stream_id': '101', 'limit': '4'});
    });

    testWidgets('short EPG failures retry after backoff when guide is stale', (
      tester,
    ) async {
      var now = DateTime.utc(2026, 1, 1, 12);
      final adapter = FakePlayerAdapter(
        capabilities: PlaybackCapabilities.desktopLibmpv,
        textureId: 42,
      );
      final orchestrator = PlaybackOrchestrator(
        platform: PlaybackPlatform.desktop,
        adapters: <PlaybackBackend, PlayerAdapter>{
          PlaybackBackend.desktopLibmpv: adapter,
        },
        transcodeGateway: FakeTranscodeGateway(),
      );
      addTearDown(orchestrator.dispose);
      final epgService =
          EpgService(
            clock: () => now,
            cacheTtl: const Duration(hours: 1),
          )..loadPrograms(<EpgProgram>[
            EpgProgram(
              channelId: 'bbc.one',
              title: 'Loaded News',
              description: '',
              start: now.subtract(const Duration(minutes: 10)),
              end: now.add(const Duration(hours: 3)),
            ),
          ]);
      now = now.add(const Duration(hours: 1));
      var shortEpgRequests = 0;
      final xtreamService = XtreamService(
        transport: (request) async {
          if (request.action == null) {
            return {
              'user_info': {'auth': 1, 'status': 'Active'},
              'm3u_editor': {'version': 'fixture'},
            };
          }
          if (request.action == 'get_short_epg') {
            shortEpgRequests += 1;
            throw StateError('temporary EPG outage');
          }
          return <String, Object?>{};
        },
      );
      await xtreamService.authenticate(
        const UserCredentials(
          server: 'https://xtream.example',
          username: 'demo',
          password: 'secret',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: PlayerScreen(
            args: const PlayerArgs(
              streamUrl: 'https://example.com/live.m3u8',
              title: 'EPG Retry Fixture',
              type: 'live',
              streamId: 101,
              epgChannelId: 'bbc.one',
            ),
            orchestrator: orchestrator,
            epgService: epgService,
            xtreamService: xtreamService,
          ),
        ),
      );
      await tester.pump();
      adapter.emitState(
        const PlaybackState(
          backend: PlaybackBackend.desktopLibmpv,
          status: PlaybackStatus.ready,
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.text('Loaded News'), findsOneWidget);
      expect(shortEpgRequests, 1);

      now = now.add(const Duration(seconds: 30));
      await tester.pump(const Duration(seconds: 30));
      expect(shortEpgRequests, 1);

      now = now.add(const Duration(seconds: 30));
      await tester.pump(const Duration(seconds: 30));
      expect(shortEpgRequests, 2);
    });

    testWidgets('successful empty short EPG response clears stale guide', (
      tester,
    ) async {
      var now = DateTime.utc(2026, 1, 1, 12);
      final adapter = FakePlayerAdapter(
        capabilities: PlaybackCapabilities.desktopLibmpv,
        textureId: 42,
      );
      final orchestrator = PlaybackOrchestrator(
        platform: PlaybackPlatform.desktop,
        adapters: <PlaybackBackend, PlayerAdapter>{
          PlaybackBackend.desktopLibmpv: adapter,
        },
        transcodeGateway: FakeTranscodeGateway(),
      );
      addTearDown(orchestrator.dispose);
      final epgService = EpgService(clock: () => now)
        ..loadPrograms(<EpgProgram>[
          EpgProgram(
            channelId: 'bbc.one',
            title: 'Stale News',
            description: '',
            start: now.subtract(const Duration(minutes: 10)),
            end: now.add(const Duration(hours: 2)),
          ),
        ]);
      now = now.add(const Duration(minutes: 30));
      expect(epgService.lookup('bbc.one')?.current.title, 'Stale News');
      var shortEpgRequests = 0;
      final xtreamService = XtreamService(
        transport: (request) async {
          if (request.action == null) {
            return {
              'user_info': {'auth': 1, 'status': 'Active'},
              'm3u_editor': {'version': 'fixture'},
            };
          }
          if (request.action == 'get_short_epg') {
            shortEpgRequests += 1;
            return <String, Object?>{'epg_listings': <Object?>[]};
          }
          return <String, Object?>{};
        },
      );
      await xtreamService.authenticate(
        const UserCredentials(
          server: 'https://xtream.example',
          username: 'demo',
          password: 'secret',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: PlayerScreen(
            args: const PlayerArgs(
              streamUrl: 'https://example.com/live.m3u8',
              title: 'Empty EPG Fixture',
              type: 'live',
              streamId: 101,
              epgChannelId: 'bbc.one',
            ),
            orchestrator: orchestrator,
            epgService: epgService,
            xtreamService: xtreamService,
          ),
        ),
      );
      await tester.pump();
      adapter.emitState(
        const PlaybackState(
          backend: PlaybackBackend.desktopLibmpv,
          status: PlaybackStatus.ready,
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(shortEpgRequests, 1);
      expect(epgService.lookup('bbc.one'), isNull);
      expect(find.text('Stale News'), findsNothing);

      now = now.add(const Duration(seconds: 30));
      await tester.pump(const Duration(seconds: 30));

      expect(shortEpgRequests, 1);
    });

    final trackSelectorSystems =
        <
          ({
            String name,
            PlaybackPlatform platform,
            PlaybackCapabilities capabilities,
            Size size,
          })
        >[
          (
            name: 'Android TV Media3',
            platform: PlaybackPlatform.android,
            capabilities: PlaybackCapabilities.androidExoPlayer,
            size: const Size(1920, 1080),
          ),
          (
            name: 'Android phone Media3',
            platform: PlaybackPlatform.android,
            capabilities: PlaybackCapabilities.androidExoPlayer,
            size: const Size(412, 915),
          ),
          (
            name: 'Apple TV AVKit',
            platform: PlaybackPlatform.apple,
            capabilities: PlaybackCapabilities.appleAvKit,
            size: const Size(1920, 1080),
          ),
          (
            name: 'Linux libmpv',
            platform: PlaybackPlatform.desktop,
            capabilities: PlaybackCapabilities.desktopLibmpv,
            size: const Size(1280, 720),
          ),
          (
            name: 'Windows libmpv',
            platform: PlaybackPlatform.desktop,
            capabilities: PlaybackCapabilities.desktopLibmpv,
            size: const Size(1366, 768),
          ),
        ];

    for (final system in trackSelectorSystems) {
      testWidgets(
        '${system.name} shows both track selectors and applies selections',
        (tester) async {
          await tester.binding.setSurfaceSize(system.size);
          addTearDown(() => tester.binding.setSurfaceSize(null));
          final adapter = FakePlayerAdapter(
            capabilities: system.capabilities,
            textureId: 42,
          );
          final backend = system.capabilities.backend;
          final orchestrator = PlaybackOrchestrator(
            platform: system.platform,
            adapters: <PlaybackBackend, PlayerAdapter>{backend: adapter},
            transcodeGateway: FakeTranscodeGateway(),
          );
          addTearDown(orchestrator.dispose);

          await tester.pumpWidget(
            MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: PlayerScreen(
                args: const PlayerArgs(
                  streamUrl: 'https://example.com/movie.m3u8',
                  title: 'Track Fixture',
                  type: 'movie',
                ),
                orchestrator: orchestrator,
                epgService: EpgService(clock: () => DateTime.utc(2026)),
              ),
            ),
          );
          await tester.pump();

          adapter.emitState(
            PlaybackState(
              backend: backend,
              status: PlaybackStatus.ready,
              duration: const Duration(hours: 1),
              audioTracks: const <PlaybackTrack>[
                PlaybackTrack(
                  id: 'audio-eng',
                  label: 'English',
                  language: 'eng',
                ),
                PlaybackTrack(
                  id: 'audio-spa',
                  label: 'Spanish',
                  language: 'spa',
                ),
              ],
              subtitleTracks: const <PlaybackTrack>[
                PlaybackTrack(
                  id: 'sub-eng',
                  label: 'English CC',
                  language: 'eng',
                ),
              ],
              selectedAudioTrackId: 'audio-eng',
            ),
          );
          await tester.pump();

          expect(tester.takeException(), isNull);
          expect(find.byIcon(Icons.audiotrack), findsOneWidget);
          expect(find.byIcon(Icons.subtitles), findsOneWidget);
          await tester.tap(find.byIcon(Icons.audiotrack));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Spanish').last);
          await tester.pumpAndSettle();
          await tester.tap(find.byIcon(Icons.subtitles));
          await tester.pumpAndSettle();
          await tester.tap(find.text('English CC').last);
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(adapter.setAudioTrackCalls, <String?>['audio-spa']);
          expect(adapter.setSubtitleTrackCalls, <String?>['sub-eng']);
        },
      );
    }

    for (final systemName in <String>['Linux libmpv', 'Windows libmpv']) {
      testWidgets(
        '$systemName confirms disabled tracks without losing track lists',
        (tester) async {
          final adapter = FakePlayerAdapter(
            capabilities: PlaybackCapabilities.desktopLibmpv,
            textureId: 42,
          );
          final orchestrator = PlaybackOrchestrator(
            platform: PlaybackPlatform.desktop,
            adapters: <PlaybackBackend, PlayerAdapter>{
              PlaybackBackend.desktopLibmpv: adapter,
            },
            transcodeGateway: FakeTranscodeGateway(),
          );
          addTearDown(orchestrator.dispose);
          const audioTracks = <PlaybackTrack>[
            PlaybackTrack(id: 'audio-eng', label: 'English'),
            PlaybackTrack(id: 'audio-spa', label: 'Spanish'),
          ];
          const subtitleTracks = <PlaybackTrack>[
            PlaybackTrack(id: 'sub-eng', label: 'English CC'),
          ];

          await tester.pumpWidget(
            MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: PlayerScreen(
                args: const PlayerArgs(
                  streamUrl: 'https://example.com/movie.m3u8',
                  title: 'Track Fixture',
                  type: 'movie',
                ),
                orchestrator: orchestrator,
                epgService: EpgService(clock: () => DateTime.utc(2026)),
              ),
            ),
          );
          await tester.pump();

          adapter.emitState(
            const PlaybackState(
              backend: PlaybackBackend.desktopLibmpv,
              status: PlaybackStatus.ready,
              audioTracks: audioTracks,
              subtitleTracks: subtitleTracks,
              selectedAudioTrackId: 'audio-eng',
              selectedSubtitleTrackId: 'sub-eng',
              isAudioTrackSelectionKnown: true,
              isSubtitleTrackSelectionKnown: true,
            ),
          );
          await tester.pump();

          await tester.tap(find.byIcon(Icons.audiotrack));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Disable'));
          await tester.pumpAndSettle();
          expect(adapter.setAudioTrackCalls, <String?>[null]);

          adapter.emitState(
            const PlaybackState(
              backend: PlaybackBackend.desktopLibmpv,
              status: PlaybackStatus.playing,
              audioTracks: audioTracks,
              subtitleTracks: subtitleTracks,
              selectedSubtitleTrackId: 'sub-eng',
              isAudioTrackSelectionKnown: true,
              isSubtitleTrackSelectionKnown: true,
            ),
          );
          await tester.pump();
          await tester.pump();
          expect(
            tester
                .widget<PlaybackControls>(find.byType(PlaybackControls))
                .isAudioTrackSelectionKnown,
            isTrue,
          );
          expect(
            tester
                .widget<TrackSelector>(find.byType(TrackSelector))
                .isAudioTrackSelectionKnown,
            isTrue,
          );
          expect(
            tester
                .widget<TrackSelector>(find.byType(TrackSelector))
                .selectedAudioTrackId,
            isNull,
          );
          await tester.tap(find.byIcon(Icons.audiotrack));
          await tester.pumpAndSettle();

          expect(
            tester
                .widget<ListTile>(find.widgetWithText(ListTile, 'Disable'))
                .selected,
            isTrue,
          );
          expect(find.text('English'), findsOneWidget);
          expect(find.text('Spanish'), findsOneWidget);
          tester.state<NavigatorState>(find.byType(Navigator)).pop();
          await tester.pumpAndSettle();

          await tester.tap(find.byIcon(Icons.subtitles));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Off'));
          await tester.pumpAndSettle();
          expect(adapter.setSubtitleTrackCalls, <String?>[null]);

          adapter.emitState(
            const PlaybackState(
              backend: PlaybackBackend.desktopLibmpv,
              status: PlaybackStatus.playing,
              audioTracks: audioTracks,
              subtitleTracks: subtitleTracks,
              isAudioTrackSelectionKnown: true,
              isSubtitleTrackSelectionKnown: true,
            ),
          );
          await tester.pump();
          await tester.pump();
          expect(
            tester
                .widget<PlaybackControls>(find.byType(PlaybackControls))
                .isSubtitleTrackSelectionKnown,
            isTrue,
          );
          await tester.tap(find.byIcon(Icons.subtitles));
          await tester.pumpAndSettle();

          expect(
            tester
                .widget<ListTile>(find.widgetWithText(ListTile, 'Off'))
                .selected,
            isTrue,
          );
          expect(find.text('English CC'), findsOneWidget);
        },
      );
    }

    testWidgets('backs out of the route when playback error is visible', (
      tester,
    ) async {
      final adapter = FakePlayerAdapter(
        capabilities: PlaybackCapabilities.androidExoPlayer,
      );
      final orchestrator = PlaybackOrchestrator(
        platform: PlaybackPlatform.android,
        adapters: <PlaybackBackend, PlayerAdapter>{
          PlaybackBackend.androidExoPlayer: adapter,
        },
        transcodeGateway: FakeTranscodeGateway(),
      );
      addTearDown(orchestrator.dispose);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) {
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Launcher'),
                    ElevatedButton(
                      onPressed: () {
                        unawaited(
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => PlayerScreen(
                                args: const PlayerArgs(
                                  streamUrl: 'https://example.com/live.m3u8',
                                  title: 'Error Fixture',
                                  type: 'live',
                                ),
                                orchestrator: orchestrator,
                                epgService: EpgService(
                                  clock: () => DateTime.utc(2026),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                      child: const Text('Open player'),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open player'));
      await tester.pumpAndSettle();

      adapter.emitError(
        const PlaybackError(
          backend: PlaybackBackend.androidExoPlayer,
          message: 'Playback failed',
          code: 'playback_failed',
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Playback error'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.text('Launcher'), findsOneWidget);
      expect(find.text('Playback error'), findsNothing);
    });

    testWidgets(
      'switching live channel via a stable key reuses the orchestrator '
      'instead of disposing it',
      (tester) async {
        // Mirrors AppShell: skip-previous/skip-next replaces `args` on an
        // already-mounted PlayerScreen (stable key, same orchestrator)
        // instead of remounting with a fresh orchestrator per channel. If
        // that stops happening, the Android Media3/Apple AVKit native
        // plugins' single global player gets released out from under the
        // channel the user just switched to.
        final adapter = FakePlayerAdapter(
          capabilities: PlaybackCapabilities.desktopLibmpv,
          textureId: 7,
        );
        final orchestrator = PlaybackOrchestrator(
          platform: PlaybackPlatform.desktop,
          adapters: <PlaybackBackend, PlayerAdapter>{
            PlaybackBackend.desktopLibmpv: adapter,
          },
          transcodeGateway: FakeTranscodeGateway(),
        );
        addTearDown(orchestrator.dispose);

        const channelA = PlayerArgs(
          streamUrl: 'https://example.com/channel-a.m3u8',
          title: 'Channel A',
          type: 'live',
          streamId: 1,
        );
        const channelB = PlayerArgs(
          streamUrl: 'https://example.com/channel-b.m3u8',
          title: 'Channel B',
          type: 'live',
          streamId: 2,
        );

        var args = channelA;
        late StateSetter setArgs;

        await tester.pumpWidget(
          MaterialApp(
            home: StatefulBuilder(
              builder: (context, setState) {
                setArgs = setState;
                return PlayerScreen(
                  key: const ValueKey('player-session'),
                  args: args,
                  orchestrator: orchestrator,
                  epgService: EpgService(clock: () => DateTime.utc(2026)),
                );
              },
            ),
          ),
        );
        await tester.pump();

        expect(adapter.loadCalls, hasLength(1));
        expect(adapter.loadCalls.single.uri, channelA.streamUrl);
        expect(adapter.disposeCallCount, 0);

        setArgs(() => args = channelB);
        await tester.pump();

        // The switch happened in place: same adapter kept loading, never
        // torn down mid-flight.
        expect(adapter.loadCalls, hasLength(2));
        expect(adapter.loadCalls.last.uri, channelB.streamUrl);
        expect(adapter.disposeCallCount, 0);
      },
    );

    testWidgets(
      'switching to a channel sharing a URL but a different stream ID '
      'still re-opens the new source',
      (tester) async {
        // Two channels can share a stream URL (e.g. a proxied/transcoded URL
        // keyed by query params the client doesn't see) while differing in
        // stream ID, headers, EPG ID, or metadata. Comparing streamUrl alone
        // in didUpdateWidget would wrongly treat this as a no-op switch and
        // leave the previous channel's EPG/state in place.
        final adapter = FakePlayerAdapter(
          capabilities: PlaybackCapabilities.desktopLibmpv,
          textureId: 9,
        );
        final orchestrator = PlaybackOrchestrator(
          platform: PlaybackPlatform.desktop,
          adapters: <PlaybackBackend, PlayerAdapter>{
            PlaybackBackend.desktopLibmpv: adapter,
          },
          transcodeGateway: FakeTranscodeGateway(),
        );
        addTearDown(orchestrator.dispose);

        const sharedUrl = 'https://example.com/shared.m3u8';
        const channelA = PlayerArgs(
          streamUrl: sharedUrl,
          title: 'Channel A',
          type: 'live',
          streamId: 1,
          epgChannelId: 'channel-a',
        );
        const channelB = PlayerArgs(
          streamUrl: sharedUrl,
          title: 'Channel B',
          type: 'live',
          streamId: 2,
          epgChannelId: 'channel-b',
        );

        var args = channelA;
        late StateSetter setArgs;

        await tester.pumpWidget(
          MaterialApp(
            home: StatefulBuilder(
              builder: (context, setState) {
                setArgs = setState;
                return PlayerScreen(
                  key: const ValueKey('player-session'),
                  args: args,
                  orchestrator: orchestrator,
                  epgService: EpgService(clock: () => DateTime.utc(2026)),
                );
              },
            ),
          ),
        );
        await tester.pump();
        expect(adapter.loadCalls, hasLength(1));

        setArgs(() => args = channelB);
        await tester.pump();

        // Same URL, but a genuinely different channel — must still re-open.
        expect(adapter.loadCalls, hasLength(2));
      },
    );

    group('Comskip', () {
      PlaybackOrchestrator buildOrchestrator(FakePlayerAdapter adapter) {
        return PlaybackOrchestrator(
          platform: PlaybackPlatform.desktop,
          adapters: <PlaybackBackend, PlayerAdapter>{
            PlaybackBackend.desktopLibmpv: adapter,
          },
          transcodeGateway: FakeTranscodeGateway(),
        );
      }

      const recordingArgs = PlayerArgs(
        streamUrl: 'https://example.com/recording.mp4',
        title: 'Comskip Fixture',
        type: 'vod',
        metadata: <String, Object?>{
          'edl_url': 'https://example.com/recording/edl',
        },
      );

      testWidgets(
        'never fetches or shows comskip UI when edl_url is absent',
        (tester) async {
          final adapter = FakePlayerAdapter(
            capabilities: PlaybackCapabilities.desktopLibmpv,
            textureId: 1,
          );
          final orchestrator = buildOrchestrator(adapter);
          addTearDown(orchestrator.dispose);

          await tester.pumpWidget(
            MaterialApp(
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: PlayerScreen(
                args: const PlayerArgs(
                  streamUrl: 'https://example.com/recording.mp4',
                  title: 'No EDL Fixture',
                  type: 'vod',
                ),
                orchestrator: orchestrator,
                epgService: EpgService(clock: () => DateTime.utc(2026)),
              ),
            ),
          );
          await tester.pump();

          adapter.emitState(
            const PlaybackState(
              backend: PlaybackBackend.desktopLibmpv,
              status: PlaybackStatus.playing,
              position: Duration(seconds: 15),
              duration: Duration(minutes: 1),
            ),
          );
          await tester.pump();

          expect(adapter.seekCalls, isEmpty);
          expect(find.text('Skipped commercial'), findsNothing);
          expect(find.text('Skip commercial'), findsNothing);
        },
      );

      testWidgets(
        'auto-skip mode seeks past a segment and re-fires on re-entry',
        (tester) async {
          final adapter = FakePlayerAdapter(
            capabilities: PlaybackCapabilities.desktopLibmpv,
            textureId: 1,
          );
          final orchestrator = buildOrchestrator(adapter);
          addTearDown(orchestrator.dispose);

          await HttpOverrides.runZoned(
            () async {
              await tester.pumpWidget(
                MaterialApp(
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  home: PlayerScreen(
                    args: recordingArgs,
                    orchestrator: orchestrator,
                    epgService: EpgService(clock: () => DateTime.utc(2026)),
                    comskipSettings: ComskipSettings(),
                  ),
                ),
              );
              await tester.pump();

              adapter.emitState(
                const PlaybackState(
                  backend: PlaybackBackend.desktopLibmpv,
                  status: PlaybackStatus.playing,
                  position: Duration(seconds: 5),
                  duration: Duration(minutes: 1),
                ),
              );
              await tester.pump();
              expect(adapter.seekCalls, isEmpty);

              adapter.emitState(
                const PlaybackState(
                  backend: PlaybackBackend.desktopLibmpv,
                  status: PlaybackStatus.playing,
                  position: Duration(seconds: 12),
                  duration: Duration(minutes: 1),
                ),
              );
              await tester.pump();

              expect(adapter.seekCalls, [const Duration(seconds: 20)]);
              expect(find.text('Skipped commercial'), findsOneWidget);

              // Orchestrator confirms the seek — clears the pending guard.
              adapter.emitState(
                const PlaybackState(
                  backend: PlaybackBackend.desktopLibmpv,
                  status: PlaybackStatus.playing,
                  position: Duration(seconds: 20),
                  duration: Duration(minutes: 1),
                ),
              );
              await tester.pump();

              // Re-entry into the same segment after confirmation — must
              // RE-fire seek. The mechanism is stateless once the guard
              // clears: position is the source of truth.
              adapter.emitState(
                const PlaybackState(
                  backend: PlaybackBackend.desktopLibmpv,
                  status: PlaybackStatus.playing,
                  position: Duration(seconds: 15),
                  duration: Duration(minutes: 1),
                ),
              );
              await tester.pump();

              expect(adapter.seekCalls, [
                const Duration(seconds: 20),
                const Duration(seconds: 20),
              ]);
            },
            createHttpClient: (_) => _FakeHttpClient(
              jsonEncode([
                {'start': 10.0, 'end': 20.0},
              ]),
            ),
          );
        },
      );

      testWidgets(
        'prompt mode shows the skip control inside a segment and confirms on tap',
        (tester) async {
          final adapter = FakePlayerAdapter(
            capabilities: PlaybackCapabilities.desktopLibmpv,
            textureId: 1,
          );
          final orchestrator = buildOrchestrator(adapter);
          addTearDown(orchestrator.dispose);
          final settings = ComskipSettings();
          await settings.setAutoSkipEnabled(enabled: false);

          await HttpOverrides.runZoned(
            () async {
              await tester.pumpWidget(
                MaterialApp(
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  home: PlayerScreen(
                    args: recordingArgs,
                    orchestrator: orchestrator,
                    epgService: EpgService(clock: () => DateTime.utc(2026)),
                    comskipSettings: settings,
                  ),
                ),
              );
              await tester.pump();

              adapter.emitState(
                const PlaybackState(
                  backend: PlaybackBackend.desktopLibmpv,
                  status: PlaybackStatus.playing,
                  position: Duration(seconds: 12),
                  duration: Duration(minutes: 1),
                ),
              );
              await tester.pump();

              expect(adapter.seekCalls, isEmpty);
              expect(find.text('Skip commercial'), findsOneWidget);

              await tester.tap(find.text('Skip commercial'));
              await tester.pump();

              expect(adapter.seekCalls, [const Duration(seconds: 20)]);
              expect(find.text('Skip commercial'), findsNothing);
            },
            createHttpClient: (_) => _FakeHttpClient(
              jsonEncode([
                {'start': 10.0, 'end': 20.0},
              ]),
            ),
          );
        },
      );

      testWidgets(
        'prompt mode hides the skip control once playback exits the segment',
        (tester) async {
          final adapter = FakePlayerAdapter(
            capabilities: PlaybackCapabilities.desktopLibmpv,
            textureId: 1,
          );
          final orchestrator = buildOrchestrator(adapter);
          addTearDown(orchestrator.dispose);
          final settings = ComskipSettings();
          await settings.setAutoSkipEnabled(enabled: false);

          await HttpOverrides.runZoned(
            () async {
              await tester.pumpWidget(
                MaterialApp(
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  home: PlayerScreen(
                    args: recordingArgs,
                    orchestrator: orchestrator,
                    epgService: EpgService(clock: () => DateTime.utc(2026)),
                    comskipSettings: settings,
                  ),
                ),
              );
              await tester.pump();

              adapter.emitState(
                const PlaybackState(
                  backend: PlaybackBackend.desktopLibmpv,
                  status: PlaybackStatus.playing,
                  position: Duration(seconds: 12),
                  duration: Duration(minutes: 1),
                ),
              );
              await tester.pump();
              expect(find.text('Skip commercial'), findsOneWidget);

              adapter.emitState(
                const PlaybackState(
                  backend: PlaybackBackend.desktopLibmpv,
                  status: PlaybackStatus.playing,
                  position: Duration(seconds: 25),
                  duration: Duration(minutes: 1),
                ),
              );
              await tester.pump();

              expect(find.text('Skip commercial'), findsNothing);
              expect(adapter.seekCalls, isEmpty);
            },
            createHttpClient: (_) => _FakeHttpClient(
              jsonEncode([
                {'start': 10.0, 'end': 20.0},
              ]),
            ),
          );
        },
      );

      testWidgets(
        'falls back to confirm prompt when comskipSettings is null',
        (tester) async {
          final adapter = FakePlayerAdapter(
            capabilities: PlaybackCapabilities.desktopLibmpv,
            textureId: 1,
          );
          final orchestrator = buildOrchestrator(adapter);
          addTearDown(orchestrator.dispose);

          await HttpOverrides.runZoned(
            () async {
              await tester.pumpWidget(
                MaterialApp(
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  home: PlayerScreen(
                    args: recordingArgs,
                    orchestrator: orchestrator,
                    epgService: EpgService(clock: () => DateTime.utc(2026)),
                    // comskipSettings intentionally omitted — null fallback
                  ),
                ),
              );
              await tester.pump();

              adapter.emitState(
                const PlaybackState(
                  backend: PlaybackBackend.desktopLibmpv,
                  status: PlaybackStatus.playing,
                  position: Duration(seconds: 12),
                  duration: Duration(minutes: 1),
                ),
              );
              await tester.pump();

              expect(adapter.seekCalls, isEmpty);
              expect(find.text('Skip commercial'), findsOneWidget);

              await tester.tap(find.text('Skip commercial'));
              await tester.pump();

              expect(adapter.seekCalls, [const Duration(seconds: 20)]);
              expect(find.text('Skip commercial'), findsNothing);
            },
            createHttpClient: (_) => _FakeHttpClient(
              jsonEncode([
                {'start': 10.0, 'end': 20.0},
              ]),
            ),
          );
        },
      );

      testWidgets(
        're-fires auto-skip when user scrubs back into an already-skipped segment',
        (tester) async {
          final adapter = FakePlayerAdapter(
            capabilities: PlaybackCapabilities.desktopLibmpv,
            textureId: 1,
          );
          final orchestrator = buildOrchestrator(adapter);
          addTearDown(orchestrator.dispose);

          await HttpOverrides.runZoned(
            () async {
              await tester.pumpWidget(
                MaterialApp(
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  home: PlayerScreen(
                    args: recordingArgs,
                    orchestrator: orchestrator,
                    epgService: EpgService(clock: () => DateTime.utc(2026)),
                    comskipSettings: ComskipSettings(),
                  ),
                ),
              );
              await tester.pump();

              // Enter segment A (10–20) → auto-skip to 20.
              adapter.emitState(
                const PlaybackState(
                  backend: PlaybackBackend.desktopLibmpv,
                  status: PlaybackStatus.playing,
                  position: Duration(seconds: 12),
                  duration: Duration(minutes: 1),
                ),
              );
              await tester.pump();
              expect(adapter.seekCalls, [const Duration(seconds: 20)]);

              // Orchestrator confirms the seek — clears the pending guard.
              adapter.emitState(
                const PlaybackState(
                  backend: PlaybackBackend.desktopLibmpv,
                  status: PlaybackStatus.playing,
                  position: Duration(seconds: 20),
                  duration: Duration(minutes: 1),
                ),
              );
              await tester.pump();

              // User scrubs back to 15s — still inside segment A — must
              // RE-fire auto-skip. The mechanism is stateless once the guard
              // clears: position is the source of truth, no persistent
              // already-skipped tracking. Matches the web reference.
              adapter.emitState(
                const PlaybackState(
                  backend: PlaybackBackend.desktopLibmpv,
                  status: PlaybackStatus.playing,
                  position: Duration(seconds: 15),
                  duration: Duration(minutes: 1),
                ),
              );
              await tester.pump();
              expect(adapter.seekCalls, [
                const Duration(seconds: 20),
                const Duration(seconds: 20),
              ]);

              // Orchestrator confirms the second seek.
              adapter.emitState(
                const PlaybackState(
                  backend: PlaybackBackend.desktopLibmpv,
                  status: PlaybackStatus.playing,
                  position: Duration(seconds: 20),
                  duration: Duration(minutes: 1),
                ),
              );
              await tester.pump();

              // Advance into segment B (30–40) — must auto-skip to 40.
              adapter.emitState(
                const PlaybackState(
                  backend: PlaybackBackend.desktopLibmpv,
                  status: PlaybackStatus.playing,
                  position: Duration(seconds: 35),
                  duration: Duration(minutes: 1),
                ),
              );
              await tester.pump();
              expect(adapter.seekCalls, [
                const Duration(seconds: 20),
                const Duration(seconds: 20),
                const Duration(seconds: 40),
              ]);
            },
            createHttpClient: (_) => _FakeHttpClient(
              jsonEncode([
                {'start': 10.0, 'end': 20.0},
                {'start': 30.0, 'end': 40.0},
              ]),
            ),
          );
        },
      );

      testWidgets(
        'does not fire auto-skip while seek is in flight (orchestrator confirms at segment end)',
        (tester) async {
          final adapter = FakePlayerAdapter(
            capabilities: PlaybackCapabilities.desktopLibmpv,
            textureId: 1,
          );
          final orchestrator = buildOrchestrator(adapter);
          addTearDown(orchestrator.dispose);

          await HttpOverrides.runZoned(
            () async {
              await tester.pumpWidget(
                MaterialApp(
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  home: PlayerScreen(
                    args: recordingArgs,
                    orchestrator: orchestrator,
                    epgService: EpgService(clock: () => DateTime.utc(2026)),
                    comskipSettings: ComskipSettings(),
                  ),
                ),
              );
              await tester.pump();

              // Enter segment A (10–20) → auto-skip fires.
              adapter.emitState(
                const PlaybackState(
                  backend: PlaybackBackend.desktopLibmpv,
                  status: PlaybackStatus.playing,
                  position: Duration(seconds: 12),
                  duration: Duration(minutes: 1),
                ),
              );
              await tester.pump();
              expect(adapter.seekCalls, [const Duration(seconds: 20)]);

              // Orchestrator confirms seek — position now AT segment end.
              // _checkComskip reads _currentPosition=20, no segment matched,
              // no extra seek. This is the optimistic-bump mechanism: the
              // next [start, end) half-open interval check naturally
              // evaluates false at t=20.
              adapter.emitState(
                const PlaybackState(
                  backend: PlaybackBackend.desktopLibmpv,
                  status: PlaybackStatus.playing,
                  position: Duration(seconds: 20),
                  duration: Duration(minutes: 1),
                ),
              );
              await tester.pump();
              expect(adapter.seekCalls, [const Duration(seconds: 20)]);
            },
            createHttpClient: (_) => _FakeHttpClient(
              jsonEncode([
                {'start': 10.0, 'end': 20.0},
              ]),
            ),
          );
        },
      );

      testWidgets(
        'prompt-mode confirm does not flicker on stale orchestrator report after tap',
        (tester) async {
          final adapter = FakePlayerAdapter(
            capabilities: PlaybackCapabilities.desktopLibmpv,
            textureId: 1,
          );
          final orchestrator = buildOrchestrator(adapter);
          addTearDown(orchestrator.dispose);
          final settings = ComskipSettings();
          await settings.setAutoSkipEnabled(enabled: false);

          await HttpOverrides.runZoned(
            () async {
              await tester.pumpWidget(
                MaterialApp(
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  home: PlayerScreen(
                    args: recordingArgs,
                    orchestrator: orchestrator,
                    epgService: EpgService(clock: () => DateTime.utc(2026)),
                    comskipSettings: settings,
                  ),
                ),
              );
              await tester.pump();

              // Enter segment A (10–20) → prompt appears.
              adapter.emitState(
                const PlaybackState(
                  backend: PlaybackBackend.desktopLibmpv,
                  status: PlaybackStatus.playing,
                  position: Duration(seconds: 12),
                  duration: Duration(minutes: 1),
                ),
              );
              await tester.pump();
              expect(find.text('Skip commercial'), findsOneWidget);

              // User taps the button. _confirmComskipSkip now goes through
              // _fireComskipSeek: optimistic bump to 20 + pending target 20.
              await tester.tap(find.text('Skip commercial'));
              await tester.pump();
              expect(adapter.seekCalls, [const Duration(seconds: 20)]);
              expect(find.text('Skip commercial'), findsNothing);

              // Orchestrator's mid-seek stale report (still inside the
              // segment). The pending guard must keep _currentPosition at
              // the optimistic 20 — _checkComskip reads 20, the half-open
              // interval [10, 20) doesn't match, and the prompt does NOT
              // reappear. Pre-fix the prompt flickered back because the
              // old confirm path never set the pending guard.
              adapter.emitState(
                const PlaybackState(
                  backend: PlaybackBackend.desktopLibmpv,
                  status: PlaybackStatus.playing,
                  position: Duration(seconds: 15),
                  duration: Duration(minutes: 1),
                ),
              );
              await tester.pump();
              expect(find.text('Skip commercial'), findsNothing);
              expect(adapter.seekCalls, [const Duration(seconds: 20)]);
            },
            createHttpClient: (_) => _FakeHttpClient(
              jsonEncode([
                {'start': 10.0, 'end': 20.0},
              ]),
            ),
          );
        },
      );

      testWidgets(
        'prompt-mode confirm uses ceil() precision for sub-second EDL end',
        (tester) async {
          final adapter = FakePlayerAdapter(
            capabilities: PlaybackCapabilities.desktopLibmpv,
            textureId: 1,
          );
          final orchestrator = buildOrchestrator(adapter);
          addTearDown(orchestrator.dispose);
          final settings = ComskipSettings();
          await settings.setAutoSkipEnabled(enabled: false);

          await HttpOverrides.runZoned(
            () async {
              await tester.pumpWidget(
                MaterialApp(
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  home: PlayerScreen(
                    args: recordingArgs,
                    orchestrator: orchestrator,
                    epgService: EpgService(clock: () => DateTime.utc(2026)),
                    comskipSettings: settings,
                  ),
                ),
              );
              await tester.pump();

              // Segment ends at 20.08 — sub-second precision. Pre-fix the
              // prompt path used round() and seeked to Duration(seconds: 20),
              // i.e. 20.000s, which is still inside [10, 20.08) and would
              // re-match on the next tick. The shared _fireComskipSeek
              // helper now uses ceil() and seeks to 20.080s, exactly past
              // the half-open end.
              adapter.emitState(
                const PlaybackState(
                  backend: PlaybackBackend.desktopLibmpv,
                  status: PlaybackStatus.playing,
                  position: Duration(seconds: 12),
                  duration: Duration(minutes: 1),
                ),
              );
              await tester.pump();
              expect(find.text('Skip commercial'), findsOneWidget);

              await tester.tap(find.text('Skip commercial'));
              await tester.pump();

              expect(adapter.seekCalls, [
                const Duration(milliseconds: 20080),
              ]);
            },
            createHttpClient: (_) => _FakeHttpClient(
              jsonEncode([
                {'start': 10.0, 'end': 20.08},
              ]),
            ),
          );
        },
      );

      testWidgets(
        'manual seek clears pending auto-skip guard so user position is respected',
        (tester) async {
          final adapter = FakePlayerAdapter(
            capabilities: PlaybackCapabilities.desktopLibmpv,
            textureId: 1,
          );
          final orchestrator = buildOrchestrator(adapter);
          addTearDown(orchestrator.dispose);

          await HttpOverrides.runZoned(
            () async {
              await tester.pumpWidget(
                MaterialApp(
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  home: PlayerScreen(
                    args: recordingArgs,
                    orchestrator: orchestrator,
                    epgService: EpgService(clock: () => DateTime.utc(2026)),
                    comskipSettings: ComskipSettings(),
                  ),
                ),
              );
              await tester.pump();

              // Auto-skip fires: segment [10..20], emit 12 → seek to 20,
              // pending=20, _currentPosition=20.
              adapter.emitState(
                const PlaybackState(
                  backend: PlaybackBackend.desktopLibmpv,
                  status: PlaybackStatus.playing,
                  position: Duration(seconds: 12),
                  duration: Duration(minutes: 1),
                ),
              );
              await tester.pump();
              expect(adapter.seekCalls, [const Duration(seconds: 20)]);

              // User rewinds twice: 20 → 10 → 0. _seekTo clears the pending
              // guard (the user's deliberate new position must never be
              // guarded by the auto-skip's pending target). Pre-fix the
              // guard stayed set at 20 across these manual seeks.
              await tester.tap(find.byIcon(Icons.replay_10));
              await tester.pump();
              await tester.tap(find.byIcon(Icons.replay_10));
              await tester.pump();
              expect(adapter.seekCalls, [
                const Duration(seconds: 20),
                const Duration(seconds: 10),
                Duration.zero,
              ]);

              // Orchestrator's confirmation of the manual seek arrives at
              // 5s (mid-seek buffering). With the fix, _currentPosition is
              // accepted as 5 — display '0:05'. Pre-fix, 5 < pending(20)
              // would suppress the emit and the manual seek would silently
              // snap back to 0 from _seekTo — display '0:00'.
              adapter.emitState(
                const PlaybackState(
                  backend: PlaybackBackend.desktopLibmpv,
                  status: PlaybackStatus.playing,
                  position: Duration(seconds: 5),
                  duration: Duration(minutes: 1),
                ),
              );
              await tester.pump();
              expect(find.text('0:05'), findsOneWidget);
              expect(find.text('0:00'), findsNothing);
            },
            createHttpClient: (_) => _FakeHttpClient(
              jsonEncode([
                {'start': 10.0, 'end': 20.0},
              ]),
            ),
          );
        },
      );

      testWidgets(
        're-fires auto-skip when user restarts playback from the beginning',
        (tester) async {
          final adapter = FakePlayerAdapter(
            capabilities: PlaybackCapabilities.desktopLibmpv,
            textureId: 1,
          );
          final orchestrator = buildOrchestrator(adapter);
          addTearDown(orchestrator.dispose);

          await HttpOverrides.runZoned(
            () async {
              await tester.pumpWidget(
                MaterialApp(
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  home: PlayerScreen(
                    args: recordingArgs,
                    orchestrator: orchestrator,
                    epgService: EpgService(clock: () => DateTime.utc(2026)),
                    comskipSettings: ComskipSettings(),
                  ),
                ),
              );
              await tester.pump();

              // First playthrough: enter segment A (10–20) → auto-skip fires.
              adapter.emitState(
                const PlaybackState(
                  backend: PlaybackBackend.desktopLibmpv,
                  status: PlaybackStatus.playing,
                  position: Duration(seconds: 12),
                  duration: Duration(minutes: 1),
                ),
              );
              await tester.pump();
              expect(adapter.seekCalls, [const Duration(seconds: 20)]);

              // Orchestrator confirms seek at 20s.
              adapter.emitState(
                const PlaybackState(
                  backend: PlaybackBackend.desktopLibmpv,
                  status: PlaybackStatus.playing,
                  position: Duration(seconds: 20),
                  duration: Duration(minutes: 1),
                ),
              );
              await tester.pump();

              // User restarts from beginning — position now at 5s (outside).
              adapter.emitState(
                const PlaybackState(
                  backend: PlaybackBackend.desktopLibmpv,
                  status: PlaybackStatus.playing,
                  position: Duration(seconds: 5),
                  duration: Duration(minutes: 1),
                ),
              );
              await tester.pump();
              expect(adapter.seekCalls, [const Duration(seconds: 20)]);

              // Forward playback re-enters segment A — must auto-skip AGAIN.
              adapter.emitState(
                const PlaybackState(
                  backend: PlaybackBackend.desktopLibmpv,
                  status: PlaybackStatus.playing,
                  position: Duration(seconds: 15),
                  duration: Duration(minutes: 1),
                ),
              );
              await tester.pump();
              expect(adapter.seekCalls, [
                const Duration(seconds: 20),
                const Duration(seconds: 20),
              ]);
            },
            createHttpClient: (_) => _FakeHttpClient(
              jsonEncode([
                {'start': 10.0, 'end': 20.0},
              ]),
            ),
          );
        },
      );

      testWidgets(
        'auto-skip uses ceil() past sub-second EDL end (avoids stuck loop on real recordings)',
        (tester) async {
          final adapter = FakePlayerAdapter(
            capabilities: PlaybackCapabilities.desktopLibmpv,
            textureId: 1,
          );
          final orchestrator = buildOrchestrator(adapter);
          addTearDown(orchestrator.dispose);

          await HttpOverrides.runZoned(
            () async {
              await tester.pumpWidget(
                MaterialApp(
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  home: PlayerScreen(
                    args: recordingArgs,
                    orchestrator: orchestrator,
                    epgService: EpgService(clock: () => DateTime.utc(2026)),
                    comskipSettings: ComskipSettings(),
                  ),
                ),
              );
              await tester.pump();

              // Segment ends at 2284.08s — sub-second precision like a real
              // comskip EDL. Pre-fix this caused an infinite stuck loop
              // because round(2284.08) = 2284 → bump-to-2284 was still
              // inside [start, 2284.08) → re-match every tick. With ceil()
              // on the millisecond value we seek to 2284.080s, which is
              // exactly past the half-open end and so no longer matches.
              adapter.emitState(
                const PlaybackState(
                  backend: PlaybackBackend.desktopLibmpv,
                  status: PlaybackStatus.playing,
                  position: Duration(seconds: 2280),
                  duration: Duration(minutes: 60),
                ),
              );
              await tester.pump();
              expect(adapter.seekCalls, [
                const Duration(milliseconds: 2284080),
              ]);

              // Position 2285 confirmed — guard clears.
              adapter.emitState(
                const PlaybackState(
                  backend: PlaybackBackend.desktopLibmpv,
                  status: PlaybackStatus.playing,
                  position: Duration(seconds: 2285),
                  duration: Duration(minutes: 60),
                ),
              );
              await tester.pump();
              // No additional seek — stuck-loop is gone.
              expect(adapter.seekCalls, [
                const Duration(milliseconds: 2284080),
              ]);
            },
            createHttpClient: (_) => _FakeHttpClient(
              jsonEncode([
                {'start': 2074.12, 'end': 2284.08},
              ]),
            ),
          );
        },
      );

      testWidgets(
        'stale orchestrator position report during seek does not re-fire auto-skip',
        (tester) async {
          final adapter = FakePlayerAdapter(
            capabilities: PlaybackCapabilities.desktopLibmpv,
            textureId: 1,
          );
          final orchestrator = buildOrchestrator(adapter);
          addTearDown(orchestrator.dispose);

          await HttpOverrides.runZoned(
            () async {
              await tester.pumpWidget(
                MaterialApp(
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  home: PlayerScreen(
                    args: recordingArgs,
                    orchestrator: orchestrator,
                    epgService: EpgService(clock: () => DateTime.utc(2026)),
                    comskipSettings: ComskipSettings(),
                  ),
                ),
              );
              await tester.pump();

              // Enter segment A (10–20) → seek to 20, pending guard = 20.
              adapter.emitState(
                const PlaybackState(
                  backend: PlaybackBackend.desktopLibmpv,
                  status: PlaybackStatus.playing,
                  position: Duration(seconds: 12),
                  duration: Duration(minutes: 1),
                ),
              );
              await tester.pump();
              expect(adapter.seekCalls, [const Duration(seconds: 20)]);

              // Orchestrator's mid-seek position report LAGS back to 15s
              // (real seek hasn't completed yet). The pending-seek-target
              // guard must reject this — _currentPosition stays at the
              // bumped 20s and no second seek fires. Pre-fix this would
              // re-fire because the clobber pulled _currentPosition back
              // inside the segment.
              adapter.emitState(
                const PlaybackState(
                  backend: PlaybackBackend.desktopLibmpv,
                  status: PlaybackStatus.playing,
                  position: Duration(seconds: 15),
                  duration: Duration(minutes: 1),
                ),
              );
              await tester.pump();
              expect(adapter.seekCalls, [const Duration(seconds: 20)]);

              // Another stale report — still no re-fire.
              adapter.emitState(
                const PlaybackState(
                  backend: PlaybackBackend.desktopLibmpv,
                  status: PlaybackStatus.playing,
                  position: Duration(seconds: 18),
                  duration: Duration(minutes: 1),
                ),
              );
              await tester.pump();
              expect(adapter.seekCalls, [const Duration(seconds: 20)]);
            },
            createHttpClient: (_) => _FakeHttpClient(
              jsonEncode([
                {'start': 10.0, 'end': 20.0},
              ]),
            ),
          );
        },
      );

      testWidgets(
        'pending-seek-target guard clears on confirmation and next segment still fires',
        (tester) async {
          final adapter = FakePlayerAdapter(
            capabilities: PlaybackCapabilities.desktopLibmpv,
            textureId: 1,
          );
          final orchestrator = buildOrchestrator(adapter);
          addTearDown(orchestrator.dispose);

          await HttpOverrides.runZoned(
            () async {
              await tester.pumpWidget(
                MaterialApp(
                  localizationsDelegates:
                      AppLocalizations.localizationsDelegates,
                  supportedLocales: AppLocalizations.supportedLocales,
                  home: PlayerScreen(
                    args: recordingArgs,
                    orchestrator: orchestrator,
                    epgService: EpgService(clock: () => DateTime.utc(2026)),
                    comskipSettings: ComskipSettings(),
                  ),
                ),
              );
              await tester.pump();

              // Enter segment A (10–20) → seek to 20, pending = 20.
              adapter.emitState(
                const PlaybackState(
                  backend: PlaybackBackend.desktopLibmpv,
                  status: PlaybackStatus.playing,
                  position: Duration(seconds: 12),
                  duration: Duration(minutes: 1),
                ),
              );
              await tester.pump();
              expect(adapter.seekCalls, [const Duration(seconds: 20)]);

              // Orchestrator genuinely catches up past the target —
              // 20 >= 20, guard clears, position is accepted.
              adapter.emitState(
                const PlaybackState(
                  backend: PlaybackBackend.desktopLibmpv,
                  status: PlaybackStatus.playing,
                  position: Duration(seconds: 20),
                  duration: Duration(minutes: 1),
                ),
              );
              await tester.pump();
              expect(adapter.seekCalls, [const Duration(seconds: 20)]);

              // Advance into segment B (30–40) — must auto-skip to 40.
              // If the guard were stuck or the mechanism broken, this
              // wouldn't fire.
              adapter.emitState(
                const PlaybackState(
                  backend: PlaybackBackend.desktopLibmpv,
                  status: PlaybackStatus.playing,
                  position: Duration(seconds: 35),
                  duration: Duration(minutes: 1),
                ),
              );
              await tester.pump();
              expect(adapter.seekCalls, [
                const Duration(seconds: 20),
                const Duration(seconds: 40),
              ]);
            },
            createHttpClient: (_) => _FakeHttpClient(
              jsonEncode([
                {'start': 10.0, 'end': 20.0},
                {'start': 30.0, 'end': 40.0},
              ]),
            ),
          );
        },
      );

      testWidgets(
        'rewrites a localhost edl_url host to the Xtream server before fetching',
        (tester) async {
          final adapter = FakePlayerAdapter(
            capabilities: PlaybackCapabilities.desktopLibmpv,
            textureId: 1,
          );
          final orchestrator = buildOrchestrator(adapter);
          addTearDown(orchestrator.dispose);

          final xtreamService = XtreamService(
            transport: (request) async {
              if (request.action == null) {
                return {
                  'user_info': {'auth': 1, 'status': 'Active'},
                  'm3u_editor': {'version': 'fixture'},
                };
              }
              return <String, Object?>{};
            },
          );
          await xtreamService.authenticate(
            const UserCredentials(
              server: 'https://xtream.example',
              username: 'demo',
              password: 'secret',
            ),
          );

          final httpClient = _FakeHttpClient(
            jsonEncode([
              {'start': 10.0, 'end': 20.0},
            ]),
          );

          await HttpOverrides.runZoned(() async {
            await tester.pumpWidget(
              MaterialApp(
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: PlayerScreen(
                  args: const PlayerArgs(
                    streamUrl: 'https://example.com/recording.mp4',
                    title: 'Localhost EDL Fixture',
                    type: 'vod',
                    metadata: <String, Object?>{
                      'edl_url': 'http://localhost/dvr/some/path/edl',
                    },
                  ),
                  orchestrator: orchestrator,
                  epgService: EpgService(clock: () => DateTime.utc(2026)),
                  xtreamService: xtreamService,
                  comskipSettings: ComskipSettings(),
                ),
              ),
            );
            await tester.pump();

            // Give the fire-and-forget EDL fetch a chance to settle.
            for (var i = 0; i < 10; i++) {
              await tester.pump(const Duration(milliseconds: 10));
            }

            expect(httpClient.requestedUrls, isNotEmpty);
            final fetched = httpClient.requestedUrls.single;
            expect(fetched.scheme, 'https');
            expect(fetched.host, 'xtream.example');
            expect(fetched.path, '/dvr/some/path/edl');
            expect(fetched.hasPort, isFalse);
          }, createHttpClient: (_) => httpClient);
        },
      );

      testWidgets(
        'leaves a non-localhost edl_url host untouched',
        (tester) async {
          final adapter = FakePlayerAdapter(
            capabilities: PlaybackCapabilities.desktopLibmpv,
            textureId: 1,
          );
          final orchestrator = buildOrchestrator(adapter);
          addTearDown(orchestrator.dispose);

          final xtreamService = XtreamService(
            transport: (request) async {
              if (request.action == null) {
                return {
                  'user_info': {'auth': 1, 'status': 'Active'},
                  'm3u_editor': {'version': 'fixture'},
                };
              }
              return <String, Object?>{};
            },
          );
          await xtreamService.authenticate(
            const UserCredentials(
              server: 'https://xtream.example',
              username: 'demo',
              password: 'secret',
            ),
          );

          final httpClient = _FakeHttpClient(
            jsonEncode([
              {'start': 10.0, 'end': 20.0},
            ]),
          );

          await HttpOverrides.runZoned(() async {
            await tester.pumpWidget(
              MaterialApp(
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: PlayerScreen(
                  args: const PlayerArgs(
                    streamUrl: 'https://example.com/recording.mp4',
                    title: 'Real Host EDL Fixture',
                    type: 'vod',
                    metadata: <String, Object?>{
                      'edl_url': 'https://m3u.bearald.com/dvr/real/path/edl',
                    },
                  ),
                  orchestrator: orchestrator,
                  epgService: EpgService(clock: () => DateTime.utc(2026)),
                  xtreamService: xtreamService,
                  comskipSettings: ComskipSettings(),
                ),
              ),
            );
            await tester.pump();

            for (var i = 0; i < 10; i++) {
              await tester.pump(const Duration(milliseconds: 10));
            }

            expect(httpClient.requestedUrls, isNotEmpty);
            final fetched = httpClient.requestedUrls.single;
            expect(fetched.scheme, 'https');
            expect(fetched.host, 'm3u.bearald.com');
            expect(fetched.path, '/dvr/real/path/edl');
          }, createHttpClient: (_) => httpClient);
        },
      );

      testWidgets(
        'fast path with edl_url in metadata does not call XtreamService',
        (tester) async {
          final adapter = FakePlayerAdapter(
            capabilities: PlaybackCapabilities.desktopLibmpv,
            textureId: 1,
          );
          final orchestrator = buildOrchestrator(adapter);
          addTearDown(orchestrator.dispose);

          final requestedActions = <String>[];
          final xtreamService = XtreamService(
            transport: (request) async {
              if (request.action != null) {
                requestedActions.add(request.action!);
              }
              if (request.action == null) {
                return {
                  'user_info': {'auth': 1, 'status': 'Active'},
                  'm3u_editor': {'version': 'fixture'},
                };
              }
              return <String, Object?>{};
            },
          );
          await xtreamService.authenticate(
            const UserCredentials(
              server: 'https://xtream.example',
              username: 'demo',
              password: 'secret',
            ),
          );

          final httpClient = _FakeHttpClient(
            jsonEncode([
              {'start': 10.0, 'end': 20.0},
            ]),
          );

          await HttpOverrides.runZoned(() async {
            await tester.pumpWidget(
              MaterialApp(
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: PlayerScreen(
                  args: recordingArgs,
                  orchestrator: orchestrator,
                  epgService: EpgService(clock: () => DateTime.utc(2026)),
                  xtreamService: xtreamService,
                  hasDvrFeature: true,
                  comskipSettings: ComskipSettings(),
                ),
              ),
            );
            await tester.pump();

            for (var i = 0; i < 10; i++) {
              await tester.pump(const Duration(milliseconds: 10));
            }

            expect(
              requestedActions.contains('get_vod_info'),
              isFalse,
              reason:
                  'Fast path must not call getVodInfo when metadata has edl_url',
            );
            expect(
              requestedActions.contains('get_series_info'),
              isFalse,
              reason:
                  'Fast path must not call getSeriesInfo when metadata has edl_url',
            );
            expect(httpClient.requestedUrls.single.host, 'example.com');
            expect(
              httpClient.requestedUrls.single.path,
              '/recording/edl',
            );
          }, createHttpClient: (_) => httpClient);
        },
      );

      testWidgets(
        'VOD fallback resolves edl_url via getVodInfo when metadata lacks it',
        (tester) async {
          final adapter = FakePlayerAdapter(
            capabilities: PlaybackCapabilities.desktopLibmpv,
            textureId: 1,
          );
          final orchestrator = buildOrchestrator(adapter);
          addTearDown(orchestrator.dispose);

          final xtreamService = XtreamService(
            transport: (request) async {
              if (request.action == null) {
                return {
                  'user_info': {'auth': 1, 'status': 'Active'},
                  'm3u_editor': {'version': 'fixture'},
                };
              }
              if (request.action == 'get_vod_info') {
                return <String, Object?>{
                  'info': {
                    'edl_url': 'https://xtream.example/dvr/vod/edl',
                  },
                };
              }
              return <String, Object?>{};
            },
          );
          await xtreamService.authenticate(
            const UserCredentials(
              server: 'https://xtream.example',
              username: 'demo',
              password: 'secret',
            ),
          );

          final httpClient = _FakeHttpClient(
            jsonEncode([
              {'start': 30.0, 'end': 60.0},
            ]),
          );

          await HttpOverrides.runZoned(() async {
            await tester.pumpWidget(
              MaterialApp(
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: PlayerScreen(
                  args: const PlayerArgs(
                    streamUrl: 'https://xtream.example/recording.mp4',
                    title: 'VOD Fallback Fixture',
                    type: 'vod',
                    streamId: 4242,
                  ),
                  orchestrator: orchestrator,
                  epgService: EpgService(clock: () => DateTime.utc(2026)),
                  xtreamService: xtreamService,
                  hasDvrFeature: true,
                  comskipSettings: ComskipSettings(),
                ),
              ),
            );
            await tester.pump();

            for (var i = 0; i < 10; i++) {
              await tester.pump(const Duration(milliseconds: 10));
            }

            expect(httpClient.requestedUrls, isNotEmpty);
            expect(
              httpClient.requestedUrls.single.toString(),
              'https://xtream.example/dvr/vod/edl',
            );
          }, createHttpClient: (_) => httpClient);
        },
      );

      testWidgets(
        'series fallback matches episode by id and fetches its edl_url',
        (tester) async {
          final adapter = FakePlayerAdapter(
            capabilities: PlaybackCapabilities.desktopLibmpv,
            textureId: 1,
          );
          final orchestrator = buildOrchestrator(adapter);
          addTearDown(orchestrator.dispose);

          final xtreamService = XtreamService(
            transport: (request) async {
              if (request.action == null) {
                return {
                  'user_info': {'auth': 1, 'status': 'Active'},
                  'm3u_editor': {'version': 'fixture'},
                };
              }
              if (request.action == 'get_series_info') {
                return <String, Object?>{
                  'seasons': <Map<String, Object?>>[],
                  'info': <String, Object?>{},
                  'episodes': <String, Object?>{
                    '1': <Map<String, Object?>>[
                      <String, Object?>{
                        'id': '99',
                        'episode_num': 1,
                        'title': 'Not This One',
                        'container_extension': 'mp4',
                        'season': 1,
                      },
                      <String, Object?>{
                        'id': '123',
                        'episode_num': 2,
                        'title': 'Target Episode',
                        'container_extension': 'mp4',
                        'season': 1,
                        'edl_url': 'https://xtream.example/dvr/series/ep-edl',
                      },
                    ],
                  },
                };
              }
              return <String, Object?>{};
            },
          );
          await xtreamService.authenticate(
            const UserCredentials(
              server: 'https://xtream.example',
              username: 'demo',
              password: 'secret',
            ),
          );

          final httpClient = _FakeHttpClient(
            jsonEncode([
              {'start': 90.0, 'end': 120.0},
            ]),
          );

          await HttpOverrides.runZoned(() async {
            await tester.pumpWidget(
              MaterialApp(
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: PlayerScreen(
                  args: const PlayerArgs(
                    streamUrl: 'https://xtream.example/series/123.mp4',
                    title: 'Series Fallback Fixture',
                    type: 'series',
                    streamId: 123,
                    seriesId: 7,
                  ),
                  orchestrator: orchestrator,
                  epgService: EpgService(clock: () => DateTime.utc(2026)),
                  xtreamService: xtreamService,
                  hasDvrFeature: true,
                  comskipSettings: ComskipSettings(),
                ),
              ),
            );
            await tester.pump();

            for (var i = 0; i < 10; i++) {
              await tester.pump(const Duration(milliseconds: 10));
            }

            expect(httpClient.requestedUrls, isNotEmpty);
            expect(
              httpClient.requestedUrls.single.toString(),
              'https://xtream.example/dvr/series/ep-edl',
            );
          }, createHttpClient: (_) => httpClient);
        },
      );
      testWidgets(
        'gate closed: hasDvrFeature false issues no XtreamService call',
        (tester) async {
          final adapter = FakePlayerAdapter(
            capabilities: PlaybackCapabilities.desktopLibmpv,
            textureId: 1,
          );
          final orchestrator = buildOrchestrator(adapter);
          addTearDown(orchestrator.dispose);

          final requestedActions = <String>[];
          final xtreamService = XtreamService(
            transport: (request) async {
              if (request.action != null) {
                requestedActions.add(request.action!);
              }
              if (request.action == null) {
                return {
                  'user_info': {'auth': 1, 'status': 'Active'},
                  'm3u_editor': {'version': 'fixture'},
                };
              }
              return <String, Object?>{};
            },
          );
          await xtreamService.authenticate(
            const UserCredentials(
              server: 'https://xtream.example',
              username: 'demo',
              password: 'secret',
            ),
          );

          final httpClient = _FakeHttpClient(
            jsonEncode([
              {'start': 10.0, 'end': 20.0},
            ]),
          );

          await HttpOverrides.runZoned(() async {
            await tester.pumpWidget(
              MaterialApp(
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: PlayerScreen(
                  args: const PlayerArgs(
                    streamUrl: 'https://xtream.example/recording.mp4',
                    title: 'Gate Closed Fixture',
                    type: 'vod',
                    streamId: 4242,
                  ),
                  orchestrator: orchestrator,
                  epgService: EpgService(clock: () => DateTime.utc(2026)),
                  xtreamService: xtreamService,
                  comskipSettings: ComskipSettings(),
                ),
              ),
            );
            await tester.pump();

            for (var i = 0; i < 10; i++) {
              await tester.pump(const Duration(milliseconds: 10));
            }

            expect(
              requestedActions.contains('get_vod_info'),
              isFalse,
              reason:
                  'Gate must suppress getVodInfo when hasDvrFeature is false',
            );
            expect(
              requestedActions.contains('get_series_info'),
              isFalse,
              reason:
                  'Gate must suppress getSeriesInfo when hasDvrFeature is false',
            );
            expect(httpClient.requestedUrls, isEmpty);
            expect(find.text('Skipped commercial'), findsNothing);
            expect(find.text('Skip commercial'), findsNothing);
          }, createHttpClient: (_) => httpClient);
        },
      );

      testWidgets(
        'fail-open: server returns no edl_url yields no comskip UI and no crash',
        (tester) async {
          final adapter = FakePlayerAdapter(
            capabilities: PlaybackCapabilities.desktopLibmpv,
            textureId: 1,
          );
          final orchestrator = buildOrchestrator(adapter);
          addTearDown(orchestrator.dispose);

          final xtreamService = XtreamService(
            transport: (request) async {
              if (request.action == null) {
                return {
                  'user_info': {'auth': 1, 'status': 'Active'},
                  'm3u_editor': {'version': 'fixture'},
                };
              }
              if (request.action == 'get_vod_info') {
                return <String, Object?>{'info': <String, Object?>{}};
              }
              return <String, Object?>{};
            },
          );
          await xtreamService.authenticate(
            const UserCredentials(
              server: 'https://xtream.example',
              username: 'demo',
              password: 'secret',
            ),
          );

          final httpClient = _FakeHttpClient(
            jsonEncode([
              {'start': 10.0, 'end': 20.0},
            ]),
          );

          await HttpOverrides.runZoned(() async {
            await tester.pumpWidget(
              MaterialApp(
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: PlayerScreen(
                  args: const PlayerArgs(
                    streamUrl: 'https://xtream.example/recording.mp4',
                    title: 'Fail-open Fixture',
                    type: 'vod',
                    streamId: 4242,
                  ),
                  orchestrator: orchestrator,
                  epgService: EpgService(clock: () => DateTime.utc(2026)),
                  xtreamService: xtreamService,
                  hasDvrFeature: true,
                  comskipSettings: ComskipSettings(),
                ),
              ),
            );
            await tester.pump();

            for (var i = 0; i < 10; i++) {
              await tester.pump(const Duration(milliseconds: 10));
            }

            expect(httpClient.requestedUrls, isEmpty);
            expect(adapter.seekCalls, isEmpty);
            expect(find.text('Skipped commercial'), findsNothing);
            expect(find.text('Skip commercial'), findsNothing);
          }, createHttpClient: (_) => httpClient);
        },
      );

      testWidgets(
        'loopback rewrite applies to a fallback-resolved edl_url',
        (tester) async {
          final adapter = FakePlayerAdapter(
            capabilities: PlaybackCapabilities.desktopLibmpv,
            textureId: 1,
          );
          final orchestrator = buildOrchestrator(adapter);
          addTearDown(orchestrator.dispose);

          final xtreamService = XtreamService(
            transport: (request) async {
              if (request.action == null) {
                return {
                  'user_info': {'auth': 1, 'status': 'Active'},
                  'm3u_editor': {'version': 'fixture'},
                };
              }
              if (request.action == 'get_vod_info') {
                return <String, Object?>{
                  'info': {
                    'edl_url': 'http://localhost/dvr/fallback/edl',
                  },
                };
              }
              return <String, Object?>{};
            },
          );
          await xtreamService.authenticate(
            const UserCredentials(
              server: 'https://xtream.example',
              username: 'demo',
              password: 'secret',
            ),
          );

          final httpClient = _FakeHttpClient(
            jsonEncode([
              {'start': 10.0, 'end': 20.0},
            ]),
          );

          await HttpOverrides.runZoned(() async {
            await tester.pumpWidget(
              MaterialApp(
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: PlayerScreen(
                  args: const PlayerArgs(
                    streamUrl: 'https://xtream.example/recording.mp4',
                    title: 'Loopback Fallback Fixture',
                    type: 'vod',
                    streamId: 4242,
                  ),
                  orchestrator: orchestrator,
                  epgService: EpgService(clock: () => DateTime.utc(2026)),
                  xtreamService: xtreamService,
                  hasDvrFeature: true,
                  comskipSettings: ComskipSettings(),
                ),
              ),
            );
            await tester.pump();

            for (var i = 0; i < 10; i++) {
              await tester.pump(const Duration(milliseconds: 10));
            }

            expect(httpClient.requestedUrls, isNotEmpty);
            final fetched = httpClient.requestedUrls.single;
            expect(fetched.scheme, 'https');
            expect(fetched.host, 'xtream.example');
            expect(fetched.path, '/dvr/fallback/edl');
          }, createHttpClient: (_) => httpClient);
        },
      );
    });
  });
}

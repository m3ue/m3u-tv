import 'dart:async';

import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/player/epg_overlay.dart';
import 'package:m3u_tv/features/player/format_time.dart';
import 'package:m3u_tv/features/player/playback_controls.dart';
import 'package:m3u_tv/features/player/player_screen.dart';
import 'package:m3u_tv/features/player/resume_prompt.dart';
import 'package:m3u_tv/features/player/track_selector.dart';
import 'package:m3u_tv/navigation/app_router.dart';
import 'package:m3u_tv/playback/playback_capabilities.dart';
import 'package:m3u_tv/playback/playback_orchestrator.dart';
import 'package:m3u_tv/playback/player_adapter.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/epg_service.dart';
import 'package:m3u_tv/services/xtream_service.dart';

import 'fake_player_adapter.dart';
import 'fake_transcode_gateway.dart';

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

    testWidgets('shows audio track selector and applies selection', (
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
              streamUrl: 'https://example.com/movie.m3u8',
              title: 'Multi Audio Fixture',
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
          duration: Duration(hours: 1),
          audioTracks: <PlaybackTrack>[
            PlaybackTrack(id: 'audio-eng', label: 'English', language: 'eng'),
            PlaybackTrack(id: 'audio-spa', label: 'Spanish', language: 'spa'),
          ],
          selectedAudioTrackId: 'audio-eng',
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.audiotrack), findsOneWidget);
      await tester.tap(find.byIcon(Icons.audiotrack));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Spanish').last);
      await tester.pumpAndSettle();

      expect(adapter.setAudioTrackCalls, <String?>['audio-spa']);
    });

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
  });
}

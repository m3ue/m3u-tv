import 'dart:async';

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
            name: 'iPhone MediaKit',
            platform: PlaybackPlatform.apple,
            capabilities: PlaybackCapabilities.appleMediaKit,
            size: const Size(430, 932),
          ),
          (
            name: 'macOS MediaKit',
            platform: PlaybackPlatform.desktop,
            capabilities: PlaybackCapabilities.desktopMediaKit,
            size: const Size(1440, 900),
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
  });
}

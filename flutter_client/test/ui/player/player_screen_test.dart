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
import 'package:m3u_tv/services/epg_service.dart';

import 'fake_player_adapter.dart';
import 'fake_transcode_gateway.dart';

void main() {
  group('formatTime', () {
    test('formats seconds as M:SS', () {
      expect(formatTime(const Duration()), '0:00');
      expect(formatTime(const Duration(seconds: 5)), '0:05');
      expect(formatTime(const Duration(minutes: 5, seconds: 30)), '5:30');
    });

    test('formats hours as H:MM:SS', () {
      expect(formatTime(const Duration(hours: 1, minutes: 30)), '1:30:00');
      expect(
          formatTime(const Duration(hours: 2, minutes: 15, seconds: 45)),
          '2:15:45');
    });

    test('handles zero duration', () {
      expect(formatTime(Duration.zero), '0:00');
    });
  });

  group('PlaybackControls', () {
    testWidgets('shows play button when paused', (tester) async {
      await tester.pumpWidget(MaterialApp(
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
      ));
      expect(find.byIcon(Icons.play_arrow), findsOneWidget);
    });

    testWidgets('shows pause button when playing', (tester) async {
      await tester.pumpWidget(MaterialApp(
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
      ));
      expect(find.byIcon(Icons.pause), findsOneWidget);
    });

    testWidgets('calls onPlayPause when play/pause button tapped',
        (tester) async {
      var tapped = false;
      await tester.pumpWidget(MaterialApp(
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
      ));
      await tester.tap(find.byIcon(Icons.play_arrow));
      expect(tapped, isTrue);
    });

    testWidgets('hides seek controls for live content', (tester) async {
      await tester.pumpWidget(MaterialApp(
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
      ));
      expect(find.byIcon(Icons.replay_10), findsNothing);
      expect(find.byIcon(Icons.forward_10), findsNothing);
    });

    testWidgets('shows seek controls for VOD content', (tester) async {
      await tester.pumpWidget(MaterialApp(
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
      ));
      expect(find.byIcon(Icons.replay_10), findsOneWidget);
      expect(find.byIcon(Icons.forward_10), findsOneWidget);
    });

    testWidgets('displays formatted time', (tester) async {
      await tester.pumpWidget(MaterialApp(
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
      ));
      expect(find.text('5:30'), findsOneWidget);
      expect(find.text('1:30:00'), findsOneWidget);
    });

    testWidgets('calls onBack when back button tapped', (tester) async {
      var backPressed = false;
      await tester.pumpWidget(MaterialApp(
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
      ));
      await tester.tap(find.byIcon(Icons.arrow_back));
      expect(backPressed, isTrue);
    });

    testWidgets('shows fallback reason badge when provided', (tester) async {
      await tester.pumpWidget(MaterialApp(
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
      ));
      expect(find.text('Server transcode active'), findsOneWidget);
    });
  });

  group('TrackSelector', () {
    testWidgets('shows audio track selector button', (tester) async {
      await tester.pumpWidget(MaterialApp(
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
      ));
      expect(find.byIcon(Icons.audiotrack), findsOneWidget);
    });

    testWidgets('shows subtitle track selector button', (tester) async {
      await tester.pumpWidget(MaterialApp(
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
      ));
      expect(find.byIcon(Icons.subtitles), findsOneWidget);
    });

    testWidgets('opens audio track dialog on tap', (tester) async {
      await tester.pumpWidget(MaterialApp(
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
      ));
      await tester.tap(find.byIcon(Icons.audiotrack));
      await tester.pumpAndSettle();
      expect(find.text('English'), findsWidgets);
    });

    testWidgets('opens subtitle track dialog on tap', (tester) async {
      await tester.pumpWidget(MaterialApp(
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
      ));
      await tester.tap(find.byIcon(Icons.subtitles));
      await tester.pumpAndSettle();
      expect(find.text('English CC'), findsWidgets);
    });

    testWidgets('calls onAudioTrackSelected when track chosen', (tester) async {
      String? selectedTrack;
      await tester.pumpWidget(MaterialApp(
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
      ));
      await tester.tap(find.byIcon(Icons.audiotrack));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Spanish').last);
      await tester.pumpAndSettle();
      expect(selectedTrack, '2');
    });
  });

  group('EpgOverlay', () {
    testWidgets('shows LIVE badge for live content', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: EpgOverlay(
          currentTitle: 'Live News',
          currentProgress: 0.5,
          nextTitle: 'Weather Update',
        ),
      ));
      expect(find.text('LIVE'), findsOneWidget);
      expect(find.text('Live News'), findsOneWidget);
    });

    testWidgets('shows progress bar', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: EpgOverlay(
          currentTitle: 'Live Show',
          currentProgress: 0.75,
          nextTitle: 'Next Show',
        ),
      ));
      expect(find.byType(EpgProgressBar), findsOneWidget);
    });

    testWidgets('shows next program title', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: EpgOverlay(
          currentTitle: 'Current Show',
          currentProgress: 0.3,
          nextTitle: 'Up Next Show',
        ),
      ));
      expect(find.text('Next: Up Next Show'), findsOneWidget);
    });

    testWidgets('hides next title when null', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: EpgOverlay(
          currentTitle: 'Current Show',
          currentProgress: 0.3,
        ),
      ));
      expect(find.byType(EpgOverlay), findsOneWidget);
      expect(find.textContaining('Next:'), findsNothing);
    });
  });

  group('ResumePrompt', () {
    testWidgets('shows resume and start over options', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: ResumePrompt(
          position: const Duration(minutes: 5, seconds: 30),
          onResume: () {},
          onStartOver: () {},
        ),
      ));
      expect(find.text('Resume'), findsOneWidget);
      expect(find.text('Start Over'), findsOneWidget);
    });

    testWidgets('shows formatted position in prompt', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: ResumePrompt(
          position: const Duration(minutes: 5, seconds: 30),
          onResume: () {},
          onStartOver: () {},
        ),
      ));
      expect(find.textContaining('5:30'), findsOneWidget);
    });

    testWidgets('calls onResume when resume button tapped', (tester) async {
      var resumed = false;
      await tester.pumpWidget(MaterialApp(
        home: ResumePrompt(
          position: const Duration(minutes: 5),
          onResume: () => resumed = true,
          onStartOver: () {},
        ),
      ));
      await tester.tap(find.text('Resume'));
      expect(resumed, isTrue);
    });

    testWidgets('calls onStartOver when start over button tapped',
        (tester) async {
      var startedOver = false;
      await tester.pumpWidget(MaterialApp(
        home: ResumePrompt(
          position: const Duration(minutes: 5),
          onResume: () {},
          onStartOver: () => startedOver = true,
        ),
      ));
      await tester.tap(find.text('Start Over'));
      expect(startedOver, isTrue);
    });
  });

  group('PlayerScreen', () {
    testWidgets('backs out of the route when playback error is visible',
        (tester) async {
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

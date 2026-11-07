import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/player/player_screen.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/navigation/app_router.dart';
import 'package:m3u_tv/playback/playback_capabilities.dart';
import 'package:m3u_tv/playback/playback_orchestrator.dart';
import 'package:m3u_tv/playback/player_adapter.dart';
import 'package:m3u_tv/services/epg_service.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_player_adapter.dart';
import 'fake_transcode_gateway.dart';

void main() {
  late FakePlayerAdapter adapter;
  late int closes;

  Future<void> pumpPlayer(
    WidgetTester tester, {
    PlaybackStatus status = PlaybackStatus.playing,
  }) async {
    closes = 0;
    adapter = FakePlayerAdapter(
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
            title: 'Movie Fixture',
            type: 'vod',
          ),
          orchestrator: orchestrator,
          epgService: EpgService(clock: () => DateTime.utc(2026)),
          onClose: () => closes++,
        ),
      ),
    );
    await tester.pump();
    adapter.emitState(
      PlaybackState(
        backend: PlaybackBackend.desktopLibmpv,
        status: status,
        duration: const Duration(hours: 1),
      ),
    );
    await tester.pump();
    adapter
      ..playCallCount = 0
      ..pauseCallCount = 0;
  }

  /// Whether the key was consumed, so it can't reach Android's MediaSession.
  Future<bool> press(WidgetTester tester, LogicalKeyboardKey key) async {
    final handled = await tester.sendKeyEvent(key);
    await tester.pump();
    return handled;
  }

  testWidgets('Pause pauses, and pressing it again does not resume', (
    tester,
  ) async {
    await pumpPlayer(tester);

    expect(await press(tester, LogicalKeyboardKey.mediaPause), isTrue);
    expect(adapter.pauseCallCount, 1);
    expect(await press(tester, LogicalKeyboardKey.mediaPause), isTrue);
    expect(adapter.pauseCallCount, 2);
    expect(adapter.playCallCount, 0);
  });

  testWidgets('Play resumes and never pauses', (tester) async {
    await pumpPlayer(tester, status: PlaybackStatus.paused);

    expect(await press(tester, LogicalKeyboardKey.mediaPlay), isTrue);
    expect(adapter.playCallCount, 1);
    expect(adapter.pauseCallCount, 0);
  });

  testWidgets('Play/Pause toggles once per press, however long it is held', (
    tester,
  ) async {
    await pumpPlayer(tester);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.mediaPlayPause);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.mediaPlayPause);
    await tester.sendKeyRepeatEvent(LogicalKeyboardKey.mediaPlayPause);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.mediaPlayPause);
    await tester.pump();

    expect(adapter.pauseCallCount, 1);
    expect(adapter.playCallCount, 0);
  });

  testWidgets('Stop leaves the player without opening the controls first', (
    tester,
  ) async {
    await pumpPlayer(tester);

    expect(await press(tester, LogicalKeyboardKey.mediaStop), isTrue);

    expect(closes, 1);
  });

  testWidgets('Stop leaves in one press with the controls open', (
    tester,
  ) async {
    await pumpPlayer(tester);
    // Any other key opens the controls.
    await press(tester, LogicalKeyboardKey.mediaPause);
    await tester.pump(const Duration(milliseconds: 300));

    await press(tester, LogicalKeyboardKey.mediaStop);

    expect(closes, 1);
  });

  testWidgets('transport keys are released when the player closes', (
    tester,
  ) async {
    await pumpPlayer(tester);
    await tester.pumpWidget(const SizedBox.shrink());
    final pausesBefore = adapter.pauseCallCount;

    expect(await tester.sendKeyEvent(LogicalKeyboardKey.mediaPause), isFalse);

    expect(adapter.pauseCallCount, pausesBefore);
  });
}

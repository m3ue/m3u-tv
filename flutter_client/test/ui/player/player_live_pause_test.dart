import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/player/player_screen.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/navigation/app_router.dart';
import 'package:m3u_tv/playback/now_playing_bridge.dart';
import 'package:m3u_tv/playback/playback_capabilities.dart';
import 'package:m3u_tv/playback/playback_orchestrator.dart';
import 'package:m3u_tv/playback/player_adapter.dart';
import 'package:m3u_tv/services/epg_service.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_player_adapter.dart';
import 'fake_transcode_gateway.dart';

void main() {
  const backend = PlaybackBackend.desktopLibmpv;

  Future<FakePlayerAdapter> pumpLivePlayer(
    WidgetTester tester, {
    NowPlayingBridge? nowPlayingBridge,
    bool pause = true,
  }) async {
    final adapter = FakePlayerAdapter(
      capabilities: PlaybackCapabilities.desktopLibmpv,
      textureId: 7,
    );
    final orchestrator = PlaybackOrchestrator(
      platform: PlaybackPlatform.desktop,
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
            streamUrl: 'https://example.com/live.ts',
            title: 'Live Fixture',
            type: 'live',
          ),
          orchestrator: orchestrator,
          epgService: EpgService(clock: () => DateTime.utc(2026)),
          nowPlayingBridge: nowPlayingBridge,
        ),
      ),
    );
    await tester.pump();
    adapter.emitState(
      const PlaybackState(backend: backend, status: PlaybackStatus.playing),
    );
    await tester.pump();
    if (pause) {
      adapter.emitState(
        const PlaybackState(backend: backend, status: PlaybackStatus.paused),
      );
      await tester.pump();
    }
    return adapter;
  }

  Future<void> pressPlay(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.mediaPlay);
    await tester.pump();
  }

  testWidgets('a short live pause resumes in place', (tester) async {
    final adapter = await pumpLivePlayer(tester);

    await tester.pump(const Duration(seconds: 10));
    await pressPlay(tester);

    expect(adapter.playCallCount, 1);
    expect(adapter.loadCalls, hasLength(1));
  });

  testWidgets('a long live pause reopens at the live edge', (tester) async {
    final adapter = await pumpLivePlayer(tester);

    await tester.pump(const Duration(seconds: 31));
    await pressPlay(tester);

    expect(adapter.playCallCount, 0);
    expect(adapter.loadCalls, hasLength(2));
    expect(adapter.loadCalls.last.uri, 'https://example.com/live.ts');
  });

  testWidgets('a very long live pause lets go of the stream until Play', (
    tester,
  ) async {
    final adapter = await pumpLivePlayer(tester);
    final stopsBefore = adapter.stopCallCount;

    await tester.pump(const Duration(minutes: 5));
    expect(adapter.stopCallCount, greaterThan(stopsBefore));
    expect(adapter.loadCalls, hasLength(1));

    await pressPlay(tester);
    expect(adapter.loadCalls, hasLength(2));
  });

  testWidgets('playing again clears the live pause clock', (tester) async {
    final adapter = await pumpLivePlayer(tester);

    await tester.pump(const Duration(seconds: 20));
    adapter.emitState(
      const PlaybackState(backend: backend, status: PlaybackStatus.playing),
    );
    await tester.pump();
    adapter.emitState(
      const PlaybackState(backend: backend, status: PlaybackStatus.paused),
    );
    await tester.pump(const Duration(seconds: 20));
    await pressPlay(tester);

    expect(adapter.playCallCount, 1);
    expect(adapter.loadCalls, hasLength(1));
  });

  testWidgets('lock screen presses while buffering never pause or restart', (
    tester,
  ) async {
    const channel = MethodChannel('test/now_playing_live');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          ..setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final adapter =
        await pumpLivePlayer(
            tester,
            nowPlayingBridge: NowPlayingBridge(channel: channel, enabled: true),
            pause: false,
          )
          ..emitState(
            const PlaybackState(
              backend: backend,
              status: PlaybackStatus.buffering,
            ),
          );
    await tester.pump();

    for (final name in ['toggle', 'play', 'toggle', 'play']) {
      await messenger.handlePlatformMessage(
        channel.name,
        const StandardMethodCodec().encodeMethodCall(
          MethodCall('command', <String, Object?>{'name': name}),
        ),
        (_) {},
      );
      await tester.pump();
    }

    expect(adapter.pauseCallCount, 0);
    expect(adapter.playCallCount, 0);
    expect(adapter.loadCalls, hasLength(1));
  });
}

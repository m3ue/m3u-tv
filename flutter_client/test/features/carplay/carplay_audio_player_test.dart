import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/carplay/carplay_audio_player.dart';
import 'package:m3u_tv/playback/now_playing_bridge.dart';
import 'package:m3u_tv/playback/playback_capabilities.dart';
import 'package:m3u_tv/playback/playback_orchestrator.dart';
import 'package:m3u_tv/playback/player_adapter.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/shared/channel_context.dart';

import '../../ui/player/fake_player_adapter.dart';
import '../../ui/player/fake_transcode_gateway.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const backend = PlaybackBackend.appleMpvNative;
  const nowPlayingChannel = MethodChannel('test/carplay_now_playing');
  const news = Channel(id: 1, name: 'News', streamUrl: 'https://e.x/1.ts');
  const sport = Channel(id: 2, name: 'Sport', streamUrl: 'https://e.x/2.ts');
  const lineup = ListChannelContext(<Channel>[news, sport]);

  late List<MethodCall> nowPlayingCalls;
  late FakePlayerAdapter adapter;
  late CarPlayAudioPlayer player;

  setUp(() {
    nowPlayingCalls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nowPlayingChannel, (call) async {
          nowPlayingCalls.add(call);
          return null;
        });
    adapter = FakePlayerAdapter(
      capabilities: PlaybackCapabilities.appleMpvNative,
    );
    player = CarPlayAudioPlayer(
      buildPlayer: () => PlaybackOrchestrator(
        platform: PlaybackPlatform.apple,
        adapters: <PlaybackBackend, PlayerAdapter>{backend: adapter},
        transcodeGateway: FakeTranscodeGateway(),
      ),
      sourceFor: (channel) =>
          PlaybackSource(uri: channel.streamUrl, isLive: true),
      allChannels: () => lineup,
      nowPlaying: NowPlayingBridge(channel: nowPlayingChannel, enabled: true),
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nowPlayingChannel, null);
  });

  Future<void> command(WidgetTester tester, NowPlayingCommand name) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
          nowPlayingChannel.name,
          const StandardMethodCodec().encodeMethodCall(
            MethodCall('command', <String, Object?>{'name': name.name}),
          ),
          (_) {},
        );
    await tester.pump();
  }

  // Never awaited bare: the open runs on the test's fake clock.
  Future<void> start(WidgetTester tester, Channel channel) async {
    unawaited(player.play(channel, lineup));
    await tester.pump();
    await tester.pump();
  }

  Future<void> stop(WidgetTester tester) async {
    final done = player.stop();
    await tester.pump();
    await done;
  }

  Future<void> emit(WidgetTester tester, PlaybackStatus status) async {
    adapter.emitState(PlaybackState(backend: backend, status: status));
    await tester.pump();
  }

  testWidgets('plays the channel and shows it in Now Playing', (tester) async {
    await start(tester, news);
    await emit(tester, PlaybackStatus.playing);

    expect(adapter.loadCalls.single.uri, 'https://e.x/1.ts');
    expect(adapter.loadCalls.single.isLive, isTrue);
    final update = nowPlayingCalls.lastWhere((c) => c.method == 'update');
    final info = update.arguments as Map<Object?, Object?>;
    expect(info['title'], 'News');
    expect(info['isPlaying'], isTrue);
    expect(info['canChangeChannel'], isTrue);

    await stop(tester);
  });

  testWidgets('Play while tuning neither restarts nor resumes', (
    tester,
  ) async {
    await start(tester, news);
    await emit(tester, PlaybackStatus.buffering);

    await command(tester, NowPlayingCommand.play);
    await command(tester, NowPlayingCommand.toggle);

    expect(adapter.playCallCount, 0);
    expect(adapter.pauseCallCount, 0);
    expect(adapter.loadCalls, hasLength(1));

    await stop(tester);
  });

  testWidgets('next channel moves through the picked list', (tester) async {
    await start(tester, news);
    await emit(tester, PlaybackStatus.playing);

    await command(tester, NowPlayingCommand.next);
    await tester.pump();

    expect(adapter.loadCalls.last.uri, 'https://e.x/2.ts');
    expect(player.channel, sport);

    await stop(tester);
  });

  testWidgets('a long live pause resumes at the live edge', (tester) async {
    await start(tester, news);
    await emit(tester, PlaybackStatus.playing);
    await emit(tester, PlaybackStatus.paused);

    await tester.pump(const Duration(seconds: 10));
    await command(tester, NowPlayingCommand.play);
    expect(adapter.playCallCount, 1);
    expect(adapter.loadCalls, hasLength(1));

    await emit(tester, PlaybackStatus.paused);
    await tester.pump(const Duration(seconds: 31));
    await command(tester, NowPlayingCommand.play);
    expect(adapter.loadCalls, hasLength(2));

    await stop(tester);
  });

  testWidgets('stop takes the player off Now Playing', (tester) async {
    await start(tester, news);
    await stop(tester);

    expect(player.channel, isNull);
    expect(nowPlayingCalls.last.method, 'clear');
  });
}

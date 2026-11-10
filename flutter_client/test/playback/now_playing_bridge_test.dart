import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/playback/now_playing_bridge.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const vod = NowPlayingInfo(
    title: 'Movie',
    isLive: false,
    isPlaying: true,
    position: Duration(seconds: 30),
    duration: Duration(minutes: 90),
    canSeek: true,
  );

  group('needsUpdate', () {
    test('sends the first update', () {
      expect(
        NowPlayingBridge.needsUpdate(
          previous: null,
          sincePrevious: Duration.zero,
          next: vod,
        ),
        isTrue,
      );
    });

    test('skips a position tick the system already extrapolated', () {
      final next = NowPlayingInfo(
        title: vod.title,
        isLive: false,
        isPlaying: true,
        position: const Duration(seconds: 35),
        duration: vod.duration,
        canSeek: true,
      );
      expect(
        NowPlayingBridge.needsUpdate(
          previous: vod,
          sincePrevious: const Duration(seconds: 5),
          next: next,
        ),
        isFalse,
      );
    });

    test('resends after a seek moves the position', () {
      final next = NowPlayingInfo(
        title: vod.title,
        isLive: false,
        isPlaying: true,
        position: const Duration(minutes: 20),
        duration: vod.duration,
        canSeek: true,
      );
      expect(
        NowPlayingBridge.needsUpdate(
          previous: vod,
          sincePrevious: const Duration(seconds: 1),
          next: next,
        ),
        isTrue,
      );
    });

    test('resends when playback pauses', () {
      final next = NowPlayingInfo(
        title: vod.title,
        isLive: false,
        isPlaying: false,
        position: vod.position,
        duration: vod.duration,
        canSeek: true,
      );
      expect(
        NowPlayingBridge.needsUpdate(
          previous: vod,
          sincePrevious: Duration.zero,
          next: next,
        ),
        isTrue,
      );
    });

    test('ignores position on live streams', () {
      const live = NowPlayingInfo(title: 'News', isLive: true, isPlaying: true);
      const later = NowPlayingInfo(
        title: 'News',
        isLive: true,
        isPlaying: true,
        position: Duration(minutes: 10),
      );
      expect(
        NowPlayingBridge.needsUpdate(
          previous: live,
          sincePrevious: Duration.zero,
          next: later,
        ),
        isFalse,
      );
    });
  });

  group('parseCommand', () {
    test('reads a seek target', () {
      final event = NowPlayingBridge.parseCommand(<Object?, Object?>{
        'name': 'seek',
        'positionMs': 61000,
      });
      expect(event?.command, NowPlayingCommand.seek);
      expect(event?.position, const Duration(seconds: 61));
    });

    test('drops unknown commands', () {
      expect(
        NowPlayingBridge.parseCommand(<Object?, Object?>{'name': 'rate'}),
        isNull,
      );
    });
  });

  group('channel', () {
    const channel = MethodChannel('test/now_playing');
    late List<MethodCall> calls;

    setUp(() {
      calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('only the current owner updates and clears', () async {
      final bridge = NowPlayingBridge(channel: channel, enabled: true);
      final oldPlayer = Object();
      final newPlayer = Object();

      bridge
        ..attach(oldPlayer, (_) {})
        ..attach(newPlayer, (_) {})
        ..update(oldPlayer, vod)
        ..detach(oldPlayer);
      await pumpEventQueue();
      expect(calls, isEmpty);

      bridge.update(newPlayer, vod);
      await pumpEventQueue();
      expect(calls.single.method, 'update');
      expect((calls.single.arguments as Map)['title'], 'Movie');

      bridge.detach(newPlayer);
      await pumpEventQueue();
      expect(calls.last.method, 'clear');
    });

    test('routes native commands to the owner', () async {
      final bridge = NowPlayingBridge(channel: channel, enabled: true);
      final received = <NowPlayingCommand>[];
      bridge.attach(Object(), (event) => received.add(event.command));

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            channel.name,
            const StandardMethodCodec().encodeMethodCall(
              const MethodCall('command', <String, Object?>{'name': 'toggle'}),
            ),
            (_) {},
          );

      expect(received, [NowPlayingCommand.toggle]);
    });

    test('does nothing when disabled', () async {
      final bridge = NowPlayingBridge(channel: channel, enabled: false);
      final owner = Object();
      bridge
        ..attach(owner, (_) {})
        ..update(owner, vod)
        ..detach(owner);
      await pumpEventQueue();
      expect(calls, isEmpty);
    });
  });
}

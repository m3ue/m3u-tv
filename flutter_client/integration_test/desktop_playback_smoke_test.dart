import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:m3u_tv/playback/desktop_libmpv_backend.dart';
import 'package:m3u_tv/playback/player_adapter.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('desktop libmpv backend smoke', () {
    testWidgets('reports feasibility and plays fixture without external mpv', (
      tester,
    ) async {
      final backend = DesktopLibmpvBackend();
      addTearDown(backend.dispose);

      final probe = await backend.probe();
      expect(probe.platform, isNot('unknown'));
      expect(probe.ownedSurface, isTrue);
      expect(probe.renderApiAvailable, isTrue);
      if (!probe.libmpvAvailable || !probe.canPlayFixture) {
        expect(probe.fallbackDecision, contains('server-transcode'));
        return;
      }

      final states = <PlaybackState>[];
      final subscription = backend.onState.listen(states.add);
      addTearDown(subscription.cancel);

      await backend.load(
        const PlaybackSource(
          uri: 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
          title: 'Desktop HLS smoke fixture',
          userAgent: 'm3u-tv/flutter-desktop-libmpv-smoke',
        ),
      );
      await backend.play();
      await tester.pump(const Duration(milliseconds: 250));
      await backend.pause();
      await backend.stop();

      expect(
        states.map((state) => state.status),
        containsAll(<PlaybackStatus>[
          PlaybackStatus.ready,
          PlaybackStatus.playing,
          PlaybackStatus.paused,
          PlaybackStatus.stopped,
        ]),
      );
    });

    test('normal playback stays on the method-channel texture path', () async {
      const methodChannel = MethodChannel('m3u_tv/desktop_libmpv');
      const eventChannel = EventChannel('m3u_tv/desktop_libmpv/events');
      final events = StreamController<Map<String, Object?>>.broadcast();

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
            eventChannel,
            MockStreamHandler.inline(
              onListen: (arguments, eventSink) {
                events.stream.listen((event) {
                  eventSink.success(event);
                });
              },
            ),
          );

      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (call) async {
            calls.add(call.method);
            switch (call.method) {
              case 'probe':
                return <String, Object?>{
                  'platform': 'linux',
                  'windowSystem': 'wayland',
                  'videoApi': 'EGL render API',
                  'ownedSurface': true,
                  'libmpvAvailable': true,
                  'renderApiAvailable': true,
                  'canPlayFixture': true,
                  'fallbackDecision': 'none',
                  'details': 'mock libmpv render context ready',
                };
              case 'load':
                scheduleMicrotask(() {
                  events.add(<String, Object?>{
                    'schemaVersion': 1,
                    'handle': 1,
                    'sequence': 0,
                    'kind': 'FILE_LOADED',
                    'videoAspectRatio': 1.78,
                  });
                });
                return <String, Object?>{
                  'ok': true,
                  'handle': 1,
                  'textureId': 11,
                };
              default:
                return null;
            }
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(methodChannel, null),
      );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockStreamHandler(eventChannel, null),
      );

      final backend = DesktopLibmpvBackend();
      addTearDown(backend.dispose);

      await backend.probe();
      await backend.load(const PlaybackSource(uri: 'fixture.mp4'));
      await backend.play();
      await backend.stop();

      expect(calls, <String>['probe', 'load', 'play', 'stop']);
      await events.close();
    });
  });
}

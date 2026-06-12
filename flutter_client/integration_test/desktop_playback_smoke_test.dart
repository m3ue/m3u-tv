import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:m3u_tv/playback/desktop_libmpv_backend.dart';
import 'package:m3u_tv/playback/player_adapter.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('desktop libmpv backend smoke', () {
    testWidgets('reports feasibility and plays fixture without external mpv', (
      WidgetTester tester,
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
        states.map((PlaybackState state) => state.status),
        containsAll(<PlaybackStatus>[
          PlaybackStatus.ready,
          PlaybackStatus.playing,
          PlaybackStatus.paused,
          PlaybackStatus.stopped,
        ]),
      );
    });

    test('normal playback stays on the method-channel texture path', () async {
      const channel = MethodChannel('m3u_tv/desktop_libmpv');
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async {
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
            .setMockMethodCallHandler(channel, null),
      );

      final backend = DesktopLibmpvBackend();
      addTearDown(backend.dispose);

      await backend.probe();
      await backend.load(const PlaybackSource(uri: 'fixture.mp4'));
      await backend.play();
      await backend.stop();

      expect(calls, <String>['probe', 'load', 'play', 'stop']);
    });
  });
}

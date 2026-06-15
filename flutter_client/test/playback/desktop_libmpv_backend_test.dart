import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/playback/desktop_libmpv_backend.dart';
import 'package:m3u_tv/playback/player_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DesktopLibmpvBackend', () {
    const channel = MethodChannel('m3u_tv/desktop_libmpv_test');

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test(
      'maps missing libmpv load response to typed BackendUnavailable',
      () async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              expect(call.method, 'load');
              return <String, Object?>{
                'ok': false,
                'code': BackendUnavailableException.unavailableCode,
                'error':
                    'mpv_create returned null; library=libmpv.so.2; LC_NUMERIC=C; ensure LC_NUMERIC is C or C.UTF-8 before creating libmpv',
              };
            });
        final backend = DesktopLibmpvBackend(channel: channel);
        final errors = <PlaybackError>[];
        final subscription = backend.onError.listen(errors.add);

        await expectLater(
          backend.load(
            const PlaybackSource(uri: 'https://example.test/live.m3u8'),
          ),
          throwsA(isA<BackendUnavailableException>()),
        );

        await pumpEventQueue();
        expect(errors, hasLength(1));
        expect(errors.single.code, BackendUnavailableException.unavailableCode);
        expect(errors.single.message, contains('library=libmpv.so.2'));
        expect(errors.single.message, contains('LC_NUMERIC=C'));
        expect(errors.single.recoverable, isTrue);
        expect(backend.textureId, isNull);

        await subscription.cancel();
        await backend.dispose();
      },
    );

    test('probe reports missing libmpv with fallback decision', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'probe');
            return <String, Object?>{
              'platform': 'linux',
              'windowSystem': 'wayland',
              'videoApi': 'software libmpv texture fallback',
              'ownedSurface': true,
              'libmpvAvailable': false,
              'renderApiAvailable': false,
              'canPlayFixture': false,
              'fallbackDecision':
                  'server-transcode until libmpv runtime is bundled',
              'details':
                  'libmpv shared library not found; tried libmpv.so.2 libmpv.so.1 libmpv.so; Flutter texture registrar unavailable; windowSystem=headless; hardwareDisplayHandle=unavailable; texture=Flutter pixel buffer',
            };
          });

      final backend = DesktopLibmpvBackend(channel: channel);
      final probe = await backend.probe();

      expect(probe.platform, 'linux');
      expect(probe.libmpvAvailable, isFalse);
      expect(probe.renderApiAvailable, isFalse);
      expect(probe.canPlayFixture, isFalse);
      expect(probe.fallbackDecision, contains('server-transcode'));
      expect(probe.passed, isFalse);

      await backend.dispose();
    });

    test('normal texture path never invokes the process-launch seam', () async {
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call.method);
            switch (call.method) {
              case 'probe':
                return <String, Object?>{
                  'platform': 'linux',
                  'windowSystem': 'x11',
                  'videoApi':
                      'X11 display handle + software libmpv texture fallback',
                  'ownedSurface': true,
                  'libmpvAvailable': true,
                  'renderApiAvailable': true,
                  'canPlayFixture': true,
                  'fallbackDecision': 'none',
                  'details':
                      'libmpv client/render symbols resolved; texture=Flutter pixel buffer',
                };
              case 'load':
                return <String, Object?>{
                  'ok': true,
                  'handle': 7,
                  'textureId': 99,
                };
              default:
                return null;
            }
          });

      final backend = DesktopLibmpvBackend(channel: channel);

      final probe = await backend.probe();
      await backend.load(
        const PlaybackSource(
          uri: 'https://example.test/live.m3u8',
          userAgent: 'm3u-tv/test',
          headers: <String, String>{'Referer': 'https://provider.test'},
        ),
      );
      await backend.play();
      await backend.pause();
      await backend.seek(const Duration(seconds: 30));
      await backend.setAudioTrack('2');
      await backend.setSubtitleTrack(null);
      await backend.setPlaybackSpeed(1.25);
      await backend.stop();

      expect(probe.passed, isTrue);
      expect(backend.textureId, 99);
      expect(calls, <String>[
        'probe',
        'load',
        'play',
        'pause',
        'seek',
        'setAudioTrack',
        'setSubtitleTrack',
        'setPlaybackSpeed',
        'stop',
      ]);

      await backend.dispose();
    });

    test('windows probe reports bundled DLL diagnostics', () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'probe');
            return <String, Object?>{
              'platform': 'windows',
              'windowSystem': 'win32-hwnd',
              'videoApi':
                  'Flutter pixel buffer texture using libmpv software render API',
              'ownedSurface': true,
              'libmpvAvailable': false,
              'renderApiAvailable': false,
              'canPlayFixture': false,
              'fallbackDecision': 'server-transcode until mpv-2.dll is bundled',
              'details':
                  'mpv-2.dll not found; tried runner directory and Windows DLL search path',
            };
          });

      final backend = DesktopLibmpvBackend(channel: channel);
      final probe = await backend.probe();

      expect(probe.platform, 'windows');
      expect(probe.windowSystem, 'win32-hwnd');
      expect(probe.libmpvAvailable, isFalse);
      expect(probe.renderApiAvailable, isFalse);
      expect(probe.fallbackDecision, contains('server-transcode'));
      expect(probe.details, contains('mpv-2.dll'));
      expect(probe.passed, isFalse);

      await backend.dispose();
    });

    test(
      'windows load sends shared contract and maps missing DLL typed error',
      () async {
        MethodCall? loadCall;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              loadCall = call;
              return <String, Object?>{
                'ok': false,
                'code': BackendUnavailableException.unavailableCode,
                'error':
                    'mpv-2.dll not found beside runner; server transcode required',
              };
            });

        final backend = DesktopLibmpvBackend(channel: channel);

        await expectLater(
          backend.load(
            const PlaybackSource(
              uri: 'https://example.test/movie.mp4',
              title: 'Movie',
              startPosition: Duration(seconds: 12),
              userAgent: 'm3u-tv/windows-test',
              headers: <String, String>{'Referer': 'https://provider.test'},
            ),
          ),
          throwsA(isA<BackendUnavailableException>()),
        );

        expect(loadCall, isNotNull);
        expect(loadCall!.method, 'load');
        expect(loadCall!.arguments, <String, Object?>{
          'uri': 'https://example.test/movie.mp4',
          'title': 'Movie',
          'startPositionMs': 12000,
          'isLive': false,
          'userAgent': 'm3u-tv/windows-test',
          'headers': <String, String>{'Referer': 'https://provider.test'},
        });
        expect(backend.textureId, isNull);

        await backend.dispose();
      },
    );

    test('windows texture controls stay on method channel commands', () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'load') {
              return <String, Object?>{
                'ok': true,
                'handle': 41,
                'textureId': 4100,
                'display':
                    'windowSystem=win32-hwnd; texture=Flutter pixel buffer',
              };
            }
            return null;
          });

      final backend = DesktopLibmpvBackend(channel: channel);
      await backend.load(
        const PlaybackSource(uri: 'https://example.test/live.m3u8'),
      );
      await backend.play();
      await backend.pause();
      await backend.seek(const Duration(milliseconds: 2500));
      await backend.setAudioTrack(null);
      await backend.setSubtitleTrack('3');
      await backend.setPlaybackSpeed(0.75);
      await backend.stop();
      await backend.dispose();

      expect(backend.textureId, isNull);
      expect(calls.map((call) => call.method), <String>[
        'load',
        'play',
        'pause',
        'seek',
        'setAudioTrack',
        'setSubtitleTrack',
        'setPlaybackSpeed',
        'stop',
        'dispose',
      ]);
      expect(calls[1].arguments, <String, Object?>{'handle': 41});
      expect(calls[3].arguments, <String, Object?>{
        'handle': 41,
        'positionMs': 2500,
      });
      expect(calls[4].arguments, <String, Object?>{
        'handle': 41,
        'trackId': null,
      });
      expect(calls[5].arguments, <String, Object?>{
        'handle': 41,
        'trackId': '3',
      });
      expect(calls[6].arguments, <String, Object?>{
        'handle': 41,
        'speed': 0.75,
      });
    });
  });
}

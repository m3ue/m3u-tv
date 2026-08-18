import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/playback/desktop_libmpv_backend.dart';
import 'package:m3u_tv/playback/player_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DesktopLibmpvBackend', () {
    const methodChannel = MethodChannel('m3u_tv/desktop_libmpv');
    const eventChannel = EventChannel('m3u_tv/desktop_libmpv/events');

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(eventChannel, null);
    });

    StreamController<Map<String, Object?>> setupMockEvents() {
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
      return events;
    }

    test(
      'maps missing libmpv response only to the load Future',
      () async {
        final events = setupMockEvents();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(methodChannel, (call) async {
              expect(call.method, 'load');
              return <String, Object?>{
                'ok': false,
                'code': BackendUnavailableException.unavailableCode,
                'error':
                    'mpv_create returned null; library=libmpv.so.2; LC_NUMERIC=C; ensure LC_NUMERIC is C or C.UTF-8 before creating libmpv',
              };
            });
        final backend = DesktopLibmpvBackend();
        final errors = <PlaybackError>[];
        final subscription = backend.onError.listen(errors.add);

        await expectLater(
          backend.load(
            const PlaybackSource(uri: 'https://example.test/live.m3u8'),
          ),
          throwsA(isA<BackendUnavailableException>()),
        );

        await pumpEventQueue();
        expect(errors, isEmpty);
        expect(backend.textureId, isNull);

        await subscription.cancel();
        await backend.dispose();
        await events.close();
      },
    );

    test('probe reports missing libmpv with fallback decision', () async {
      final events = setupMockEvents();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (call) async {
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

      final backend = DesktopLibmpvBackend();
      final probe = await backend.probe();

      expect(probe.platform, 'linux');
      expect(probe.libmpvAvailable, isFalse);
      expect(probe.renderApiAvailable, isFalse);
      expect(probe.canPlayFixture, isFalse);
      expect(probe.fallbackDecision, contains('server-transcode'));
      expect(probe.passed, isFalse);

      await backend.dispose();
      await events.close();
    });

    test('normal texture path never invokes the process-launch seam', () async {
      final events = setupMockEvents();
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (call) async {
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
                scheduleMicrotask(() {
                  events.add(<String, Object?>{
                    'schemaVersion': 1,
                    'handle': 7,
                    'sequence': 0,
                    'kind': 'FILE_LOADED',
                    'videoAspectRatio': 1.78,
                  });
                });
                return <String, Object?>{
                  'ok': true,
                  'handle': 7,
                  'textureId': 99,
                };
              default:
                return null;
            }
          });

      final backend = DesktopLibmpvBackend();

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
      expect(backend.textureId, isNull);
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
        'dispose',
      ]);

      await backend.dispose();
      await events.close();
    });

    test('windows probe reports bundled DLL diagnostics', () async {
      final events = setupMockEvents();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (call) async {
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

      final backend = DesktopLibmpvBackend();
      final probe = await backend.probe();

      expect(probe.platform, 'windows');
      expect(probe.windowSystem, 'win32-hwnd');
      expect(probe.libmpvAvailable, isFalse);
      expect(probe.renderApiAvailable, isFalse);
      expect(probe.fallbackDecision, contains('server-transcode'));
      expect(probe.details, contains('mpv-2.dll'));
      expect(probe.passed, isFalse);

      await backend.dispose();
      await events.close();
    });

    test(
      'windows load sends shared contract and maps missing DLL typed error',
      () async {
        final events = setupMockEvents();
        MethodCall? loadCall;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(methodChannel, (call) async {
              loadCall = call;
              return <String, Object?>{
                'ok': false,
                'code': BackendUnavailableException.unavailableCode,
                'error':
                    'mpv-2.dll not found beside runner; server transcode required',
              };
            });

        final backend = DesktopLibmpvBackend();

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
          'externalSubtitles': <Map<String, Object?>>[],
        });
        expect(backend.textureId, isNull);

        await backend.dispose();
        await events.close();
      },
    );

    test('windows texture controls stay on method channel commands', () async {
      final events = setupMockEvents();
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (call) async {
            calls.add(call);
            if (call.method == 'load') {
              scheduleMicrotask(() {
                events.add(<String, Object?>{
                  'schemaVersion': 1,
                  'handle': 41,
                  'sequence': 0,
                  'kind': 'FILE_LOADED',
                });
              });
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

      final backend = DesktopLibmpvBackend();
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
      await events.close();
    });

    test(
      'dispose during a pending load releases the returned handle without publishing after close',
      () async {
        final events = setupMockEvents();
        final loadResponse = Completer<Map<String, Object?>>();
        final calls = <MethodCall>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(methodChannel, (call) async {
              calls.add(call);
              if (call.method == 'load') return loadResponse.future;
              return null;
            });

        final backend = DesktopLibmpvBackend();
        final states = <PlaybackState>[];
        final errors = <PlaybackError>[];
        final stateSub = backend.onState.listen(states.add);
        final errorSub = backend.onError.listen(errors.add);
        final load = backend.load(
          const PlaybackSource(uri: 'https://example.test/pending.m3u8'),
        );

        await pumpEventQueue();
        await backend.dispose();
        loadResponse.complete(<String, Object?>{
          'ok': true,
          'handle': 77,
          'textureId': 7700,
        });

        await expectLater(load, completes);
        await pumpEventQueue();

        final disposeCalls = calls
            .where((call) => call.method == 'dispose')
            .toList();
        expect(disposeCalls, hasLength(1));
        expect(disposeCalls.single.arguments, <String, Object?>{'handle': 77});
        expect(backend.textureId, isNull);
        expect(states, isEmpty);
        expect(errors, isEmpty);

        await stateSub.cancel();
        await errorSub.cancel();
        await events.close();
      },
    );

    test(
      'stop during a pending load settles it and disposes the late handle once',
      () async {
        final events = setupMockEvents();
        final loadResponse = Completer<Map<String, Object?>>();
        final calls = <MethodCall>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(methodChannel, (call) async {
              calls.add(call);
              if (call.method == 'load') return loadResponse.future;
              return null;
            });

        final backend = DesktopLibmpvBackend();
        final load = backend.load(
          const PlaybackSource(uri: 'https://example.test/pending-stop.m3u8'),
        );

        await pumpEventQueue();
        await backend.stop().timeout(const Duration(seconds: 1));
        loadResponse.complete(<String, Object?>{
          'ok': true,
          'handle': 78,
          'textureId': 7800,
        });

        await expectLater(
          load.timeout(const Duration(seconds: 1)),
          completes,
        );
        await pumpEventQueue();

        final disposeCalls = calls
            .where((call) => call.method == 'dispose')
            .toList();
        expect(disposeCalls, hasLength(1));
        expect(disposeCalls.single.arguments, <String, Object?>{'handle': 78});
        expect(calls.where((call) => call.method == 'stop'), isEmpty);
        expect(backend.textureId, isNull);

        await backend.dispose();
        await events.close();
      },
    );
  });
}

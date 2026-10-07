import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/playback/mac_mpv_native_backend.dart';
import 'package:m3u_tv/playback/player_adapter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MacMpvNativeBackend', () {
    const methodChannel = MethodChannel('m3u_tv/mac_mpv');
    const eventChannel = EventChannel('m3u_tv/mac_mpv/events');

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(eventChannel, null);
    });

    void setupMockEvents() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockStreamHandler(
            eventChannel,
            MockStreamHandler.inline(onListen: (arguments, eventSink) {}),
          );
    }

    test('is a MultiviewBackend', () {
      setupMockEvents();
      final backend = MacMpvNativeBackend();
      expect(backend, isA<MultiviewBackend>());
      expect(backend, isA<PlatformViewProvider>());
    });

    test(
      "setVolume scales the 0-1 fraction to mpv's 0-100 volume property",
      () async {
        setupMockEvents();
        final calls = <MethodCall>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(methodChannel, (call) async {
              calls.add(call);
              return null;
            });

        final backend = MacMpvNativeBackend();
        await backend.setVolume(0.5);

        expect(calls, hasLength(1));
        final call = calls.single;
        expect(call.method, 'setVolume');
        final args = call.arguments as Map<Object?, Object?>;
        expect(args['volume'], 50.0);
        expect(args['viewId'], isNotNull);

        await backend.dispose();
      },
    );

    test('load tells the native core when the source is catchup', () async {
      setupMockEvents();
      MethodCall? loadCall;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (call) async {
            if (call.method == 'load') loadCall = call;
            return <String, Object?>{'ok': false, 'error': 'test'};
          });

      final backend = MacMpvNativeBackend();
      await expectLater(
        backend.load(
          const PlaybackSource(
            uri: 'https://editor.test/timeshift/u/p/60/2026-10-01:20-00/1.ts',
            isCatchup: true,
          ),
        ),
        throwsA(isA<PlaybackException>()),
      );

      final args = loadCall!.arguments as Map<Object?, Object?>;
      expect(args['isCatchup'], isTrue);
      expect(args['isLive'], isFalse);

      await backend.dispose();
    });

    test('load forwards the deinterlace setting', () async {
      setupMockEvents();
      final loadCalls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (call) async {
            if (call.method == 'load') loadCalls.add(call);
            return <String, Object?>{'ok': false, 'error': 'test'};
          });

      final backend = MacMpvNativeBackend();
      for (final deinterlace in [true, false]) {
        await expectLater(
          backend.load(
            PlaybackSource(
              uri: 'https://editor.test/live/u/p/1.ts',
              isLive: true,
              deinterlace: deinterlace,
            ),
          ),
          throwsA(isA<PlaybackException>()),
        );
      }

      // Sent on every load, off included: the native handle persists across
      // loads, so an omitted key would leave the previous load's value.
      expect(
        loadCalls.map(
          (call) => (call.arguments as Map<Object?, Object?>)['deinterlace'],
        ),
        [isTrue, isFalse],
      );

      await backend.dispose();
    });

    test('seekWindow reads the buffered ranges from the native core', () async {
      setupMockEvents();
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, (call) async {
            calls.add(call);
            return <String, Object?>{
              'cacheState': '{"seekable-ranges":[{"start":12.5,"end":40.0}]}',
            };
          });

      final backend = MacMpvNativeBackend();
      final window = await backend.seekWindow();

      expect(calls.single.method, 'seekWindow');
      expect(
        (calls.single.arguments as Map<Object?, Object?>)['viewId'],
        backend.viewId,
      );
      expect(window?.buffered, <({Duration start, Duration end})>[
        (
          start: const Duration(seconds: 12, milliseconds: 500),
          end: const Duration(seconds: 40),
        ),
      ]);

      await backend.dispose();
    });
  });
}

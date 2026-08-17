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
  });
}

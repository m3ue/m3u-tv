import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:m3u_tv/playback/android_playback_adapter.dart';
import 'package:m3u_tv/playback/playback_capabilities.dart';
import 'package:m3u_tv/playback/player_adapter.dart';

import '../test/fakes/fake_m3u_editor_server.dart';
import '../test/fixtures/production_stream_catalog.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('production Android Media3 playback', () {
    late FakeM3uEditorServer server;
    late AndroidPlaybackAdapter adapter;

    setUp(() async {
      if (!Platform.isAndroid ||
          Platform.environment['ANDROID_MEDIA3_DEVICE_SMOKE'] != 'true') {
        return;
      }
      server = FakeM3uEditorServer(apiToken: 'fixture-api-token');
      await server.start();
      adapter = AndroidPlaybackAdapter(
        probe: const AndroidPlaybackProbe(
          hardwareCodecs: <VideoCodec>{VideoCodec.h264},
          passthroughAudioCodecs: <AudioCodec>{AudioCodec.aac},
          mpvAvailable: false,
          serverTranscodeAvailable: true,
        ),
      );
    });

    tearDown(() async {
      if (!Platform.isAndroid ||
          Platform.environment['ANDROID_MEDIA3_DEVICE_SMOKE'] != 'true') {
        return;
      }
      await adapter.dispose();
      await server.close();
    });

    testWidgets('loads HLS live and MP4 VOD fixtures through Media3', (
      tester,
    ) async {
      _skipWithoutAndroidSmokeFlag();

      for (final fixture in <ProductionStreamFixture>[
        hlsLiveFixture,
        mp4VodFixture,
      ]) {
        final states = <PlaybackState>[];
        final errors = <PlaybackError>[];
        final stateSubscription = adapter.onState.listen(states.add);
        final errorSubscription = adapter.onError.listen(errors.add);
        addTearDown(stateSubscription.cancel);
        addTearDown(errorSubscription.cancel);

        await adapter.load(fixture.playbackSource(server.uri));
        await adapter.play();
        await _pumpUntil(
          tester,
          () => states.any(
            (state) =>
                state.status == PlaybackStatus.ready ||
                state.status == PlaybackStatus.playing,
          ),
        );
        await adapter.stop();

        expect(adapter.activeBackend, PlaybackBackend.androidExoPlayer);
        expect(errors, isEmpty);
        expect(
          states.map((state) => state.status),
          contains(anyOf(PlaybackStatus.ready, PlaybackStatus.playing)),
        );
      }
    });

    testWidgets('emits typed recoverable error for dead stream fixture', (
      tester,
    ) async {
      _skipWithoutAndroidSmokeFlag();

      final errors = <PlaybackError>[];
      final subscription = adapter.onError.listen(errors.add);
      addTearDown(subscription.cancel);

      await adapter.load(deadUrlFixture.playbackSource(server.uri));
      await adapter.play();
      await _pumpUntil(tester, () => errors.isNotEmpty);

      expect(adapter.activeBackend, PlaybackBackend.androidExoPlayer);
      expect(errors.single.backend, PlaybackBackend.androidExoPlayer);
      expect(errors.single.recoverable, isTrue);
    });
  });
}

void _skipWithoutAndroidSmokeFlag() {
  if (!Platform.isAndroid) {
    return markTestSkipped(
      'Android Media3 integration requires an Android device or emulator.',
    );
  }
  if (Platform.environment['ANDROID_MEDIA3_DEVICE_SMOKE'] != 'true') {
    return markTestSkipped(
      'Set ANDROID_MEDIA3_DEVICE_SMOKE=true on an Android device runner to execute.',
    );
  }
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() predicate, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

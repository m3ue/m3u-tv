import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/epg/epg_preview_player.dart';
import 'package:m3u_tv/features/player/player_screen.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/navigation/app_router.dart';
import 'package:m3u_tv/playback/native_video_surface.dart';
import 'package:m3u_tv/playback/playback_capabilities.dart';
import 'package:m3u_tv/playback/playback_orchestrator.dart';
import 'package:m3u_tv/playback/player_adapter.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/epg_service.dart';

import '../player/fake_player_adapter.dart';
import '../player/fake_transcode_gateway.dart';

const _channel = Channel(id: 1, name: 'One', streamUrl: 'fixture://one');
const _otherChannel = Channel(id: 2, name: 'Two', streamUrl: 'fixture://two');

class _DisplayModeAdapter extends FakePlayerAdapter
    implements DisplayModeController {
  _DisplayModeAdapter()
    : super(capabilities: PlaybackCapabilities.desktopLibmpv, textureId: 42);

  final List<bool> displayModeCalls = <bool>[];

  @override
  Future<void> setAllowDisplayModeChanges(bool allowed) async {
    displayModeCalls.add(allowed);
  }
}

({PlaybackOrchestrator orchestrator, _DisplayModeAdapter adapter})
_buildPlayer() {
  final adapter = _DisplayModeAdapter();
  final orchestrator = PlaybackOrchestrator(
    platform: PlaybackPlatform.desktop,
    adapters: <PlaybackBackend, PlayerAdapter>{
      PlaybackBackend.desktopLibmpv: adapter,
    },
    transcodeGateway: FakeTranscodeGateway(),
  );
  return (orchestrator: orchestrator, adapter: adapter);
}

/// Not live, so the orchestrator skips its HTTP preflight in tests.
PlaybackSource _sourceFor(Channel channel) =>
    PlaybackSource(uri: channel.streamUrl, title: channel.name);

void main() {
  group('EpgPreviewPlayerController', () {
    late List<_DisplayModeAdapter> adapters;
    late EpgPreviewPlayerController controller;

    setUp(() {
      adapters = <_DisplayModeAdapter>[];
      controller = EpgPreviewPlayerController(
        buildPlayer: () {
          final built = _buildPlayer();
          adapters.add(built.adapter);
          return built.orchestrator;
        },
        sourceFor: _sourceFor,
      );
    });

    tearDown(() => controller.dispose());

    test('opens with display mode changes held off', () async {
      await controller.play(_channel);

      expect(adapters.single.loadCalls.single.allowDisplayModeChanges, false);
    });

    test('lend hands the playing player over without stopping it', () async {
      await controller.play(_channel);
      final orchestrator = controller.surfaceOrchestrator;
      final surfaceKey = controller.surfaceKey;
      var notified = 0;
      controller.addListener(() => notified++);

      final lease = controller.lend();

      expect(lease, isNotNull);
      expect(lease!.orchestrator, same(orchestrator));
      expect(lease.surfaceKey, same(surfaceKey));
      expect(lease.channel.id, _channel.id);
      expect(controller.channel, isNull);
      expect(controller.surfaceOrchestrator, isNull);
      expect(notified, 1);
      expect(adapters.single.stopCallCount, 0);
      expect(adapters.single.disposeCallCount, 0);

      // The guide stopping its preview meanwhile doesn't reach a lent player.
      await controller.stop();
      expect(adapters.single.disposeCallCount, 0);
      await lease.orchestrator.dispose();
    });

    test('lend returns null with nothing healthy to hand over', () async {
      expect(controller.lend(), isNull);
    });

    test(
      'adoptBack resumes rendering the lent player on its new channel',
      () async {
        await controller.play(_channel);
        final lease = controller.lend()!;

        expect(controller.canAdoptBack, isTrue);
        expect(controller.adoptBack(lease.withChannel(_otherChannel)), isTrue);

        expect(controller.surfaceOrchestrator, same(lease.orchestrator));
        expect(controller.surfaceKey, same(lease.surfaceKey));
        expect(controller.isPlaying(_otherChannel), isTrue);
        expect(adapters, hasLength(1));
      },
    );

    test('does not start another player while one is lent', () async {
      await controller.play(_channel);
      final lease = controller.lend()!;

      await controller.play(_otherChannel);
      expect(adapters, hasLength(1));

      controller.forgetLent();
      await controller.play(_otherChannel);
      expect(adapters, hasLength(2));
      await lease.orchestrator.dispose();
    });

    test('adoptBack refuses while the preview plays something else', () async {
      await controller.play(_channel);
      final lease = controller.lend()!;
      controller.forgetLent();
      await controller.play(_otherChannel);

      expect(controller.canAdoptBack, isFalse);
      expect(controller.adoptBack(lease), isFalse);
      await lease.orchestrator.dispose();
    });
  });

  group('PlaybackOrchestrator display mode', () {
    test(
      'forwards the toggle to the active backend and remembers it',
      () async {
        final built = _buildPlayer();
        addTearDown(built.orchestrator.dispose);
        await built.orchestrator.open(
          _sourceFor(_channel).copyWith(allowDisplayModeChanges: false),
        );

        await built.orchestrator.setAllowDisplayModeChanges(true);
        await built.orchestrator.open(_sourceFor(_otherChannel));

        expect(built.adapter.displayModeCalls, [true]);
        expect(
          built.adapter.loadCalls.map(
            (source) => source.allowDisplayModeChanges,
          ),
          [false, true],
        );
      },
    );

    test('lastState is the latest state emitted', () async {
      final built = _buildPlayer();
      addTearDown(built.orchestrator.dispose);
      await built.orchestrator.open(_sourceFor(_channel));
      built.adapter.emitState(
        const PlaybackState(
          backend: PlaybackBackend.desktopLibmpv,
          status: PlaybackStatus.playing,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(built.orchestrator.lastState?.status, PlaybackStatus.playing);
    });
  });

  testWidgets(
    'the native view moves between the preview and the player in one frame',
    (tester) async {
      final controller = EpgPreviewPlayerController(
        buildPlayer: () => _buildPlayer().orchestrator,
        sourceFor: _sourceFor,
      );
      addTearDown(controller.dispose);
      await tester.runAsync(() => controller.play(_channel));
      final player = ValueNotifier<EpgPreviewLease?>(null);
      addTearDown(player.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: ValueListenableBuilder<EpgPreviewLease?>(
            valueListenable: player,
            builder: (context, lease, _) => Stack(
              children: [
                // The guide's preview panel, built during layout like the
                // guide's own LayoutBuilder.
                LayoutBuilder(
                  builder: (context, _) => Align(
                    alignment: Alignment.topLeft,
                    child: SizedBox(
                      width: 320,
                      height: 180,
                      child: ListenableBuilder(
                        listenable: controller,
                        builder: (context, _) =>
                            controller.surfaceOrchestrator == null
                            ? const SizedBox.shrink()
                            : EpgPreviewVideo(controller: controller),
                      ),
                    ),
                  ),
                ),
                // The full-screen player, wrapped differently.
                if (lease != null)
                  Positioned.fill(
                    child: LayoutBuilder(
                      builder: (context, _) => NativeVideoSurface(
                        surfaceKey: lease.surfaceKey,
                        textureId: lease.orchestrator.activeTextureId,
                        platformView: null,
                        aspectRatio: 16 / 9,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
      final previewElement = tester.element(find.byType(Texture));

      // Lent and opened synchronously, as LiveTvScreen and AppShell do.
      player.value = controller.lend();
      await tester.pump();

      expect(find.byType(Texture), findsOneWidget);
      expect(tester.element(find.byType(Texture)), same(previewElement));
      expect(tester.getSize(find.byType(Texture)).width, greaterThan(320));

      // And back.
      final lease = player.value!;
      expect(controller.adoptBack(lease), isTrue);
      player.value = null;
      await tester.pump();

      expect(find.byType(Texture), findsOneWidget);
      expect(tester.element(find.byType(Texture)), same(previewElement));
      expect(
        tester.getSize(find.byType(Texture)).width,
        lessThanOrEqualTo(320),
      );
    },
  );

  testWidgets('PlayerScreen carries on with an adopted session', (
    tester,
  ) async {
    final built = _buildPlayer();
    addTearDown(built.orchestrator.dispose);
    await tester.runAsync(
      () => built.orchestrator.open(_sourceFor(_channel)),
    );
    built.adapter.emitState(
      const PlaybackState(
        backend: PlaybackBackend.desktopLibmpv,
        status: PlaybackStatus.playing,
      ),
    );
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    const released = false;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: PlayerScreen(
          args: PlayerArgs.liveChannel(_channel),
          orchestrator: built.orchestrator,
          epgService: EpgService(clock: () => DateTime.utc(2026)),
          adoptsPlayingSession: true,
          releasesOrchestratorOnDispose: () => released,
        ),
      ),
    );
    await tester.pump();

    expect(built.adapter.loadCalls, hasLength(1));
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(built.adapter.stopCallCount, 0);
  });

  testWidgets('a channel change keeps the native view mounted', (
    tester,
  ) async {
    // Remounting it makes the mpv cores re-create themselves, tearing down
    // the core the new channel's load was already sent to.
    final viewCalls = <String>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform_views,
      (call) async {
        viewCalls.add(call.method);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform_views,
        null,
      ),
    );
    final adapter = _PlatformViewAdapter();
    final orchestrator = PlaybackOrchestrator(
      platform: PlaybackPlatform.desktop,
      adapters: <PlaybackBackend, PlayerAdapter>{
        PlaybackBackend.desktopLibmpv: adapter,
      },
      transcodeGateway: FakeTranscodeGateway(),
      streamSessionGateway: _SlowReleaseGateway(),
    );
    final surfaceKey = GlobalKey();
    Widget player(Channel channel) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: PlayerScreen(
        key: const ValueKey('player'),
        // VOD args: no live preflight HTTP probe in tests.
        args: PlayerArgs(
          streamUrl: channel.streamUrl,
          title: channel.name,
          type: 'vod',
          streamId: channel.id,
        ),
        orchestrator: orchestrator,
        surfaceKey: surfaceKey,
        epgService: EpgService(clock: () => DateTime.utc(2026)),
      ),
    );

    await tester.pumpWidget(player(_channel));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    viewCalls.clear();

    await tester.pumpWidget(player(_otherChannel));
    // Frames keep building while the old session's release is in flight
    // and open() has no active adapter.
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }

    expect(adapter.loadCalls, hasLength(2));
    expect(viewCalls, isNot(contains('create')));
    expect(viewCalls, isNot(contains('dispose')));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 3));
    await tester.runAsync(orchestrator.dispose);
  });
}

class _PlatformViewAdapter extends FakePlayerAdapter
    implements PlatformViewProvider {
  _PlatformViewAdapter()
    : super(capabilities: PlaybackCapabilities.desktopLibmpv);

  @override
  String get platformViewType => 'm3u_tv/test_player_view';

  @override
  Map<String, dynamic>? get platformViewCreationParams => <String, dynamic>{
    'viewId': 1,
  };

  @override
  Future<void> releaseNativeView() async {}
}

/// Takes as long to release a session as the editor's stop call does.
class _SlowReleaseGateway implements PlaybackStreamSessionGateway {
  @override
  PlaybackSource attachClientId(PlaybackSource source, String clientId) =>
      source.copyWith(uri: '${source.uri}?client_id=$clientId');

  @override
  Future<void> releaseStream(PlaybackSource source, String clientId) =>
      Future<void>.delayed(const Duration(milliseconds: 150));
}

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/player/playback_controls.dart';
import 'package:m3u_tv/features/player/player_screen.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/navigation/app_router.dart';
import 'package:m3u_tv/playback/playback_capabilities.dart';
import 'package:m3u_tv/playback/playback_orchestrator.dart';
import 'package:m3u_tv/playback/player_adapter.dart';
import 'package:m3u_tv/services/epg_service.dart';
import 'package:m3u_tv/services/view_settings_service.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_player_adapter.dart';
import 'fake_transcode_gateway.dart';

void main() {
  Future<void> pumpPlayer(
    WidgetTester tester, {
    required bool hideOverlayOnStart,
  }) async {
    final viewSettings = ViewSettingsService();
    await viewSettings.setHideOverlayOnStart(hideOverlayOnStart);
    final adapter = FakePlayerAdapter(
      capabilities: PlaybackCapabilities.desktopLibmpv,
      textureId: 42,
    );
    final orchestrator = PlaybackOrchestrator(
      platform: PlaybackPlatform.desktop,
      adapters: <PlaybackBackend, PlayerAdapter>{
        PlaybackBackend.desktopLibmpv: adapter,
      },
      transcodeGateway: FakeTranscodeGateway(),
    );
    addTearDown(orchestrator.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: PlayerScreen(
          args: const PlayerArgs(
            streamUrl: 'https://example.com/live.ts',
            title: 'Channel Fixture',
            type: 'live',
          ),
          orchestrator: orchestrator,
          epgService: EpgService(clock: () => DateTime.utc(2026)),
          viewSettingsService: viewSettings,
          onClose: () {},
        ),
      ),
    );
    await tester.pump();
    adapter.emitState(
      const PlaybackState(
        backend: PlaybackBackend.desktopLibmpv,
        status: PlaybackStatus.playing,
      ),
    );
    await tester.pump();
  }

  testWidgets('shows the controls on start by default', (tester) async {
    await pumpPlayer(tester, hideOverlayOnStart: false);

    expect(find.byType(PlaybackControls), findsOneWidget);
  });

  testWidgets('starts on just the picture when hide overlay on start is on', (
    tester,
  ) async {
    await pumpPlayer(tester, hideOverlayOnStart: true);

    expect(find.byType(PlaybackControls), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    expect(find.byType(PlaybackControls), findsOneWidget);
  });
}

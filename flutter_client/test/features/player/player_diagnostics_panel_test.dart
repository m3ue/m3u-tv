import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/player/player_diagnostics_panel.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/playback/playback_capabilities.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  Future<void> pump(WidgetTester tester, List<String> diagnostics) =>
      tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: PlaybackDiagnosticsPanel(
              activeBackend: PlaybackBackend.androidMpv,
              diagnostics: diagnostics,
            ),
          ),
        ),
      );

  testWidgets('shows a mid-stream switch and its reason', (tester) async {
    await pump(tester, const [
      'active-backend:androidExoPlayer:ready',
      'decoder-fallback:AUDIO_TIMESTAMP_DISCONTINUITY:androidExoPlayer->androidMpv',
      'active-backend:androidMpv:ready',
    ]);

    expect(find.text('Android native mpv'), findsOneWidget);
    expect(find.text('AUDIO_TIMESTAMP_DISCONTINUITY'), findsOneWidget);
    expect(find.text('androidExoPlayer->androidMpv'), findsOneWidget);
  });

  testWidgets('removes credentials from a load failure', (tester) async {
    await pump(tester, const [
      'fallback-reason:load_failed:failed http://host/movie/alice/s3cret/1.mkv',
    ]);

    expect(find.textContaining('s3cret'), findsNothing);
    expect(find.textContaining('[redacted]'), findsOneWidget);
  });
}

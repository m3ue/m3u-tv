import 'package:dpad/dpad.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/settings/sections/playback_settings_page.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/view_settings_service.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  late ViewSettingsService service;

  setUp(() => service = ViewSettingsService());

  Future<AppLocalizations> pump(
    WidgetTester tester, {
    bool showVodPlayer = true,
    bool showHdr = true,
    bool showRefreshRate = true,
    bool showDeinterlace = true,
  }) async {
    await tester.pumpWidget(
      Dpad(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: ListenableBuilder(
                listenable: service,
                builder: (context, _) => PlayerSettingsGroup(
                  service: service,
                  showVodPlayer: showVodPlayer,
                  showHdr: showHdr,
                  showRefreshRate: showRefreshRate,
                  showDeinterlace: showDeinterlace,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return AppLocalizations.delegate.load(const Locale('en'));
  }

  testWidgets('shows only the rows the platform supports', (tester) async {
    final l = await pump(
      tester,
      showVodPlayer: false,
      showHdr: false,
      showDeinterlace: false,
    );

    expect(find.text(l.settingsVodPlayer), findsNothing);
    expect(find.text(l.settingsHdrMode), findsNothing);
    expect(find.text(l.settingsDeinterlace), findsNothing);
    expect(find.text(l.settingsMatchRefreshRate), findsOneWidget);
  });

  testWidgets('picks mpv for movies and series', (tester) async {
    final l = await pump(tester);
    expect(find.text(l.settingsVodPlayerExoPlayerFirst), findsOneWidget);

    await tester.tap(find.text(l.settingsVodPlayer));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l.settingsVodPlayerMpv));
    await tester.pumpAndSettle();

    expect(service.vodPlayerSync, VodPlayerPreference.mpv);
    expect(find.text(l.settingsVodPlayerMpv), findsOneWidget);
  });

  testWidgets('moved switches still change their settings', (tester) async {
    final l = await pump(tester);
    expect(service.hdrEnabledSync, isTrue);
    expect(service.matchRefreshRateSync, isFalse);
    expect(service.deinterlaceSync, isFalse);

    await tester.tap(find.text(l.settingsHdrMode));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l.settingsMatchRefreshRate));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l.settingsDeinterlace));
    await tester.pumpAndSettle();

    expect(service.hdrEnabledSync, isFalse);
    expect(service.matchRefreshRateSync, isTrue);
    expect(service.deinterlaceSync, isTrue);
  });
}

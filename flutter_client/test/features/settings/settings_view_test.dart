import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/settings/settings_screen.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/auth_notifier.dart';
import 'package:m3u_tv/services/comskip_settings.dart';
import 'package:m3u_tv/services/proxy_playback_settings.dart';
import 'package:m3u_tv/services/secure_storage.dart';
import 'package:m3u_tv/services/trakt_service.dart';
import 'package:m3u_tv/services/view_settings_service.dart';
import 'package:m3u_tv/services/xtream_service.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';

class _FakeSecureStorage implements SecureStorage {
  final _data = <String, String?>{};

  @override
  Future<String?> read(String key) async => _data[key];

  @override
  Future<void> write(String key, String value) async => _data[key] = value;

  @override
  Future<void> delete(String key) async => _data.remove(key);
}

class _FakeXtreamService implements XtreamService {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('SettingsScreen view settings section', () {
    late ViewSettingsService viewSettingsService;
    late AuthNotifier authNotifier;
    late TraktService traktService;
    late ProxyPlaybackSettings proxyPlaybackSettings;
    late ComskipSettings comskipSettings;

    setUp(() {
      viewSettingsService = ViewSettingsService();
      final secureStorage = _FakeSecureStorage();
      authNotifier = AuthNotifier(
        xtreamService: _FakeXtreamService(),
        secureStorage: secureStorage,
      );
      traktService = TraktService(storage: secureStorage);
      proxyPlaybackSettings = ProxyPlaybackSettings();
      comskipSettings = ComskipSettings();
    });

    tearDown(() {
      authNotifier.dispose();
      traktService.dispose();
      viewSettingsService.dispose();
      proxyPlaybackSettings.dispose();
      comskipSettings.dispose();
    });

    Future<void> pumpSettingsScreen(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SettingsScreen(
            authNotifier: authNotifier,
            traktService: traktService,
            sourceLabel: 'Test',
            isConfiguredOverride: true,
            viewSettingsService: viewSettingsService,
            proxyPlaybackSettings: proxyPlaybackSettings,
            comskipSettings: comskipSettings,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('renders view settings chips and persists layout', (
      tester,
    ) async {
      await pumpSettingsScreen(tester);

      final l = await AppLocalizations.delegate.load(const Locale('en'));
      expect(find.text(l.settingsView), findsOneWidget);
      expect(find.text(l.settingsLiveTvLayoutList), findsOneWidget);
      expect(find.text(l.settingsLiveTvLayoutGrid), findsOneWidget);
      expect(find.text(l.settingsLiveTvLayoutTimeline), findsOneWidget);
      expect(find.text(l.settingsEpgStartViewCurrentTime), findsOneWidget);
      expect(find.text(l.settingsEpgStartViewPrimeTime), findsOneWidget);

      final gridChip = find.widgetWithText(
        DpadInkWell,
        l.settingsLiveTvLayoutGrid,
      );
      await tester.ensureVisible(gridChip);
      await tester.pumpAndSettle();
      await tester.tap(gridChip);
      await tester.pumpAndSettle();

      expect(await viewSettingsService.liveTvLayout(), LiveTvLayout.grid);

      final primeChip = find.widgetWithText(
        DpadInkWell,
        l.settingsEpgStartViewPrimeTime,
      );
      await tester.ensureVisible(primeChip);
      await tester.pumpAndSettle();
      await tester.tap(primeChip);
      await tester.pumpAndSettle();

      expect(await viewSettingsService.epgStartView(), EpgStartView.primeTime);
    });
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/settings/settings_screen.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/auth_notifier.dart';
import 'package:m3u_tv/services/comskip_settings.dart';
import 'package:m3u_tv/services/introdb_settings.dart';
import 'package:m3u_tv/services/proxy_playback_settings.dart';
import 'package:m3u_tv/services/secure_storage.dart';
import 'package:m3u_tv/services/trakt_service.dart';
import 'package:m3u_tv/services/view_settings_service.dart';
import 'package:m3u_tv/services/xtream_service.dart';

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
    late IntroDbSettings introDbSettings;

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
      introDbSettings = IntroDbSettings();
    });

    tearDown(() {
      authNotifier.dispose();
      traktService.dispose();
      viewSettingsService.dispose();
      proxyPlaybackSettings.dispose();
      comskipSettings.dispose();
      introDbSettings.dispose();
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
            introDbSettings: introDbSettings,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// Navigates from the root settings list into the pushed Appearance
    /// sub-page, where the layout/EPG/filter rows now live (moved out of the
    /// old single-tab chip section).
    Future<void> openAppearancePage(
      WidgetTester tester,
      AppLocalizations l,
    ) async {
      await tester.tap(find.text(l.settingsAppearance));
      await tester.pumpAndSettle();
    }

    testWidgets('renders view settings rows and persists layout via picker', (
      tester,
    ) async {
      await pumpSettingsScreen(tester);
      final l = await AppLocalizations.delegate.load(const Locale('en'));

      await openAppearancePage(tester, l);
      expect(find.text(l.settingsLiveTvLayout), findsOneWidget);
      expect(find.text(l.settingsEpgStartView), findsOneWidget);
      expect(find.text(l.settingsFilterPersistence), findsOneWidget);

      await tester.tap(find.text(l.settingsLiveTvLayout));
      await tester.pumpAndSettle();
      expect(find.text(l.settingsLiveTvLayoutGrid), findsOneWidget);
      await tester.tap(find.text(l.settingsLiveTvLayoutGrid));
      await tester.pumpAndSettle();

      expect(await viewSettingsService.liveTvLayout(), LiveTvLayout.grid);

      await tester.tap(find.text(l.settingsEpgStartView));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l.settingsEpgStartViewPrimeTime));
      await tester.pumpAndSettle();

      expect(await viewSettingsService.epgStartView(), EpgStartView.primeTime);
    });

    testWidgets(
      'Filter Persistence defaults to Reset and toggles via switch row',
      (tester) async {
        await pumpSettingsScreen(tester);
        final l = await AppLocalizations.delegate.load(const Locale('en'));

        await openAppearancePage(tester, l);

        // Default state: rememberMediaSort is false → subtitle shows "Reset".
        expect(await viewSettingsService.rememberMediaSort(), isFalse);
        expect(find.text(l.settingsFilterPersistenceReset), findsOneWidget);

        final filterRow = find.text(l.settingsFilterPersistence);
        await tester.ensureVisible(filterRow);
        await tester.pumpAndSettle();
        await tester.tap(filterRow);
        await tester.pumpAndSettle();

        expect(await viewSettingsService.rememberMediaSort(), isTrue);
        expect(find.text(l.settingsFilterPersistenceRemember), findsOneWidget);

        await tester.ensureVisible(filterRow);
        await tester.pumpAndSettle();
        await tester.tap(filterRow);
        await tester.pumpAndSettle();

        expect(await viewSettingsService.rememberMediaSort(), isFalse);
      },
    );

    testWidgets('renders default start page row and persists via picker', (
      tester,
    ) async {
      await pumpSettingsScreen(tester);
      final l = await AppLocalizations.delegate.load(const Locale('en'));

      await openAppearancePage(tester, l);
      expect(find.text(l.settingsDefaultStartPage), findsOneWidget);

      await tester.tap(find.text(l.settingsDefaultStartPage));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l.navLiveTv));
      await tester.pumpAndSettle();

      expect(
        await viewSettingsService.defaultStartPage(),
        DefaultStartPage.liveTv,
      );
    });

    testWidgets(
      'TheIntroDB toggle defaults on and turns off from Integrations',
      (
        tester,
      ) async {
        await pumpSettingsScreen(tester);
        final l = await AppLocalizations.delegate.load(const Locale('en'));

        await tester.tap(find.text(l.settingsIntegrations));
        await tester.pumpAndSettle();

        expect(find.text(l.settingsIntroDb), findsOneWidget);
        expect(introDbSettings.enabled, isTrue);

        final introDbRow = find.text(l.settingsIntroDb);
        await tester.ensureVisible(introDbRow);
        await tester.pumpAndSettle();
        await tester.tap(introDbRow);
        await tester.pumpAndSettle();

        expect(introDbSettings.enabled, isFalse);
      },
    );
  });
}

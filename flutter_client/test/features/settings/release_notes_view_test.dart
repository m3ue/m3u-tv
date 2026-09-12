import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/settings/release_notes_view.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/app_version_service.dart';
import 'package:m3u_tv/services/release_notes_service.dart';
import 'package:m3u_tv/services/view_settings_service.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';
import 'package:m3u_tv/shared/image_quality_scope.dart';

class _FakeReleaseNotesService extends ReleaseNotesService {
  _FakeReleaseNotesService(this._releases);

  final List<ReleaseNote> _releases;

  @override
  Future<List<ReleaseNote>> fetch({bool forceRefresh = false}) async =>
      _releases;
}

class _FakeVersionService extends AppVersionService {
  _FakeVersionService(this._version);

  final String? _version;

  @override
  Future<String?> currentVersion() async => _version;
}

ReleaseNote _note(String tag, String body) => ReleaseNote(
  tag: tag,
  name: tag,
  body: body,
  htmlUrl: 'https://github.com/m3ue/m3u-tv/releases/tag/$tag',
  publishedAt: DateTime.utc(2026, 8, 2),
);

Future<AppLocalizations> _l() =>
    AppLocalizations.delegate.load(const Locale('en'));

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required List<ReleaseNote> releases,
    String? currentVersion,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 600,
            child: ReleaseNotesView(
              releaseNotesService: _FakeReleaseNotesService(releases),
              appVersionService: _FakeVersionService(currentVersion),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('lists versions, flags the current and newer ones', (
    tester,
  ) async {
    await pump(
      tester,
      currentVersion: '1.3.0',
      releases: [
        _note('v1.4.0', "## What's Changed\n- Added subtitles"),
        _note('v1.3.0', '- Older fix'),
        _note('v1.2.0', 'plain paragraph'),
      ],
    );
    final l = await _l();

    expect(find.widgetWithText(DpadInkWell, 'v1.4.0'), findsOneWidget);
    expect(find.widgetWithText(DpadInkWell, 'v1.2.0'), findsOneWidget);
    expect(find.text(l.settingsReleaseNotesCurrentBadge), findsOneWidget);
    expect(find.text(l.settingsReleaseNotesNewBadge), findsOneWidget);
    expect(
      find.text(l.settingsReleaseNotesYouAreOn('1.3.0')),
      findsOneWidget,
    );
    expect(find.text(l.settingsReleaseNotesNewerCount(1)), findsOneWidget);
  });

  testWidgets('shows the current version notes first, then follows selection', (
    tester,
  ) async {
    await pump(
      tester,
      currentVersion: '1.3.0',
      releases: [
        _note('v1.4.0', '- Added subtitles'),
        _note('v1.3.0', '- Older fix here'),
        _note('v1.2.0', 'plain paragraph text'),
      ],
    );

    // Lands on the running version's notes.
    expect(find.textContaining('Older fix here'), findsOneWidget);
    expect(find.textContaining('Added subtitles'), findsNothing);

    await tester.tap(find.widgetWithText(DpadInkWell, 'v1.2.0'));
    await tester.pumpAndSettle();
    expect(find.textContaining('plain paragraph text'), findsOneWidget);
  });

  testWidgets('shows a retry affordance when no releases load', (tester) async {
    await pump(tester, releases: const []);
    final l = await _l();

    expect(find.text(l.settingsReleaseNotesError), findsOneWidget);
    expect(
      find.widgetWithText(Container, l.settingsReleaseNotesRetry),
      findsNothing,
    );
    expect(find.text(l.settingsReleaseNotesRetry), findsOneWidget);
  });

  testWidgets('version rail rows do not overflow at Very Large display size', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: FontSizeScope(
            fontSize: AppFontSize.veryLarge,
            child: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(
                    FontSizeScope.scaleOf(context),
                  ),
                ),
                child: SizedBox(
                  width: 900,
                  height: 600,
                  child: ReleaseNotesView(
                    releaseNotesService: _FakeReleaseNotesService([
                      _note('v1.4.0', "## What's Changed\n- Added subtitles"),
                      _note('v1.3.0', '- Older fix'),
                    ]),
                    appVersionService: _FakeVersionService('1.3.0'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'narrow width collapses to a version dropdown with notes below, no overflow',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SizedBox(
              width: 360,
              height: 640,
              child: ReleaseNotesView(
                releaseNotesService: _FakeReleaseNotesService([
                  _note('v1.4.0', "## What's Changed\n- Added subtitles"),
                  _note('v1.3.0', '- Older fix here'),
                  _note('v1.2.0', 'plain paragraph text'),
                ]),
                appVersionService: _FakeVersionService('1.3.0'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final l = await _l();

      // Summary card collapses to just the status pill + a GitHub icon
      // button - the version/latest text didn't fit and got clipped anyway.
      expect(
        find.text(l.settingsReleaseNotesYouAreOn('1.3.0')),
        findsNothing,
      );
      expect(find.text(l.settingsReleaseNotesLatestIs('v1.4.0')), findsNothing);
      expect(find.text(l.settingsReleaseNotesNewerCount(1)), findsOneWidget);
      expect(find.byIcon(Icons.open_in_new), findsOneWidget);

      // No rail rendered; the dropdown button and current notes show instead.
      expect(find.widgetWithText(DpadInkWell, 'v1.2.0'), findsNothing);
      expect(find.widgetWithText(DpadInkWell, 'v1.3.0'), findsOneWidget);
      expect(find.textContaining('Older fix here'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Opening the picker lists every version and lets one be selected.
      await tester.tap(find.widgetWithText(DpadInkWell, 'v1.3.0'));
      await tester.pumpAndSettle();
      expect(find.text(l.settingsReleaseNotesSelectVersion), findsOneWidget);
      expect(find.widgetWithText(DpadInkWell, 'v1.2.0'), findsOneWidget);

      await tester.tap(find.widgetWithText(DpadInkWell, 'v1.2.0'));
      await tester.pumpAndSettle();
      expect(find.textContaining('plain paragraph text'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

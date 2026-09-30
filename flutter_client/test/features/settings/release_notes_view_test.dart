import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/settings/release_notes_view.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/app_version_service.dart';
import 'package:m3u_tv/services/release_notes_service.dart';
import 'package:m3u_tv/services/view_settings_service.dart';
import 'package:m3u_tv/shared/image_quality_scope.dart';
import 'package:qr_flutter/qr_flutter.dart';

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

const _changelog = '''
## What's Changed

### Features
- Add canary workflow (`fae2f6e`)
- bump flutter_cache_manager (#306) (`efa1234`)

### Bug Fixes
- Timeline scrubber on large scale (`e061396`)

### Maintenance
- Refactor settings screen (`cdd1ed8`)
- Update app screenshots (`cb97216`)
- Align related tiles (`35bf36a`)
''';

final List<ReleaseNote> _threeReleases = [
  _note('v1.4.0', '- Added subtitles'),
  _note('v1.3.0', '- Older fix here'),
  _note('v1.2.0', 'plain paragraph text'),
];

Future<AppLocalizations> _l() =>
    AppLocalizations.delegate.load(const Locale('en'));

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required List<ReleaseNote> releases,
    String? currentVersion,
    bool isTv = false,
    Size size = const Size(1000, 700),
    AppFontSize fontSize = AppFontSize.normal,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: FontSizeScope(
            fontSize: fontSize,
            child: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(
                    FontSizeScope.scaleOf(context),
                  ),
                ),
                child: Center(
                  child: SizedBox.fromSize(
                    size: size,
                    child: ReleaseNotesView(
                      releaseNotesService: _FakeReleaseNotesService(releases),
                      appVersionService: _FakeVersionService(currentVersion),
                      isTv: isTv,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('opens on the running version and shows the install status', (
    tester,
  ) async {
    await pump(tester, currentVersion: '1.3.0', releases: _threeReleases);
    final l = await _l();

    expect(find.text('v1.3.0'), findsOneWidget);
    expect(find.text(l.settingsReleaseNotesCurrentBadge), findsOneWidget);
    expect(find.textContaining('Older fix here'), findsOneWidget);
    expect(find.textContaining('Added subtitles'), findsNothing);
    expect(
      find.textContaining(l.settingsReleaseNotesNewerCount(1)),
      findsOneWidget,
    );
    expect(
      find.textContaining(l.settingsReleaseNotesYouAreOn('1.3.0')),
      findsOneWidget,
    );
  });

  testWidgets('shows the up-to-date status on the latest version', (
    tester,
  ) async {
    await pump(tester, currentVersion: '1.4.0', releases: _threeReleases);
    final l = await _l();

    expect(find.text(l.settingsReleaseNotesUpToDate), findsOneWidget);
    expect(
      find.textContaining(l.settingsReleaseNotesYouAreOn('1.4.0')),
      findsNothing,
    );
  });

  testWidgets('hides the chevron with no version beyond it', (tester) async {
    await pump(tester, currentVersion: '1.4.0', releases: _threeReleases);
    final l = await _l();

    bool visible(String tooltip) => tester
        .widget<Visibility>(
          find.ancestor(
            of: find.byTooltip(tooltip),
            matching: find.byType(Visibility),
          ),
        )
        .visible;

    // On the newest release: nothing newer.
    expect(visible(l.settingsReleaseNotesNewer), isFalse);
    expect(visible(l.settingsReleaseNotesOlder), isTrue);

    await tester.tap(find.byTooltip(l.settingsReleaseNotesOlder));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(l.settingsReleaseNotesOlder));
    await tester.pumpAndSettle();

    // On the oldest: the older chevron hides and focus lands on the title.
    expect(find.text('v1.2.0'), findsOneWidget);
    expect(visible(l.settingsReleaseNotesOlder), isFalse);
    expect(visible(l.settingsReleaseNotesNewer), isTrue);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'release-notes/version-button',
    );
  });

  testWidgets('the header arrows step to older and newer versions', (
    tester,
  ) async {
    await pump(tester, currentVersion: '1.3.0', releases: _threeReleases);
    final l = await _l();

    await tester.tap(find.byTooltip(l.settingsReleaseNotesOlder));
    await tester.pumpAndSettle();
    expect(find.text('v1.2.0'), findsOneWidget);
    expect(find.textContaining('plain paragraph text'), findsOneWidget);

    await tester.tap(find.byTooltip(l.settingsReleaseNotesNewer));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip(l.settingsReleaseNotesNewer));
    await tester.pumpAndSettle();
    expect(find.text('v1.4.0'), findsOneWidget);
    expect(find.text(l.settingsReleaseNotesNewBadge), findsOneWidget);
    expect(find.textContaining('Added subtitles'), findsOneWidget);
  });

  testWidgets('Left/Right on the focused notes switch versions', (
    tester,
  ) async {
    await pump(tester, currentVersion: '1.3.0', releases: _threeReleases);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('v1.4.0'), findsOneWidget);

    // Already on the newest: Right is swallowed, nothing changes.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(find.text('v1.4.0'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    expect(find.text('v1.2.0'), findsOneWidget);
  });

  testWidgets('renders a categorized changelog as cleaned-up sections', (
    tester,
  ) async {
    await pump(
      tester,
      currentVersion: '1.2.0',
      releases: [_note('v1.2.0', _changelog)],
    );
    final l = await _l();

    expect(find.text("What's Changed"), findsNothing);
    expect(find.text('Features'), findsOneWidget);
    expect(find.text('Bug Fixes'), findsOneWidget);
    expect(find.text('Maintenance'), findsOneWidget);

    // Commit hashes stripped, first letter capitalized, PR ref kept apart.
    expect(find.textContaining('fae2f6e'), findsNothing);
    expect(find.textContaining('Add canary workflow'), findsOneWidget);
    expect(find.textContaining('Bump flutter_cache_manager'), findsOneWidget);
    expect(find.textContaining('#306'), findsOneWidget);

    // Header summary counts features and fixes.
    expect(
      find.textContaining(l.settingsReleaseNotesFeatureCount(2)),
      findsOneWidget,
    );
    expect(
      find.textContaining(l.settingsReleaseNotesFixCount(1)),
      findsOneWidget,
    );

    // Maintenance is shown in full, not collapsed.
    expect(find.textContaining('Refactor settings screen'), findsOneWidget);
    expect(find.textContaining('Align related tiles'), findsOneWidget);
  });

  testWidgets('the version title opens a picker that switches versions', (
    tester,
  ) async {
    await pump(tester, currentVersion: '1.3.0', releases: _threeReleases);
    final l = await _l();

    await tester.tap(find.text('v1.3.0'));
    await tester.pumpAndSettle();
    expect(find.text(l.settingsReleaseNotesSelectVersion), findsOneWidget);

    await tester.tap(find.text('v1.2.0'));
    await tester.pumpAndSettle();
    expect(find.text(l.settingsReleaseNotesSelectVersion), findsNothing);
    expect(find.textContaining('plain paragraph text'), findsOneWidget);
  });

  testWidgets('TV shows remote hints and a QR code for GitHub', (
    tester,
  ) async {
    await pump(
      tester,
      currentVersion: '1.3.0',
      releases: _threeReleases,
      isTv: true,
    );
    final l = await _l();

    expect(find.text(l.settingsReleaseNotesHintVersions), findsOneWidget);
    expect(find.byType(QrImageView), findsNothing);

    await tester.tap(find.text(l.settingsReleaseNotesViewOnGithub));
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsOneWidget);
  });

  testWidgets('shows a retry affordance when no releases load', (tester) async {
    await pump(tester, releases: const []);
    final l = await _l();

    expect(find.text(l.settingsReleaseNotesError), findsOneWidget);
    expect(find.text(l.settingsReleaseNotesRetry), findsOneWidget);
  });

  testWidgets('no overflow at Very Large display size', (tester) async {
    await pump(
      tester,
      currentVersion: '1.2.0',
      releases: [_note('v1.3.0', _changelog), _note('v1.2.0', _changelog)],
      fontSize: AppFontSize.veryLarge,
      isTv: true,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone width keeps the version and status readable', (
    tester,
  ) async {
    await pump(
      tester,
      currentVersion: '1.2.0',
      releases: [_note('v1.3.0', _changelog), _note('v1.2.0', _changelog)],
      // The test font draws every glyph as a full em square (roughly twice
      // the real font's width), so Normal here is already a stress case.
      size: const Size(354, 700),
    );
    expect(tester.takeException(), isNull);

    bool truncated(Finder finder) =>
        tester.renderObject<RenderParagraph>(finder).didExceedMaxLines;

    expect(truncated(find.text('v1.2.0')), isFalse);

    // The status parts go on separate lines rather than being squeezed
    // onto one (pixel width isn't asserted - see the test-font note above).
    final l = await _l();
    expect(
      find.text(
        '${l.settingsReleaseNotesNewerCount(1)}\n'
        '${l.settingsReleaseNotesYouAreOn('1.2.0')}',
      ),
      findsOneWidget,
    );
  });
}

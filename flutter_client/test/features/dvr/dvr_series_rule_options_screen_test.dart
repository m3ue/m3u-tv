import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/dvr/dvr_series_rule_options_screen.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/domain_models.dart';

/// Builds a minimal MaterialApp wrapper with l10n + ProviderScope, with a
/// button that pushes the options screen via [openDvrSeriesRuleOptions].
Widget buildOptionsApp(WidgetBuilder pushButtonBuilder) {
  return ProviderScope(
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Builder(builder: pushButtonBuilder)),
    ),
  );
}

/// Fixture EpgShow with 2 channels and a next-airing episode on channel 2.
EpgShow buildShowWithNextAiring() {
  final nextAiring = DateTime.utc(2026, 8, 10, 20);
  return EpgShow(
    normalizedTitle: 'Test Show',
    displayTitle: 'Test Show',
    channelCount: 2,
    channels: [
      const EpgShowChannel(channelId: 1, channelName: 'Channel 1'),
      const EpgShowChannel(channelId: 2, channelName: 'Channel 2'),
    ],
    episodeCount: 10,
    nextAiringAt: nextAiring,
    recentEpisodes: [
      EpgShowEpisode(
        channelId: 1,
        channelName: 'Channel 1',
        title: 'Ep A',
        startTime: DateTime.utc(2026, 8, 9, 20),
        endTime: DateTime.utc(2026, 8, 9, 21),
      ),
      // This episode matches nextAiringAt and is on channel 2 — the next-airing channel.
      EpgShowEpisode(
        channelId: 2,
        channelName: 'Channel 2',
        title: 'Ep B',
        startTime: nextAiring, // matches show.nextAiringAt exactly
        endTime: DateTime.utc(2026, 8, 10, 21),
      ),
    ],
  );
}

/// Fixture EpgShow with channelCount == 1.
EpgShow buildShowSingleChannel() {
  return EpgShow(
    normalizedTitle: 'Single Channel Show',
    displayTitle: 'Single Channel Show',
    channelCount: 1,
    channels: [
      const EpgShowChannel(channelId: 99, channelName: 'Only Channel'),
    ],
    episodeCount: 5,
    nextAiringAt: DateTime.utc(2026, 8, 10, 20),
    recentEpisodes: [
      EpgShowEpisode(
        channelId: 99,
        channelName: 'Only Channel',
        title: 'Ep 1',
        startTime: DateTime.utc(2026, 8, 10, 20),
        endTime: DateTime.utc(2026, 8, 10, 21),
      ),
    ],
  );
}

/// Fixture EpgShow with channelCount > 1 but NO episode matches nextAiringAt,
/// so nextAiringChannelId returns null (falls back to "any channel").
EpgShow buildShowNoMatchingNextAiring() {
  return EpgShow(
    normalizedTitle: 'No Match Show',
    displayTitle: 'No Match Show',
    channelCount: 2,
    channels: [
      const EpgShowChannel(channelId: 1, channelName: 'Channel 1'),
      const EpgShowChannel(channelId: 2, channelName: 'Channel 2'),
    ],
    episodeCount: 10,
    nextAiringAt: DateTime.utc(2026, 8, 10, 20),
    recentEpisodes: [
      // No episode has startTime == nextAiringAt
      EpgShowEpisode(
        channelId: 1,
        channelName: 'Channel 1',
        title: 'Ep A',
        startTime: DateTime.utc(2026, 8, 9, 20),
        endTime: DateTime.utc(2026, 8, 9, 21),
      ),
    ],
  );
}

void main() {
  // ─────────────────────────────────────────────────────────────────────────────
  // Test 3 — Screen omit-to-inherit defaults
  // ─────────────────────────────────────────────────────────────────────────────
  ///
  /// Documents the screen's default state at initState:
  ///   _selectedChannelId   = nextAiringChannelId(show)   → may be null
  ///   _selectedSeriesMode  = null                        → omit
  ///   _selectedMatchMode   = DvrMatchMode.contains       → explicitly set
  ///   _keepLastController  = empty                       → null (omit)
  ///   _priorityController  = blank (hint '50')            → null (omit)
  ///   _startEarlyController = empty                      → null (omit)
  ///   _endLateController   = empty                       → null (omit)
  group('Test 3 — Screen omit-to-inherit defaults', () {
    testWidgets(
      'Save without touching any control returns correct omit/default values',
      (
        tester,
      ) async {
        // Show with 2 channels but NO episode matching nextAiringAt → channelId=null (any).
        final testShow = buildShowNoMatchingNextAiring();

        DvrSeriesRuleOptions? result;

        await tester.pumpWidget(
          buildOptionsApp(
            (context) => ElevatedButton(
              onPressed: () async {
                result = await openDvrSeriesRuleOptions(
                  context,
                  show: testShow,
                );
              },
              child: const Text('Open Options'),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Open Options'));
        await tester.pumpAndSettle();

        final screenContext = tester.element(
          find.byType(DvrSeriesRuleOptionsScreen),
        );
        final l10n = AppLocalizations.of(screenContext);
        await tester.tap(find.text(l10n.dvrSeriesSave));
        await tester.pumpAndSettle();

        expect(result, isNotNull);

        // channelId: no episode matched nextAiringAt → nextAiringChannelId returned null.
        expect(
          result!.channelId,
          isNull,
          reason: 'channelId should be null (any channel)',
        );

        // seriesMode: null init → omit.
        expect(
          result!.seriesMode,
          isNull,
          reason: 'seriesMode should be null (omit)',
        );

        // matchMode: explicitly set to DvrMatchMode.contains (NOT null/omit).
        expect(
          result!.matchMode,
          equals(DvrMatchMode.contains),
          reason: 'matchMode should be DvrMatchMode.contains (screen default)',
        );

        expect(
          result!.keepLast,
          isNull,
          reason: 'keepLast should be null (empty field)',
        );
        expect(
          result!.priority,
          isNull,
          reason: 'priority should be null (omit)',
        );
        expect(
          result!.startEarlySeconds,
          isNull,
          reason: 'startEarlySeconds should be null',
        );
        expect(
          result!.endLateSeconds,
          isNull,
          reason: 'endLateSeconds should be null',
        );
      },
    );
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // Test 4 — Channel picker hidden when channelCount == 1; next-airing default
  // ─────────────────────────────────────────────────────────────────────────────
  group('Test 4 — Channel picker visibility and next-airing default', () {
    testWidgets('channelCount == 1 hides the channel picker section', (
      tester,
    ) async {
      final testShow = buildShowSingleChannel();

      await tester.pumpWidget(
        buildOptionsApp(
          (context) => ElevatedButton(
            onPressed: () async {
              await openDvrSeriesRuleOptions(context, show: testShow);
            },
            child: const Text('Open Options'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Options'));
      await tester.pumpAndSettle();

      final screenContext = tester.element(
        find.byType(DvrSeriesRuleOptionsScreen),
      );
      final l10n = AppLocalizations.of(screenContext);

      // "Any channel" pill must not appear (picker is hidden).
      expect(
        find.text(l10n.dvrSeriesAnyChannel),
        findsNothing,
        reason: 'Any channel pill should not appear when channelCount == 1',
      );

      // The channel section header must not appear.
      expect(
        find.text(l10n.dvrSeriesChannel),
        findsNothing,
        reason:
            'Channel section header should not appear when channelCount == 1',
      );

      // Other sections must still be present.
      expect(find.text(l10n.dvrSeriesMode), findsOneWidget);
      expect(find.text(l10n.dvrSeriesMatchMode), findsOneWidget);
    });

    testWidgets(
      'channelId defaults to the next-airing episode channel when matched',
      (
        tester,
      ) async {
        // Show: 2 channels, one episode with startTime == nextAiringAt on channel 2.
        final testShow = buildShowWithNextAiring();

        DvrSeriesRuleOptions? result;

        await tester.pumpWidget(
          buildOptionsApp(
            (context) => ElevatedButton(
              onPressed: () async {
                result = await openDvrSeriesRuleOptions(
                  context,
                  show: testShow,
                );
              },
              child: const Text('Open Options'),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Open Options'));
        await tester.pumpAndSettle();

        // Tap Save without changing anything.
        final screenContext = tester.element(
          find.byType(DvrSeriesRuleOptionsScreen),
        );
        final l10n = AppLocalizations.of(screenContext);
        await tester.tap(find.text(l10n.dvrSeriesSave));
        await tester.pumpAndSettle();

        expect(result, isNotNull);
        // The next-airing episode is on channel 2.
        expect(
          result!.channelId,
          equals(2),
          reason: "channelId should be 2 (the next-airing episode's channel)",
        );
      },
    );
  });

  // ─────────────────────────────────────────────────────────────────────────────
  // Test 17 — Edit mode pre-fill from an existing DvrSeriesRule
  // ─────────────────────────────────────────────────────────────────────────────
  group('Test 17 — Screen edit mode pre-fills from an existing rule', () {
    testWidgets('save returns the rule fields pre-filled, not defaults', (
      tester,
    ) async {
      const rule = DvrSeriesRule(
        id: 11,
        channelId: 8,
        channelName: 'Channel Eight',
        seriesTitle: 'Prefilled Show',
        matchMode: DvrMatchMode.exact,
        seriesMode: DvrSeriesMode.newFlag,
        keepLast: 4,
        priority: 70,
        enabled: true,
        enableComskip: false,
        startEarlySeconds: 120,
        endLateSeconds: 180,
      );

      DvrSeriesRuleOptions? result;

      await tester.pumpWidget(
        buildOptionsApp(
          (context) => ElevatedButton(
            onPressed: () async {
              result = await openDvrSeriesRuleOptions(
                context,
                show: buildShowNoMatchingNextAiring(),
                initialRule: rule,
              );
            },
            child: const Text('Open Options'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open Options'));
      await tester.pumpAndSettle();

      final screenContext = tester.element(
        find.byType(DvrSeriesRuleOptionsScreen),
      );
      final l10n = AppLocalizations.of(screenContext);
      await tester.tap(find.text(l10n.dvrSeriesSave));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(
        result!.channelId,
        equals(8),
        reason: 'edit mode pre-fills the rule channel',
      );
      expect(
        result!.seriesMode,
        equals(DvrSeriesMode.newFlag),
        reason: 'edit mode pre-fills the rule series mode',
      );
      expect(
        result!.matchMode,
        equals(DvrMatchMode.exact),
        reason: 'edit mode pre-fills the rule match mode',
      );
      expect(result!.keepLast, equals(4));
      expect(result!.priority, equals(70));
      expect(result!.startEarlySeconds, equals(120));
      expect(result!.endLateSeconds, equals(180));
    });
  });
}

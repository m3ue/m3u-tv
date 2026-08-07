// B8: Toggle state — verifies that ShowDetailScreen renders the "Series rule
// active" state (not the Record Series button) when hasSeriesRule is true and
// a matching rule exists in dvrSeriesRulesProvider.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/shows/show_detail_screen.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/xtream_service.dart';

void main() {
  testWidgets(
    'hasSeriesRule:true with matching rule shows active state, not Record Series',
    (tester) async {
      const ruleId = 42;
      const displayTitle = 'Test Show Alpha';

      // A rule that matches the EpgShow by id (seriesRuleId = ruleId).
      const matchingRule = DvrSeriesRule(
        id: ruleId,
        channelId: 1,
        seriesTitle: displayTitle,
        matchMode: DvrMatchMode.contains,
        seriesMode: DvrSeriesMode.all,
        enabled: true,
        enableComskip: false,
      );

      const testShow = EpgShow(
        normalizedTitle: 'test show alpha',
        displayTitle: displayTitle,
        channelCount: 3,
        channels: [
          EpgShowChannel(channelId: 1, channelName: 'Channel One'),
          EpgShowChannel(channelId: 2, channelName: 'Channel Two'),
        ],
        episodeCount: 12,
        recentEpisodes: [],
        hasSeriesRule: true,
        seriesRuleId: ruleId,
      );

      // Pumps ShowDetailScreen with the provider overridden to return our rule.
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            // Override dvrSeriesRulesProvider directly so we don't need a
            // full AppStateController mock.
            dvrSeriesRulesProvider.overrideWith((_) => [matchingRule]),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ShowDetailScreen(
              show: testShow,
              onRecordSeries:
                  ({
                    channelId,
                    required title,
                    matchMode,
                    seriesMode,
                    keepLast,
                    priority,
                    startEarlySeconds,
                    endLateSeconds,
                  }) async => CreateDvrSeriesRuleOutcome.created,
              onDeleteSeriesRule: (_) async {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // "Series rule active" label — exactly one.
      expect(
        find.text('Series rule active'),
        findsOneWidget,
      );

      // Delete affordance icon — exactly one.
      expect(
        find.byIcon(Icons.delete_outline),
        findsOneWidget,
      );

      // Record Series button — not present.
      expect(
        find.text('Record Series'),
        findsNothing,
      );

      // FilledButton is not present (the one-tap button is replaced).
      expect(
        find.byType(FilledButton),
        findsNothing,
      );
    },
  );

  testWidgets(
    'hasSeriesRule:false renders the Record Series button (smoke test)',
    (tester) async {
      const testShow = EpgShow(
        normalizedTitle: 'another show',
        displayTitle: 'Another Show',
        channelCount: 1,
        channels: [
          EpgShowChannel(channelId: 5, channelName: 'Channel Five'),
        ],
        episodeCount: 4,
        recentEpisodes: [],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            dvrSeriesRulesProvider.overrideWith((_) => const []),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: ShowDetailScreen(
              show: testShow,
              onRecordSeries:
                  ({
                    channelId,
                    required title,
                    matchMode,
                    seriesMode,
                    keepLast,
                    priority,
                    startEarlySeconds,
                    endLateSeconds,
                  }) async => CreateDvrSeriesRuleOutcome.created,
              onDeleteSeriesRule: (_) async {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      // No "Series rule active" text when there's no rule.
      expect(find.text('Series rule active'), findsNothing);

      // Record Series button IS present.
      expect(find.text('Record Series'), findsOneWidget);

      // Delete icon is NOT present.
      expect(find.byIcon(Icons.delete_outline), findsNothing);
    },
  );
}

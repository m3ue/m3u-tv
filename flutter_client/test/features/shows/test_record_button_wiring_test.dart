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
    'Record Series button invokes onRecordSeries with next-airing channel and display title',
    (tester) async {
      final nextAiring = DateTime.utc(2026, 8, 10, 20);
      final testShow = EpgShow(
        normalizedTitle: 'wired show',
        displayTitle: 'Wired Show',
        channelCount: 3,
        channels: const [
          EpgShowChannel(channelId: 7, channelName: 'Channel Seven'),
          EpgShowChannel(channelId: 8, channelName: 'Channel Eight'),
        ],
        episodeCount: 5,
        nextAiringAt: nextAiring,
        recentEpisodes: [
          EpgShowEpisode(
            channelId: 8,
            channelName: 'Channel Eight',
            title: 'Next Airing Ep',
            startTime: nextAiring,
            endTime: DateTime.utc(2026, 8, 10, 21),
          ),
        ],
      );

      int? capturedChannelId;
      String? capturedTitle;
      DvrMatchMode? capturedMatchMode;
      DvrSeriesMode? capturedSeriesMode;
      int? capturedKeepLast;
      int? capturedPriority;
      int? capturedStartEarly;
      int? capturedEndLate;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [dvrSeriesRulesProvider.overrideWith((_) => const [])],
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
                  }) async {
                    capturedChannelId = channelId;
                    capturedTitle = title;
                    capturedMatchMode = matchMode;
                    capturedSeriesMode = seriesMode;
                    capturedKeepLast = keepLast;
                    capturedPriority = priority;
                    capturedStartEarly = startEarlySeconds;
                    capturedEndLate = endLateSeconds;
                    return CreateDvrSeriesRuleOutcome.created;
                  },
              onDeleteSeriesRule: (_) async {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.text('Record Series'));
      await tester.pumpAndSettle();

      expect(
        capturedChannelId,
        8,
        reason: 'one-tap defaults to next-airing channel, not channels.first',
      );
      expect(capturedTitle, 'Wired Show');
      expect(capturedMatchMode, isNull);
      expect(capturedSeriesMode, isNull);
      expect(capturedKeepLast, isNull);
      expect(capturedPriority, isNull);
      expect(capturedStartEarly, isNull);
      expect(capturedEndLate, isNull);
    },
  );

  testWidgets(
    'Options sheet with any-channel passes channelId null through to onRecordSeries',
    (tester) async {
      const testShow = EpgShow(
        normalizedTitle: 'any channel show',
        displayTitle: 'Any Channel Show',
        channelCount: 2,
        channels: [
          EpgShowChannel(channelId: 7, channelName: 'Channel Seven'),
          EpgShowChannel(channelId: 8, channelName: 'Channel Eight'),
        ],
        episodeCount: 5,
        recentEpisodes: [],
      );

      int? capturedChannelId;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [dvrSeriesRulesProvider.overrideWith((_) => const [])],
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
                  }) async {
                    capturedChannelId = channelId;
                    return CreateDvrSeriesRuleOutcome.created;
                  },
              onDeleteSeriesRule: (_) async {},
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      final l10n = AppLocalizations.of(
        tester.element(find.byType(ShowDetailScreen)),
      );

      await tester.tap(find.text(l10n.dvrSeriesOptions));
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.dvrSeriesAnyChannel));
      await tester.pumpAndSettle();

      await tester.tap(find.text(l10n.dvrSeriesSave));
      await tester.pumpAndSettle();

      expect(
        capturedChannelId,
        isNull,
        reason:
            'any-channel (null) must pass through, not pin to first channel',
      );
    },
  );
}

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/shows/show_detail_screen.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  // Fixed future window so the per-row end-timer never fires during a test.
  // Anywhere later than now() + a few minutes is fine; an hour keeps the
  // 1-hour-future end safely beyond the typical widget-test runtime.
  final episode = EpgShowEpisode(
    channelId: 8,
    channelName: 'Channel Eight',
    title: 'Future Ep',
    startTime: DateTime.now().add(const Duration(hours: 1)),
    endTime: DateTime.now().add(const Duration(hours: 2)),
  );

  EpgShow testShow({List<EpgShowEpisode> episodes = const []}) => EpgShow(
    normalizedTitle: 'scheduled-show',
    displayTitle: 'Scheduled Show',
    channelCount: 1,
    channels: const [
      EpgShowChannel(channelId: 8, channelName: 'Channel Eight'),
    ],
    episodeCount: episodes.length,
    recentEpisodes: episodes,
  );

  DvrRecording recording({
    int? channelId = 8,
    required DateTime? scheduledStart,
    required DateTime? scheduledEnd,
  }) => DvrRecording(
    uuid:
        'uuid-${channelId ?? 'null'}-${scheduledStart?.millisecondsSinceEpoch ?? 0}',
    title: 'Existing Recording',
    status: DvrRecordingStatus.scheduled,
    channelId: channelId,
    channelName: 'Channel Eight',
    scheduledStart: scheduledStart,
    scheduledEnd: scheduledEnd,
  );

  Future<void> pumpScreen(
    WidgetTester tester, {
    required EpgShow show,
    List<DvrRecording> recordings = const [],
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dvrSeriesRulesProvider.overrideWith((_) => const []),
          dvrRecordingsProvider.overrideWith((_) => recordings),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ShowDetailScreen(show: show),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder scheduledBadge(WidgetTester tester) {
    final l10n = AppLocalizations.of(
      tester.element(find.byType(ShowDetailScreen)),
    );
    return find.text(l10n.showScheduled);
  }

  testWidgets(
    'shows Scheduled badge when a recording window overlaps the episode',
    (tester) async {
      await pumpScreen(
        tester,
        show: testShow(episodes: [episode]),
        recordings: [
          recording(
            scheduledStart: episode.startTime,
            scheduledEnd: episode.endTime,
          ),
        ],
      );

      expect(scheduledBadge(tester), findsOneWidget);
    },
  );

  testWidgets(
    'shows Scheduled badge when the recording is padded backward by '
    'start_early_seconds beyond the 1-minute singular tolerance',
    (tester) async {
      // 5 minutes of padding — the singular `scheduleDvrAiring` return-match
      // only tolerates 1 minute, so this case would have been missed by any
      // helper built on near-exact start-time equality. The new overlap
      // helper must still match.
      await pumpScreen(
        tester,
        show: testShow(episodes: [episode]),
        recordings: [
          recording(
            scheduledStart: episode.startTime.subtract(
              const Duration(minutes: 5),
            ),
            scheduledEnd: episode.endTime,
          ),
        ],
      );

      expect(scheduledBadge(tester), findsOneWidget);
    },
  );

  testWidgets(
    'does NOT show Scheduled badge when the recording is on a different '
    'channel, even at the same time',
    (tester) async {
      await pumpScreen(
        tester,
        show: testShow(episodes: [episode]),
        recordings: [
          recording(
            channelId: 9,
            scheduledStart: episode.startTime,
            scheduledEnd: episode.endTime,
          ),
        ],
      );

      expect(scheduledBadge(tester), findsNothing);
    },
  );

  testWidgets(
    'does NOT show Scheduled badge when the recording has null '
    'scheduledStart/End ("cannot confirm" semantics)',
    (tester) async {
      // The provider yields a recording whose window can't be checked
      // (both timestamps null). Overlap match must return false rather than
      // locking out a still-seeding recording from being scheduled.
      await pumpScreen(
        tester,
        show: testShow(episodes: [episode]),
        recordings: [
          recording(scheduledStart: null, scheduledEnd: null),
        ],
      );

      expect(scheduledBadge(tester), findsNothing);
    },
  );
}

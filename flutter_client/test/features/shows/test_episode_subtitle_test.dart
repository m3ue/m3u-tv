import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/shows/show_detail_screen.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  EpgShowEpisode episode({String? subtitle}) => EpgShowEpisode(
    channelId: 8,
    channelName: 'Channel Eight',
    title: 'Show Title',
    subtitle: subtitle,
    startTime: DateTime.utc(2026, 1, 1, 12),
    endTime: DateTime.utc(2026, 1, 1, 13),
  );

  EpgShow testShow(List<EpgShowEpisode> episodes) => EpgShow(
    normalizedTitle: 'wired show',
    displayTitle: 'Wired Show',
    channelCount: 1,
    channels: const [
      EpgShowChannel(channelId: 8, channelName: 'Channel Eight'),
    ],
    episodeCount: episodes.length,
    recentEpisodes: episodes,
  );

  Future<void> pumpScreen(WidgetTester tester, EpgShow show) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dvrSeriesRulesProvider.overrideWith((_) => const []),
          dvrRecordingsProvider.overrideWith((_) => const []),
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

  testWidgets(
    'renders episode subtitle when present, hiding the show title',
    (tester) async {
      await pumpScreen(
        tester,
        testShow([episode(subtitle: 'Episode 1: Pilot')]),
      );

      expect(find.text('Episode 1: Pilot'), findsOneWidget);
      expect(find.text('Show Title'), findsNothing);
    },
  );

  testWidgets('falls back to show title when subtitle is null', (tester) async {
    await pumpScreen(tester, testShow([episode()]));

    expect(find.text('Show Title'), findsOneWidget);
    expect(find.text('Episode 1: Pilot'), findsNothing);
  });
}

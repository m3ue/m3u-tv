import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/shows/show_detail_screen.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  final futureEpisode = EpgShowEpisode(
    channelId: 8,
    channelName: 'Channel Eight',
    title: 'Future Ep',
    startTime: DateTime.now().add(const Duration(hours: 1)),
    endTime: DateTime.now().add(const Duration(hours: 2)),
  );
  final pastEpisode = EpgShowEpisode(
    channelId: 9,
    channelName: 'Channel Nine',
    title: 'Past Ep',
    startTime: DateTime.now().subtract(const Duration(hours: 2)),
    endTime: DateTime.now().subtract(const Duration(hours: 1)),
  );

  EpgShow testShow({required List<EpgShowEpisode> episodes}) => EpgShow(
    normalizedTitle: 'wired show',
    displayTitle: 'Wired Show',
    channelCount: 2,
    channels: const [
      EpgShowChannel(channelId: 7, channelName: 'Channel Seven'),
      EpgShowChannel(channelId: 8, channelName: 'Channel Eight'),
    ],
    episodeCount: episodes.length,
    recentEpisodes: episodes,
  );

  Future<void> pumpScreen(
    WidgetTester tester, {
    required EpgShow show,
    Future<DvrRecording?> Function(EpgShowEpisode episode)? onScheduleEpisode,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          dvrSeriesRulesProvider.overrideWith((_) => const []),
          dvrRecordingsProvider.overrideWith((_) => const []),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ShowDetailScreen(
            show: show,
            onScheduleEpisode: onScheduleEpisode,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder recordIcon(WidgetTester tester) {
    final l10n = AppLocalizations.of(
      tester.element(find.byType(ShowDetailScreen)),
    );
    return find.byTooltip(l10n.liveTvRecord);
  }

  testWidgets(
    'tapping an episode record icon invokes onScheduleEpisode with that episode',
    (tester) async {
      EpgShowEpisode? captured;
      await pumpScreen(
        tester,
        show: testShow(episodes: [futureEpisode, pastEpisode]),
        onScheduleEpisode: (episode) async {
          captured = episode;
          return null;
        },
      );

      // Only the future episode gets the affordance; the past one is over.
      expect(recordIcon(tester), findsOneWidget);

      await tester.tap(recordIcon(tester));
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      expect(captured!.channelId, futureEpisode.channelId);
      expect(captured!.title, futureEpisode.title);
      expect(captured!.startTime, futureEpisode.startTime);
      expect(captured!.endTime, futureEpisode.endTime);

      final l10n = AppLocalizations.of(
        tester.element(find.byType(ShowDetailScreen)),
      );
      expect(
        find.text(l10n.appRecordingScheduled(futureEpisode.title)),
        findsOneWidget,
        reason: 'success SnackBar must surface after the schedule completes',
      );
    },
  );

  testWidgets(
    'record icon is absent when onScheduleEpisode is not wired',
    (tester) async {
      await pumpScreen(
        tester,
        show: testShow(episodes: [futureEpisode]),
      );

      expect(recordIcon(tester), findsNothing);
    },
  );

  testWidgets(
    'record icon is absent for an airing that has already ended',
    (tester) async {
      await pumpScreen(
        tester,
        show: testShow(episodes: [pastEpisode]),
        onScheduleEpisode: (episode) async => null,
      );

      expect(recordIcon(tester), findsNothing);
    },
  );

  testWidgets(
    'double-tap guard: a second tap while scheduling is in flight is a no-op',
    (tester) async {
      final inFlight = Completer<DvrRecording?>();
      var invocations = 0;
      await pumpScreen(
        tester,
        show: testShow(episodes: [futureEpisode]),
        onScheduleEpisode: (episode) {
          invocations += 1;
          return inFlight.future;
        },
      );

      await tester.tap(recordIcon(tester));
      await tester.pump();
      expect(invocations, 1);

      // The request is still in flight; the button is disabled, so a second
      // tap (or fast double-tap) must not reach the callback again.
      await tester.tap(recordIcon(tester), warnIfMissed: false);
      await tester.pump();
      expect(invocations, 1);

      inFlight.complete();
      await tester.pumpAndSettle();
      expect(invocations, 1);
    },
  );

  testWidgets(
    'schedule failure surfaces the appRecordingFailed SnackBar',
    (tester) async {
      await pumpScreen(
        tester,
        show: testShow(episodes: [futureEpisode]),
        onScheduleEpisode: (episode) async {
          throw StateError('server rejected');
        },
      );

      await tester.tap(recordIcon(tester));
      await tester.pumpAndSettle();

      final l10n = AppLocalizations.of(
        tester.element(find.byType(ShowDetailScreen)),
      );
      expect(
        find.text(l10n.appRecordingFailed('Bad state: server rejected')),
        findsOneWidget,
        reason: 'failure SnackBar must surface the thrown error',
      );
    },
  );
}

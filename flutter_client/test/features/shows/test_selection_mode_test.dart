import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/shows/show_detail_screen.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:m3u_tv/services/app_state_controller.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/shared/app_button.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  // Each episode starts 1 hour apart in the future so the per-row end-timer
  // (rebuilds the row when the airing ends) never fires during a test.
  EpgShowEpisode ep(int n) => EpgShowEpisode(
    channelId: 8,
    channelName: 'Channel Eight',
    title: 'Ep $n',
    startTime: DateTime.now().add(Duration(hours: n)),
    endTime: DateTime.now().add(Duration(hours: n + 1)),
  );

  EpgShow testShow({List<EpgShowEpisode> episodes = const []}) => EpgShow(
    normalizedTitle: 'selectable-show',
    displayTitle: 'Selectable Show',
    channelCount: 1,
    channels: const [
      EpgShowChannel(channelId: 8, channelName: 'Channel Eight'),
    ],
    episodeCount: episodes.length,
    recentEpisodes: episodes,
  );

  Future<void> pumpScreen(
    WidgetTester tester, {
    required EpgShow show,
    List<DvrRecording> recordings = const [],
    Future<List<DvrAiringScheduleResult>> Function(List<EpgShowEpisode>)?
    onScheduleEpisodes,
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
          home: ShowDetailScreen(
            show: show,
            onScheduleEpisodes: onScheduleEpisodes,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  AppLocalizations l10n(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(ShowDetailScreen)));

  Finder cancelButton(WidgetTester tester) => find.text(l10n(tester).cancel);

  Finder recordButtonLabel(WidgetTester tester, int count) =>
      find.text(l10n(tester).showBatchRecord(count));

  // Returns the [_SelectionActionsBar]'s Record button widget so a test can
  // assert its onPressed state without scraping semantics.
  AppButton recordButtonWidget(WidgetTester tester, int count) {
    final labelFinder = recordButtonLabel(tester, count);
    final buttonFinder = find.ancestor(
      of: labelFinder,
      matching: find.byType(AppButton),
    );
    return tester.widget<AppButton>(buttonFinder);
  }

  testWidgets(
    'long-pressing a row enters selection mode and surfaces the action bar',
    (tester) async {
      await pumpScreen(
        tester,
        show: testShow(episodes: [ep(1), ep(2)]),
        onScheduleEpisodes: (_) async => [],
      );

      // Initially no action bar; the user is in normal mode.
      expect(cancelButton(tester), findsNothing);

      await tester.longPress(find.text('Ep 1'));
      await tester.pumpAndSettle();

      // Action bar now visible, Record button label reflects the seed row.
      expect(cancelButton(tester), findsOneWidget);
      expect(recordButtonLabel(tester, 1), findsOneWidget);
    },
  );

  testWidgets(
    'in selection mode, tapping a row toggles its selection',
    (tester) async {
      await pumpScreen(
        tester,
        show: testShow(episodes: [ep(1), ep(2), ep(3)]),
        onScheduleEpisodes: (_) async => [],
      );

      await tester.longPress(find.text('Ep 1'));
      await tester.pumpAndSettle();
      expect(recordButtonLabel(tester, 1), findsOneWidget);

      // Tap Ep 2 → 2 selected.
      await tester.tap(find.text('Ep 2'));
      await tester.pumpAndSettle();
      expect(recordButtonLabel(tester, 2), findsOneWidget);

      // Tap Ep 1 (the seed row) → 1 selected (only Ep 2 remains).
      await tester.tap(find.text('Ep 1'));
      await tester.pumpAndSettle();
      expect(recordButtonLabel(tester, 1), findsOneWidget);
    },
  );

  testWidgets(
    'Record button is disabled when the selection is empty (count = 0)',
    (tester) async {
      await pumpScreen(
        tester,
        show: testShow(episodes: [ep(1)]),
        onScheduleEpisodes: (_) async => [],
      );

      // Enter mode with Ep 1 selected.
      await tester.longPress(find.text('Ep 1'));
      await tester.pumpAndSettle();

      // Deselect Ep 1 by tapping it.
      await tester.tap(find.text('Ep 1'));
      await tester.pumpAndSettle();

      // Label shows "Record (0)" but the button itself is disabled.
      expect(recordButtonLabel(tester, 0), findsOneWidget);
      expect(recordButtonWidget(tester, 0).onPressed, isNull);
    },
  );

  testWidgets(
    'Cancel exits selection mode and clears the action bar',
    (tester) async {
      await pumpScreen(
        tester,
        show: testShow(episodes: [ep(1), ep(2)]),
        onScheduleEpisodes: (_) async => [],
      );

      await tester.longPress(find.text('Ep 1'));
      await tester.pumpAndSettle();
      expect(cancelButton(tester), findsOneWidget);

      await tester.tap(cancelButton(tester));
      await tester.pumpAndSettle();

      expect(cancelButton(tester), findsNothing);
      expect(recordButtonLabel(tester, 0), findsNothing);
    },
  );

  testWidgets(
    'null onScheduleEpisodes: long-press does NOT enter selection mode',
    (tester) async {
      await pumpScreen(
        tester,
        show: testShow(episodes: [ep(1)]),
        // onScheduleEpisodes left null; selection mode is unavailable.
      );

      await tester.longPress(find.text('Ep 1'));
      await tester.pumpAndSettle();

      // No action bar should ever surface.
      expect(cancelButton(tester), findsNothing);
      expect(recordButtonLabel(tester, 1), findsNothing);
    },
  );

  testWidgets(
    'already-scheduled rows are excluded from selection (long-press is a no-op)',
    (tester) async {
      // A recording that covers Ep 1's window: Ep 1 should be excluded.
      final recording = DvrRecording(
        uuid: 'uuid-scheduled',
        title: 'Ep 1',
        status: DvrRecordingStatus.scheduled,
        channelId: 8,
        channelName: 'Channel Eight',
        scheduledStart: ep(1).startTime,
        scheduledEnd: ep(1).endTime,
      );

      await pumpScreen(
        tester,
        show: testShow(episodes: [ep(1), ep(2)]),
        recordings: [recording],
        onScheduleEpisodes: (_) async => [],
      );

      // Long-press Ep 1 (already-scheduled): should not enter mode.
      await tester.longPress(find.text('Ep 1'));
      await tester.pumpAndSettle();
      expect(cancelButton(tester), findsNothing);

      // Long-press Ep 2 (selectable): should enter mode.
      await tester.longPress(find.text('Ep 2'));
      await tester.pumpAndSettle();
      expect(cancelButton(tester), findsOneWidget);
      expect(recordButtonLabel(tester, 1), findsOneWidget);
    },
  );

  testWidgets(
    'an already-ended episode cannot be long-pressed into selection mode',
    (tester) async {
      final endedEpisode = EpgShowEpisode(
        channelId: 8,
        channelName: 'Channel Eight',
        title: 'Ep Past',
        startTime: DateTime.now().subtract(const Duration(hours: 2)),
        endTime: DateTime.now().subtract(const Duration(hours: 1)),
      );

      await pumpScreen(
        tester,
        show: testShow(episodes: [endedEpisode, ep(1)]),
        onScheduleEpisodes: (_) async => [],
      );

      // The single-item Record button already hides for ended episodes; this
      // asserts the batch entry point (long-press) respects the same rule.
      await tester.longPress(find.text('Ep Past'));
      await tester.pumpAndSettle();
      expect(cancelButton(tester), findsNothing);

      await tester.longPress(find.text('Ep 1'));
      await tester.pumpAndSettle();
      expect(cancelButton(tester), findsOneWidget);
      expect(recordButtonLabel(tester, 1), findsOneWidget);
    },
  );

  testWidgets(
    'a recording that only touches (does not overlap) an episode does not '
    'mark it already-scheduled',
    (tester) async {
      // Recording for Ep 1 ends exactly when Ep 2 starts (back-to-back
      // airings on the same channel). Ep 2 must remain selectable.
      final recording = DvrRecording(
        uuid: 'uuid-back-to-back',
        title: 'Ep 1',
        status: DvrRecordingStatus.scheduled,
        channelId: 8,
        channelName: 'Channel Eight',
        scheduledStart: ep(1).startTime,
        scheduledEnd: ep(2).startTime,
      );

      await pumpScreen(
        tester,
        show: testShow(episodes: [ep(1), ep(2)]),
        recordings: [recording],
        onScheduleEpisodes: (_) async => [],
      );

      await tester.longPress(find.text('Ep 2'));
      await tester.pumpAndSettle();
      expect(cancelButton(tester), findsOneWidget);
      expect(recordButtonLabel(tester, 1), findsOneWidget);
    },
  );

  testWidgets(
    'double-tapping Record (N) only fires onScheduleEpisodes once',
    (tester) async {
      var callCount = 0;
      final completer = Completer<List<DvrAiringScheduleResult>>();
      await pumpScreen(
        tester,
        show: testShow(episodes: [ep(1)]),
        onScheduleEpisodes: (eps) {
          callCount++;
          return completer.future;
        },
      );

      await tester.longPress(find.text('Ep 1'));
      await tester.pumpAndSettle();

      // Tap twice before the handler resolves.
      await tester.tap(recordButtonLabel(tester, 1));
      await tester.pump();
      await tester.tap(recordButtonLabel(tester, 1));
      await tester.pump();

      expect(callCount, 1);

      completer.complete([
        DvrAiringScheduleResult(episode: ep(1), success: true),
      ]);
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'tapping Record (N) fires onScheduleEpisodes with the selected episodes '
    'and exits selection mode',
    (tester) async {
      List<EpgShowEpisode>? captured;
      await pumpScreen(
        tester,
        show: testShow(episodes: [ep(1), ep(2), ep(3)]),
        onScheduleEpisodes: (eps) async {
          captured = eps;
          return [
            for (final e in eps)
              DvrAiringScheduleResult(episode: e, success: true),
          ];
        },
      );

      await tester.longPress(find.text('Ep 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ep 2'));
      await tester.pumpAndSettle();
      expect(recordButtonLabel(tester, 2), findsOneWidget);

      await tester.tap(recordButtonLabel(tester, 2));
      await tester.pumpAndSettle();

      expect(captured, isNotNull);
      expect(captured!.map((e) => e.title).toSet(), {'Ep 1', 'Ep 2'});

      // Handler completed → selection mode cleared.
      expect(cancelButton(tester), findsNothing);
    },
  );

  testWidgets(
    'all-success batch shows a summary SnackBar ("All succeeded.")',
    (tester) async {
      await pumpScreen(
        tester,
        show: testShow(episodes: [ep(1), ep(2)]),
        onScheduleEpisodes: (eps) async => [
          for (final e in eps)
            DvrAiringScheduleResult(episode: e, success: true),
        ],
      );

      await tester.longPress(find.text('Ep 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ep 2'));
      await tester.pumpAndSettle();
      await tester.tap(recordButtonLabel(tester, 2));
      await tester.pumpAndSettle();

      // Summary appears as a SnackBar text. failed == 0 → no failure line.
      expect(
        find.text(l10n(tester).showBatchScheduleSummary(2, 0)),
        findsOneWidget,
      );
      expect(
        find.text(l10n(tester).showBatchScheduleFailures('Ep 1, Ep 2')),
        findsNothing,
        reason: 'failed == 0 should suppress the failure-list line',
      );
    },
  );

  testWidgets(
    'mixed batch lists per-failure titles inline when failed ≤ 3',
    (tester) async {
      await pumpScreen(
        tester,
        show: testShow(episodes: [ep(1), ep(2), ep(3)]),
        onScheduleEpisodes: (eps) async => [
          DvrAiringScheduleResult(episode: eps[0], success: true),
          DvrAiringScheduleResult(
            episode: eps[1],
            success: false,
            errorMessage: 'limit reached',
          ),
          DvrAiringScheduleResult(
            episode: eps[2],
            success: false,
            errorMessage: 'limit reached',
          ),
        ],
      );

      await tester.longPress(find.text('Ep 1'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ep 2'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Ep 3'));
      await tester.pumpAndSettle();
      await tester.tap(recordButtonLabel(tester, 3));
      await tester.pumpAndSettle();

      // 1 scheduled + 2 failed (≤ 3) → failure titles listed inline.
      // The SnackBar text is summary + "\n" + failure-line, so use
      // `find.textContaining`; `find.text` is an exact-match against
      // the full multi-line string.
      expect(
        find.textContaining(
          l10n(tester).showBatchScheduleFailures('Ep 2, Ep 3'),
        ),
        findsOneWidget,
        reason: 'failed (2) ≤ 3 → failure-line appended; substring matches',
      );
    },
  );

  testWidgets(
    'large-failure batch omits per-failure titles when failed > 3',
    (tester) async {
      // List.generate is 0-indexed, so shift by 1 to get titles Ep 1..Ep 5.
      await pumpScreen(
        tester,
        show: testShow(episodes: List.generate(5, (i) => ep(i + 1))),
        onScheduleEpisodes: (eps) async => [
          DvrAiringScheduleResult(episode: eps[0], success: true),
          for (final e in eps.skip(1))
            DvrAiringScheduleResult(
              episode: e,
              success: false,
              errorMessage: 'x',
            ),
        ],
      );

      await tester.longPress(find.text('Ep 1'));
      await tester.pumpAndSettle();
      for (var i = 2; i <= 5; i++) {
        await tester.tap(find.text('Ep $i'));
        await tester.pumpAndSettle();
      }
      await tester.tap(recordButtonLabel(tester, 5));
      await tester.pumpAndSettle();

      // 1 scheduled + 4 failed (> 3) → failure list is suppressed.
      expect(
        find.text(l10n(tester).showBatchScheduleSummary(1, 4)),
        findsOneWidget,
      );
      expect(
        find.textContaining('Failed:'),
        findsNothing,
        reason: 'failed > 3 should suppress the failure-list line entirely',
      );
    },
  );

  testWidgets(
    'wholesale handler failure surfaces appRecordingFailed',
    (tester) async {
      await pumpScreen(
        tester,
        show: testShow(episodes: [ep(1)]),
        onScheduleEpisodes: (_) async {
          throw StateError('server down');
        },
      );

      await tester.longPress(find.text('Ep 1'));
      await tester.pumpAndSettle();
      await tester.tap(recordButtonLabel(tester, 1));
      await tester.pumpAndSettle();

      // Wholesale-fail path uses the existing appRecordingFailed key.
      expect(
        find.text(l10n(tester).appRecordingFailed('Bad state: server down')),
        findsOneWidget,
      );
    },
  );
}

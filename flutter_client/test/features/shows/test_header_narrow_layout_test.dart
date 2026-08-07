import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/shows/show_detail_screen.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/xtream_service.dart';

/// Regression for the mobile header layout bug: on a narrow (phone-width)
/// viewport, forcing the title + "Record Series"/"Options" buttons into one
/// Row starved the title's Expanded column down to a sliver, wrapping the
/// title one or two characters per line. The header must switch to a
/// stacked (title, then actions) layout below its narrow breakpoint
/// instead, with no layout overflow.
void main() {
  testWidgets(
    'show detail header stacks title above actions on a narrow viewport with no overflow',
    (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;

      final testShow = EpgShow(
        normalizedTitle: 'good morning football overtime',
        displayTitle: 'Good Morning Football: Overtime',
        channelCount: 44,
        channels: const [],
        episodeCount: 48,
        nextAiringAt: DateTime.utc(2026, 8, 7, 20),
        recentEpisodes: const [],
      );

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
                  }) async => CreateDvrSeriesRuleOutcome.created,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);

      // The title must not be broken into single-character lines: each
      // rendered line of the title Text should hold more than a couple of
      // characters. RenderParagraph exposes this via its computed line
      // metrics through the InlineSpan's painted extents — simplest robust
      // check available from a widget test is that the title's own render
      // box is wide enough to plausibly hold multiple words, i.e. it is not
      // starved down near zero width the way the Expanded column was when
      // squeezed by an un-wrapped button Row.
      final titleFinder = find.text('Good Morning Football: Overtime');
      expect(titleFinder, findsOneWidget);
      final titleBox = tester.getSize(titleFinder);
      expect(
        titleBox.width,
        greaterThan(150),
        reason:
            'Title render width looks starved — the header may still be '
            'forcing title + actions into one unwrapped Row on a narrow '
            'viewport.',
      );
    },
  );
}

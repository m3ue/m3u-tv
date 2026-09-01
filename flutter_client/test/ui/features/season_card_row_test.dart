import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/shared/season_card_row.dart';

Season _s(int number, {int episodes = 0, String? cover}) => Season(
  number: number,
  name: 'Season $number',
  episodeCount: episodes,
  coverUrl: cover,
);

Widget _harness({
  required List<Season> seasons,
  int? selected,
  void Function(int)? onSelect,
}) {
  return MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Dpad(
      child: Scaffold(
        body: SeasonCardRow(
          seasons: seasons,
          selectedSeason: selected,
          onSeasonSelected: onSelect ?? (_) {},
        ),
      ),
    ),
  );
}

void main() {
  group('SeasonCardRow', () {
    testWidgets('renders one card per season', (tester) async {
      await tester.pumpWidget(
        _harness(
          seasons: [_s(1, episodes: 8), _s(2, episodes: 10)],
          selected: 1,
        ),
      );
      // Two tappable season cards.
      final cards = find.byType(InkWell);
      expect(cards, findsNWidgets(2));
    });

    testWidgets('empty seasons renders nothing', (tester) async {
      await tester.pumpWidget(_harness(seasons: const []));
      expect(find.byType(InkWell), findsNothing);
    });

    testWidgets(
      'tapping a card calls onSeasonSelected with that season number',
      (tester) async {
        int? selected;
        await tester.pumpWidget(
          _harness(
            seasons: [_s(1, episodes: 8), _s(2, episodes: 10)],
            onSelect: (n) => selected = n,
          ),
        );
        // Tap the second card.
        await tester.tap(find.byType(InkWell).at(1));
        await tester.pump();
        expect(selected, 2);
      },
    );

    testWidgets('selected season name renders in bold', (tester) async {
      await tester.pumpWidget(
        _harness(
          seasons: [_s(1, episodes: 8), _s(2, episodes: 10)],
          selected: 2,
        ),
      );
      // The label for season 2 should be in bold (selected state).
      final season2Label = find.text('Season 2');
      expect(season2Label, findsOneWidget);
      final style = tester.widget<Text>(season2Label).style;
      expect(style?.fontWeight, FontWeight.bold);

      // Season 1's label should be normal weight.
      final season1Label = find.text('Season 1');
      final style1 = tester.widget<Text>(season1Label).style;
      expect(style1?.fontWeight, isNot(FontWeight.bold));
    });
  });
}

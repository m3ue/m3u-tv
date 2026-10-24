import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/player/episode_picker.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/domain_models.dart';

Episode _ep(int season, int number) => Episode(
  id: '${season}0$number',
  episodeNumber: number,
  title: 'S${season}E$number Title',
  containerExtension: 'mp4',
  seasonNumber: season,
);

SeriesInfo _info() => SeriesInfo(
  series: const Series(id: 7, name: 'Fixture Show'),
  seasons: const [
    Season(number: 1, name: 'Season 1'),
    Season(number: 2, name: 'Season 2'),
  ],
  episodesBySeason: {
    1: [_ep(1, 1), _ep(1, 2)],
    2: [_ep(2, 1)],
  },
);

Future<void> _pumpPicker(
  WidgetTester tester, {
  required SeriesInfo info,
  int? currentSeasonNumber,
  required String currentEpisodeId,
  required ValueChanged<Episode> onSelect,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => ElevatedButton(
          onPressed: () => showEpisodePicker(
            context,
            info: info,
            currentSeasonNumber: currentSeasonNumber,
            currentEpisodeId: currentEpisodeId,
            onSelect: onSelect,
          ),
          child: const Text('Open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists episodes for the current season and highlights it', (
    tester,
  ) async {
    await _pumpPicker(
      tester,
      info: _info(),
      currentSeasonNumber: 1,
      currentEpisodeId: '102',
      onSelect: (_) {},
    );

    expect(find.textContaining('S1E1 Title'), findsOneWidget);
    expect(find.textContaining('S1E2 Title'), findsOneWidget);
    expect(find.textContaining('S2E1 Title'), findsNothing);
  });

  testWidgets('switching seasons swaps the episode list', (tester) async {
    await _pumpPicker(
      tester,
      info: _info(),
      currentSeasonNumber: 1,
      currentEpisodeId: '101',
      onSelect: (_) {},
    );

    await tester.tap(find.text('Season 2'));
    await tester.pumpAndSettle();

    expect(find.textContaining('S2E1 Title'), findsOneWidget);
    expect(find.textContaining('S1E1 Title'), findsNothing);
  });

  testWidgets('tapping an episode selects it and closes the sheet', (
    tester,
  ) async {
    Episode? selected;
    await _pumpPicker(
      tester,
      info: _info(),
      currentSeasonNumber: 1,
      currentEpisodeId: '101',
      onSelect: (episode) => selected = episode,
    );

    await tester.tap(find.textContaining('S1E2 Title'));
    await tester.pumpAndSettle();

    expect(selected?.id, '102');
    expect(find.textContaining('S1E2 Title'), findsNothing);
  });

  testWidgets(
    'falls back to the first season when the current one is unknown',
    (tester) async {
      await _pumpPicker(
        tester,
        info: _info(),
        currentEpisodeId: '999',
        onSelect: (_) {},
      );

      expect(find.textContaining('S1E1 Title'), findsOneWidget);
    },
  );

  testWidgets('marks the selected season with a check icon', (tester) async {
    await _pumpPicker(
      tester,
      info: _info(),
      currentSeasonNumber: 1,
      currentEpisodeId: '101',
      onSelect: (_) {},
    );

    expect(find.byIcon(Icons.check), findsOneWidget);

    await tester.tap(find.text('Season 2'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.check), findsOneWidget);
  });

  testWidgets('shows a truncated plot when the episode has one', (
    tester,
  ) async {
    const info = SeriesInfo(
      series: Series(id: 7, name: 'Fixture Show'),
      seasons: [Season(number: 1, name: 'Season 1')],
      episodesBySeason: {
        1: [
          Episode(
            id: '101',
            episodeNumber: 1,
            title: 'With Plot',
            containerExtension: 'mp4',
            seasonNumber: 1,
            plot: 'A gripping synopsis.',
          ),
        ],
      },
    );

    await _pumpPicker(
      tester,
      info: info,
      currentSeasonNumber: 1,
      currentEpisodeId: '999',
      onSelect: (_) {},
    );

    expect(find.text('A gripping synopsis.'), findsOneWidget);
  });

  testWidgets('closing via the X button does not select an episode', (
    tester,
  ) async {
    var selectCalled = false;
    await _pumpPicker(
      tester,
      info: _info(),
      currentSeasonNumber: 1,
      currentEpisodeId: '101',
      onSelect: (_) => selectCalled = true,
    );

    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();

    expect(selectCalled, isFalse);
    expect(find.textContaining('S1E1 Title'), findsNothing);
  });

  testWidgets(
    'scrolls a far-right current season fully into view on open',
    (tester) async {
      final info = SeriesInfo(
        series: const Series(id: 7, name: 'Fixture Show'),
        seasons: [
          for (var s = 1; s <= 8; s++) Season(number: s, name: 'Season $s'),
        ],
        episodesBySeason: {
          for (var s = 1; s <= 8; s++) s: [_ep(s, 1)],
        },
      );

      await _pumpPicker(
        tester,
        info: info,
        currentSeasonNumber: 8,
        currentEpisodeId: '801',
        onSelect: (_) {},
      );

      final screenWidth =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      final chip = find.text('Season 8');
      expect(chip, findsOneWidget);
      final topLeft = tester.getTopLeft(chip);
      final bottomRight = tester.getBottomRight(chip);
      expect(topLeft.dx, greaterThanOrEqualTo(0));
      expect(bottomRight.dx, lessThanOrEqualTo(screenWidth));
    },
  );
}

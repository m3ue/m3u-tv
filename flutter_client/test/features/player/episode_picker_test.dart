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

    expect(find.text('S1E1 Title'), findsOneWidget);
    expect(find.text('S1E2 Title'), findsOneWidget);
    expect(find.text('S2E1 Title'), findsNothing);
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

    expect(find.text('S2E1 Title'), findsOneWidget);
    expect(find.text('S1E1 Title'), findsNothing);
  });

  testWidgets('tapping an episode selects it and closes the dialog', (
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

    await tester.tap(find.text('S1E2 Title'));
    await tester.pumpAndSettle();

    expect(selected?.id, '102');
    expect(find.text('S1E2 Title'), findsNothing);
  });

  testWidgets(
    'falls back to the first season when the current one is unknown',
    (
      tester,
    ) async {
      await _pumpPicker(
        tester,
        info: _info(),
        currentEpisodeId: '999',
        onSelect: (_) {},
      );

      expect(find.text('S1E1 Title'), findsOneWidget);
    },
  );
}

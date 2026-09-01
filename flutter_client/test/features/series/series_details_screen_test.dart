import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/series/series_details_screen.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/navigation/app_router.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/xtream_service.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';

Episode _ep(int season, int number) => Episode(
  id: '${season}0$number',
  episodeNumber: number,
  title: 'S${season}E$number Title',
  containerExtension: 'mp4',
  seasonNumber: season,
  streamUrl: 'http://example.com/s$season/e$number.mp4',
);

class _FakeSeriesService extends XtreamService {
  _FakeSeriesService(this.info, {this.seriesProgress = const []});

  final SeriesInfo info;
  final List<Progress> seriesProgress;

  @override
  Future<SeriesInfo> getSeriesInfo(int seriesId) async => info;

  @override
  Future<List<Progress>> getSeriesProgress(
    String viewerId,
    int seriesId,
  ) async => seriesProgress;
}

Widget _app(
  SeriesInfo info, {
  List<Progress> progressList = const [],
  List<Progress> seriesProgress = const [],
  String? viewerId,
  void Function(PlayerArgs)? onPlay,
  MarkEpisodeWatched? onMarkEpisodeWatched,
}) => MaterialApp(
  theme: ThemeData.dark(useMaterial3: true),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: SeriesDetailsScreen(
    seriesId: 7,
    seriesName: 'Fixture Show',
    xtreamService: _FakeSeriesService(info, seriesProgress: seriesProgress),
    viewerId: viewerId,
    progressList: progressList,
    onPlay: onPlay,
    onMarkEpisodeWatched: onMarkEpisodeWatched,
  ),
);

SeriesInfo _info() => SeriesInfo(
  series: const Series(id: 7, name: 'Fixture Show', plot: 'Series-level plot'),
  seasons: const [
    Season(number: 1, name: 'Season 1', overview: 'First season synopsis'),
    Season(number: 2, name: 'Season 2'),
    Season(number: 3, name: 'Season 3', overview: 'Third season synopsis'),
  ],
  episodesBySeason: {
    1: [_ep(1, 1), _ep(1, 2), _ep(1, 3)],
    2: [_ep(2, 1)],
    3: [_ep(3, 1), _ep(3, 2)],
  },
);

Progress _prog(
  int streamId, {
  required int season,
  required int episode,
  int position = 0,
  int duration = 2700,
  bool completed = false,
}) => Progress(
  viewerId: 'v1',
  contentType: ContentType.episode,
  streamId: streamId,
  positionSeconds: position,
  durationSeconds: duration,
  completed: completed,
  seriesId: 7,
  seasonNumber: season,
  episodeNumber: episode,
);

void main() {
  testWidgets('episode cards show plot, formatted date and runtime', (
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
            title: 'Pilot',
            containerExtension: 'mp4',
            seasonNumber: 1,
            plot: 'A drifter arrives in a quiet town.',
            duration: '45m',
            rating: 8.1,
            releaseDate: '2025-10-01',
            streamUrl: 'http://example.com/s1/e1.mp4',
          ),
        ],
      },
    );

    await tester.pumpWidget(_app(info));
    await tester.pumpAndSettle();

    expect(find.text('A drifter arrives in a quiet town.'), findsOneWidget);
    expect(find.text('Oct 1, 2025'), findsOneWidget);
    // Runtime shows on the card overlay and as an average chip in the meta.
    expect(find.text('45m'), findsOneWidget);
    expect(find.text('~45m'), findsOneWidget);
  });

  testWidgets('a bare-seconds duration reads as seconds, not minutes', (
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
            title: 'Pilot',
            containerExtension: 'mp4',
            seasonNumber: 1,
            duration: '5400', // 90 minutes expressed as raw seconds
            streamUrl: 'http://example.com/s1/e1.mp4',
          ),
        ],
      },
    );

    await tester.pumpWidget(_app(info));
    await tester.pumpAndSettle();

    expect(find.text('~1h 30m'), findsOneWidget);
    expect(find.text('~90h'), findsNothing);
  });

  testWidgets('poster falls through season -> series -> backdrop', (
    tester,
  ) async {
    const info = SeriesInfo(
      series: Series(
        id: 7,
        name: 'Fixture Show',
        coverUrl: 'http://example.com/series-cover.jpg',
        backdropUrl: 'http://example.com/backdrop.jpg',
      ),
      seasons: [Season(number: 1, name: 'Season 1')], // no cover
      episodesBySeason: {
        1: [
          Episode(
            id: '101',
            episodeNumber: 1,
            title: 'Pilot',
            containerExtension: 'mp4',
            seasonNumber: 1,
            streamUrl: 'http://example.com/s1/e1.mp4',
          ),
        ],
      },
    );

    await tester.pumpWidget(_app(info));
    await tester.pumpAndSettle();

    final poster = tester.widget<ResilientMediaImage>(
      find.byWidgetPredicate(
        (w) => w is ResilientMediaImage && w.borderRadius != 0,
      ),
    );
    expect(poster.imageUrl, 'http://example.com/series-cover.jpg');
    expect(poster.fallbackImageUrls, ['http://example.com/backdrop.jpg']);

    // Flush the palette-generator timeout timer the backdrop kicks off.
    await tester.pump(const Duration(seconds: 16));
  });

  testWidgets('phone layout stacks the poster and uses a vertical episode '
      'list', (tester) async {
    tester.view.physicalSize = const Size(420, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const info = SeriesInfo(
      series: Series(id: 7, name: 'Fixture Show'),
      seasons: [Season(number: 1, name: 'Season 1')],
      episodesBySeason: {
        1: [
          Episode(
            id: '101',
            episodeNumber: 1,
            title: 'Pilot',
            containerExtension: 'mp4',
            seasonNumber: 1,
            duration: '45m',
            rating: 8.1,
            streamUrl: 'http://example.com/s1/e1.mp4',
          ),
        ],
      },
    );

    await tester.pumpWidget(_app(info));
    await tester.pumpAndSettle();

    // Vertical cards render a single joined meta line rather than separate
    // overlaid pills.
    expect(find.text('S1E1  ·  ★ 8.1  ·  45m'), findsOneWidget);
    // No horizontal strip -> no episode Scrollbar.
    expect(find.byType(Scrollbar), findsNothing);
  });

  testWidgets('play button takes focus once the series loads', (tester) async {
    await tester.pumpWidget(_app(_info()));
    await tester.pumpAndSettle();

    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'seriesPlayButton',
    );
  });

  testWidgets('defaults to season 1 and its overview when nothing is watched', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_info()));
    await tester.pumpAndSettle();

    expect(find.textContaining('S1E1 Title', findRichText: true), findsWidgets);
    expect(find.textContaining('S3E1 Title', findRichText: true), findsNothing);
    expect(find.text('First season synopsis'), findsOneWidget);
    expect(find.text('Series-level plot'), findsNothing);
    // No watch history -> the lowest season, first episode.
    expect(find.text('Play S1E1'), findsOneWidget);
  });

  testWidgets('play button follows the selected season', (tester) async {
    await tester.pumpWidget(_app(_info()));
    await tester.pumpAndSettle();

    expect(find.text('Play S1E1'), findsOneWidget);

    await tester.tap(find.text('Season 1').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Season 3').last);
    await tester.pumpAndSettle();

    expect(find.text('Play S3E1'), findsOneWidget);
    expect(find.text('Play S1E1'), findsNothing);
  });

  testWidgets('season picker switches the visible episode list', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_info()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Season 1').last);
    await tester.pumpAndSettle();

    // Pick-list rows are D-pad targets, and the current season's row takes
    // focus so the list is drivable by remote the moment it opens.
    final rows = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(DpadInkWell),
    );
    expect(rows, findsNWidgets(3));
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(DpadRegion),
      ),
      findsOneWidget,
    );
    expect(
      tester.widget<DpadInkWell>(rows.first).autofocus,
      isTrue,
      reason: 'Season 1 (the selected season) row should autofocus',
    );

    await tester.tap(find.text('Season 3').last);
    await tester.pumpAndSettle();

    expect(find.textContaining('S3E1 Title', findRichText: true), findsWidgets);
    expect(find.textContaining('S1E1 Title', findRichText: true), findsNothing);
    expect(find.text('Third season synopsis'), findsOneWidget);
  });

  testWidgets('season picker shows an episode count badge and per-season '
      'counts in the pick-list', (tester) async {
    await tester.pumpWidget(_app(_info()));
    await tester.pumpAndSettle();

    // Default season (1) has 3 episodes -> badge on the picker button.
    expect(find.text('3'), findsOneWidget);

    await tester.tap(find.text('Season 1').last);
    await tester.pumpAndSettle();

    expect(find.text('3 episodes'), findsOneWidget);
    expect(find.text('1 episode'), findsOneWidget);
    expect(find.text('2 episodes'), findsOneWidget);
    // Season overview rides under the count in the pick-list row (season 1's
    // also shows in the page body since it is the default season).
    expect(find.text('First season synopsis'), findsNWidgets(2));
    expect(find.text('Third season synopsis'), findsOneWidget);
  });

  testWidgets('falls back to series plot when the season has no overview', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_info()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Season 1').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Season 2').last);
    await tester.pumpAndSettle();

    expect(find.text('Series-level plot'), findsOneWidget);
  });

  testWidgets('lands on the season of the furthest-along episode', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        _info(),
        viewerId: 'v1',
        seriesProgress: [
          _prog(101, season: 1, episode: 1, position: 2700, completed: true),
          _prog(103, season: 1, episode: 3, position: 2700, completed: true),
          _prog(301, season: 3, episode: 1, position: 600),
        ],
      ),
    );
    await tester.pumpAndSettle();

    // Furthest along is S3E1 (in progress) -> land on Season 3 and resume it.
    expect(find.text('Season 3'), findsOneWidget);
    expect(find.text('35 min left'), findsOneWidget);
    expect(find.text('Start from Beginning'), findsOneWidget);
    expect(find.textContaining('S3E1 Title', findRichText: true), findsWidgets);
  });

  SeriesInfo infoS1x4() => SeriesInfo(
    series: const Series(id: 7, name: 'Fixture Show'),
    seasons: const [Season(number: 1, name: 'Season 1')],
    episodesBySeason: {
      1: [_ep(1, 1), _ep(1, 2), _ep(1, 3), _ep(1, 4)],
    },
  );

  testWidgets('play target is the episode after the last finished one', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        infoS1x4(),
        viewerId: 'v1',
        seriesProgress: [
          _prog(101, season: 1, episode: 1, position: 2700, completed: true),
          _prog(102, season: 1, episode: 2, position: 2700, completed: true),
          _prog(103, season: 1, episode: 3, position: 2700, completed: true),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Play S1E4'), findsOneWidget);
  });

  testWidgets('a zeroed (un-marked) row does not advance the play target', (
    tester,
  ) async {
    // E3's row is present but completed:false / position:0 - what "mark
    // unwatched" leaves behind. The target must stay at S1E3, not jump to E4.
    await tester.pumpWidget(
      _app(
        infoS1x4(),
        viewerId: 'v1',
        seriesProgress: [
          _prog(101, season: 1, episode: 1, position: 2700, completed: true),
          _prog(102, season: 1, episode: 2, position: 2700, completed: true),
          _prog(103, season: 1, episode: 3),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Play S1E3'), findsOneWidget);
    expect(find.text('Play S1E4'), findsNothing);
  });

  testWidgets('primary button resumes an in-progress episode with time left', (
    tester,
  ) async {
    PlayerArgs? played;
    await tester.pumpWidget(
      _app(
        _info(),
        onPlay: (args) => played = args,
        progressList: [_prog(102, season: 1, episode: 2, position: 600)],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('35 min left'), findsOneWidget);
    expect(find.text('Start from Beginning'), findsOneWidget);

    await tester.tap(find.text('35 min left'));
    await tester.pump();
    expect(played?.type, 'series');
    expect(played?.streamId, 102);
    expect(played?.startPosition, 600);

    await tester.tap(find.text('Start from Beginning'));
    await tester.pump();
    expect(played?.startPosition, 0);
  });

  testWidgets('long-pressing an episode card confirms before marking watched', (
    tester,
  ) async {
    final calls = <({int streamId, bool watched})>[];
    await tester.pumpWidget(
      _app(
        _info(),
        viewerId: 'v1',
        onMarkEpisodeWatched:
            ({
              required streamId,
              required seriesId,
              required seasonNumber,
              required episodeNumber,
              durationSeconds,
              seriesName,
              episodeTitle,
              required watched,
            }) async {
              calls.add((streamId: streamId, watched: watched));
              return true;
            },
      ),
    );
    await tester.pumpAndSettle();

    final card = find.textContaining('S1E1 Title', findRichText: true).first;
    await tester.ensureVisible(card);
    await tester.pumpAndSettle();
    // The title sits under the thumbnail scrim; the card's DpadInkWell still
    // receives the press at that point, so the miss warning is expected.
    await tester.longPress(card, warnIfMissed: false);
    await tester.pumpAndSettle();

    // A confirmation modal gates the change.
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(calls, isEmpty);

    await tester.tap(find.text('Mark watched'));
    await tester.pumpAndSettle();

    expect(calls, isNotEmpty);
    expect(calls.first.streamId, 101);
    expect(calls.first.watched, isTrue);
  });

  testWidgets('mark-season reports partial sync failure', (tester) async {
    var writes = 0;
    await tester.pumpWidget(
      _app(
        _info(), // Season 1 has 3 episodes
        viewerId: 'v1',
        onMarkEpisodeWatched:
            ({
              required streamId,
              required seriesId,
              required seasonNumber,
              required episodeNumber,
              durationSeconds,
              seriesName,
              episodeTitle,
              required watched,
            }) async {
              writes++;
              return writes != 2; // second episode "fails" to sync
            },
      ),
    );
    await tester.pumpAndSettle();

    // Nothing watched -> the picker defaults to Season 1 (3 episodes).
    await tester.longPress(find.text('Season 1'), warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Mark watched'));
    await tester.pumpAndSettle();

    expect(writes, 3); // sequential, one per episode
    expect(find.text("Couldn't sync watched status"), findsOneWidget);
    expect(find.text('Marked as watched'), findsNothing);
  });
}

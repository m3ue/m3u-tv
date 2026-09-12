import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/series/series_details_screen.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/navigation/app_router.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/xtream_service.dart';
import 'package:m3u_tv/shared/cast_member_row.dart';
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

  testWidgets('app bar title carries the active season', (tester) async {
    await tester.pumpWidget(_app(_info()));
    await tester.pumpAndSettle();

    final appBarTitle = find.descendant(
      of: find.byType(AppBar),
      matching: find.text('Fixture Show - S1'),
    );
    expect(appBarTitle, findsOneWidget);

    await tester.tap(find.text('Season 1').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Season 3').last);
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.text('Fixture Show - S3'),
      ),
      findsOneWidget,
    );
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

  testWidgets('season picker close icon dismisses the dialog only', (
    tester,
  ) async {
    await tester.pumpWidget(_app(_info()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Season 1').last);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byIcon(Icons.close),
      ),
    );
    await tester.pumpAndSettle();

    // The dialog closes; the series screen stays put (no route pop).
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(SeriesDetailsScreen), findsOneWidget);
    expect(find.text('Play S1E1'), findsOneWidget);
  });

  testWidgets('phone layout opens the season picker as a bottom sheet', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_app(_info()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Season 1').last);
    await tester.pumpAndSettle();

    // A bottom sheet, not a centered dialog.
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    final rows = find.descendant(
      of: find.byType(BottomSheet),
      matching: find.byType(DpadInkWell),
    );
    expect(rows, findsNWidgets(3));
    expect(
      tester.widget<DpadInkWell>(rows.first).autofocus,
      isTrue,
      reason: 'the selected season row should autofocus',
    );

    // The close icon dismisses without picking anything.
    await tester.tap(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.byIcon(Icons.close),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.textContaining('S1E1 Title', findRichText: true), findsWidgets);

    await tester.tap(find.text('Season 1').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Season 3').last);
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsNothing);
    expect(find.textContaining('S3E1 Title', findRichText: true), findsWidgets);
    expect(find.textContaining('S1E1 Title', findRichText: true), findsNothing);
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

  group('SeriesDetailsScreen - rich cast', () {
    testWidgets(
      'wide layout: renders the locked-focus cast strip below the episode '
      'strip when the server resolved a rich cast',
      (tester) async {
        await tester.pumpWidget(
          _app(
            SeriesInfo(
              series: const Series(
                id: 7,
                name: 'Rich Cast Show',
                plot: 'A series with a populated rich cast.',
                richCast: <CastMember>[
                  CastMember(
                    id: 1,
                    name: 'Bryan Cranston',
                    character: 'Walter White',
                  ),
                  CastMember(
                    id: 2,
                    name: 'Aaron Paul',
                    character: 'Jesse Pinkman',
                  ),
                ],
              ),
              seasons: const [Season(number: 1, name: 'Season 1')],
              episodesBySeason: {
                1: [_ep(1, 1)],
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        // The wide layout uses its own _CastStrip (private), not the compact
        // CastMemberRow chip.
        expect(find.byType(CastMemberRow), findsNothing);
        expect(find.text('Cast'), findsOneWidget);
        // Member names render inline; the resilient avatar also renders the
        // name as a text placeholder when the image fails (no network in
        // tests), so allow more than one.
        expect(find.text('Bryan Cranston'), findsWidgets);
        expect(find.text('Walter White'), findsOneWidget);
        expect(find.text('Jesse Pinkman'), findsOneWidget);
        // The legacy string-cast line in the meta block is untouched.
        expect(
          find.text('A series with a populated rich cast.'),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'wide layout: no cast strip when the server sent no rich cast',
      (tester) async {
        await tester.pumpWidget(_app(_info()));
        await tester.pumpAndSettle();

        expect(find.byType(CastMemberRow), findsNothing);
        expect(find.text('Cast'), findsNothing);
      },
    );

    testWidgets(
      'narrow layout: renders CastMemberRow when series.richCast is populated',
      (tester) async {
        tester.view.physicalSize = const Size(420, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          _app(
            SeriesInfo(
              series: const Series(
                id: 7,
                name: 'Rich Cast Show',
                richCast: <CastMember>[
                  CastMember(name: 'Bryan Cranston', character: 'Walter White'),
                ],
              ),
              seasons: const [Season(number: 1, name: 'Season 1')],
              episodesBySeason: {
                1: [_ep(1, 1)],
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        // Compact layout is a single picker chip - only the "Cast"
        // label and a count badge render; member names live inside
        // the bottom sheet, not inline.
        expect(find.byType(CastMemberRow), findsOneWidget);
        expect(find.text('Cast'), findsOneWidget);
        // Scoped to the cast row - the season picker's episode-count
        // badge also renders "1" for this single-episode fixture.
        expect(
          find.descendant(
            of: find.byType(CastMemberRow),
            matching: find.text('1'),
          ),
          findsOneWidget,
        );
        // No member name bleeds into the inline compact layout.
        expect(find.text('Bryan Cranston'), findsNothing);
        // The chip lives in the same Wrap as the season picker - beside
        // it, not on its own row above the action buttons.
        final actionWrap = find.ancestor(
          of: find.text('Season 1'),
          matching: find.byType(Wrap),
        );
        expect(
          find.descendant(
            of: actionWrap.first,
            matching: find.byType(CastMemberRow),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'narrow layout: hides CastMemberRow when series.richCast is null',
      (tester) async {
        tester.view.physicalSize = const Size(420, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(_app(_info()));
        await tester.pumpAndSettle();

        expect(find.byType(CastMemberRow), findsNothing);
      },
    );

    testWidgets(
      'narrow layout: rich cast picker button opens bottom sheet listing all members',
      (tester) async {
        tester.view.physicalSize = const Size(420, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        // 5 members → compact layout shows one chip with a "5" badge.
        final richCast = <CastMember>[
          const CastMember(name: 'Bryan Cranston', character: 'Walter White'),
          const CastMember(name: 'Aaron Paul', character: 'Jesse Pinkman'),
          const CastMember(name: 'Anna Gunn', character: 'Skyler White'),
          const CastMember(name: 'Dean Norris', character: 'Hank Schrader'),
          const CastMember(name: 'Betsy Brandt', character: 'Marie Schrader'),
        ];
        await tester.pumpWidget(
          _app(
            SeriesInfo(
              series: Series(id: 7, name: 'Rich Cast Show', richCast: richCast),
              seasons: const [Season(number: 1, name: 'Season 1')],
              episodesBySeason: {
                1: [_ep(1, 1)],
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        // The picker is the visible inline compact control - a button
        // labelled "Cast" with a count badge showing all 5 members.
        expect(find.text('Cast'), findsOneWidget);
        expect(find.text('5'), findsOneWidget);

        // Tap the picker → bottom sheet opens with every member
        // listed (5 rows). Compact layout keeps member names inside
        // the sheet only - no inline duplication.
        await tester.tap(find.text('Cast'));
        await tester.pumpAndSettle();

        expect(find.text('Bryan Cranston'), findsOneWidget);
        expect(find.text('Aaron Paul'), findsOneWidget);
        expect(find.text('Anna Gunn'), findsOneWidget);
        expect(find.text('Dean Norris'), findsOneWidget);
        expect(find.text('Betsy Brandt'), findsOneWidget);
        expect(find.text('Walter White'), findsOneWidget);
        expect(find.text('Jesse Pinkman'), findsOneWidget);
        expect(find.text('Skyler White'), findsOneWidget);
        expect(find.text('Hank Schrader'), findsOneWidget);
        expect(find.text('Marie Schrader'), findsOneWidget);
      },
    );

    testWidgets(
      'wide layout: on a short viewport, moving focus cast -> episode strip '
      'scrolls the episode strip back into view (no clip)',
      (tester) async {
        // Wide (>700) but deliberately short so the hero (poster/meta/season
        // picker), episode strip and cast row cannot all fit and the region -
        // which now spans the whole page, not just the space left below the
        // hero - still has to scroll. This is the state that made the strip
        // stay clipped on a TV.
        tester.view.physicalSize = const Size(1000, 420);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          _app(
            SeriesInfo(
              series: Series(
                id: 7,
                name: 'Rich Cast Show',
                richCast: List.generate(
                  12,
                  (i) =>
                      CastMember(name: 'Cast Member $i', character: 'Role $i'),
                ),
              ),
              seasons: const [Season(number: 1, name: 'Season 1')],
              episodesBySeason: {
                1: [_ep(1, 1), _ep(1, 2), _ep(1, 3)],
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        FocusNode strip(String label) => tester
            .widgetList<Focus>(find.byType(Focus))
            .firstWhere((w) => w.focusNode?.debugLabel == label)
            .focusNode!;

        final scrollView = find.byType(SingleChildScrollView);
        expect(scrollView, findsOneWidget);
        final regionTop = tester.getRect(scrollView).top;
        double episodeStripTop() {
          final box =
              strip('episodeStrip').context!.findRenderObject()! as RenderBox;
          return box.localToGlobal(Offset.zero).dy;
        }

        // Focus the cast row: the region scrolls down and the episode strip
        // is pushed off the top.
        strip('castStrip').requestFocus();
        await tester.pumpAndSettle();
        expect(
          episodeStripTop(),
          lessThan(regionTop - 1),
          reason: 'episode strip should be clipped above the viewport now',
        );

        // Focus back to the episode strip: it must come fully back into view.
        strip('episodeStrip').requestFocus();
        await tester.pumpAndSettle();
        expect(
          episodeStripTop(),
          greaterThanOrEqualTo(regionTop - 1),
          reason: 'episode strip should no longer be clipped at the top',
        );
      },
    );

    testWidgets(
      'wide layout: DOWN/UP arrows move focus straight between the episode '
      'strip and the cast strip on a short viewport',
      (tester) async {
        tester.view.physicalSize = const Size(1000, 600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          _app(
            SeriesInfo(
              series: Series(
                id: 7,
                name: 'Rich Cast Show',
                richCast: List.generate(
                  12,
                  (i) =>
                      CastMember(name: 'Cast Member $i', character: 'Role $i'),
                ),
              ),
              seasons: const [Season(number: 1, name: 'Season 1')],
              episodesBySeason: {
                1: [_ep(1, 1), _ep(1, 2), _ep(1, 3)],
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        String? focusLabel() => FocusManager.instance.primaryFocus?.debugLabel;

        // Play autofocuses; one DOWN reaches the episode strip.
        expect(focusLabel(), 'seriesPlayButton');
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(focusLabel(), 'episodeStrip');

        // One DOWN must land on the cast strip - not scroll the region and
        // leave focus behind (the "press down twice" bug).
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        expect(focusLabel(), 'castStrip');

        // One UP must return to the episode strip.
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
        expect(focusLabel(), 'episodeStrip');
      },
    );
  });
}

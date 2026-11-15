import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/home/home_screen.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/navigation/nav_layout.dart';
import 'package:m3u_tv/navigation/route_names.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:m3u_tv/services/catalog_db/catalog_codec.dart';
import 'package:m3u_tv/services/catalog_db/catalog_database.dart';
import 'package:m3u_tv/services/catalog_db/catalog_repository.dart';
import 'package:m3u_tv/services/client_config.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/epg_service.dart';
import 'package:m3u_tv/services/favorites_service.dart';
import 'package:m3u_tv/services/sports_models.dart';
import 'package:m3u_tv/services/sports_service.dart';
import 'package:m3u_tv/services/sports_settings.dart';
import 'package:m3u_tv/services/view_settings_service.dart';
import 'package:m3u_tv/services/xtream_service.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';
import 'package:material_ui/material_ui.dart';

// No artwork URLs: rendering one under tester.runAsync reaches the real
// image cache, which is not set up in tests.
const _channels = <Channel>[
  Channel(id: 1, name: 'BBC One', streamUrl: 'http://x/1', categoryId: '10'),
];
const _movies = <VodItem>[
  VodItem(
    id: 7,
    name: 'Big Buck Bunny',
    streamUrl: 'http://x/7.mp4',
    containerExtension: 'mp4',
    categoryId: '20',
  ),
];
const _otherMovies = <VodItem>[
  VodItem(
    id: 9,
    name: 'Elephants Dream',
    streamUrl: 'http://x/9.mp4',
    containerExtension: 'mp4',
    categoryId: '40',
  ),
];
const _series = <Series>[Series(id: 5, name: 'Sintel Saga', categoryId: '30')];

/// Favorites whose reads can be held back (a slow storage read) and are
/// counted.
class _GatedFavorites extends FavoritesService {
  _GatedFavorites(this.ids) : super(memory: <String, Object?>{});

  Set<int> ids;
  Completer<void>? gate;
  int reads = 0;

  @override
  Future<Set<int>> all() async {
    reads += 1;
    await gate?.future;
    return {...ids};
  }
}

/// Settings for the plain rows layout. The default Spotlight layout repeats
/// the focused row's text in its hero.
ViewSettingsService _rowsOnlySettings() => ViewSettingsService(
  memory: <String, Object?>{
    ViewSettingsService.homeScreenStyleKey: HomeScreenStyle.simplified.value,
  },
);

/// The catalog one playlist shows.
class _Catalog {
  const _Catalog({
    this.channels = const [],
    this.movies = const [],
    this.series = const [],
  });

  final List<Channel> channels;
  final List<VodItem> movies;
  final List<Series> series;

  // Fresh lists every time: a new categories list is how a reload shows.
  List<Category> categoriesFor(List<Object> items, String id) => [
    if (items.isNotEmpty) Category(id: id, name: 'Category $id'),
  ];
}

Future<void> _fill(CatalogRepository repo, _Catalog catalog) async {
  for (final (kind, items) in <(String, List<Object>)>[
    (kCatalogKindLive, catalog.channels),
    (kCatalogKindVod, catalog.movies),
    (kCatalogKindSeries, catalog.series),
  ]) {
    await repo.replaceItems(
      sourceKey: CatalogRepository.defaultSource,
      kind: kind,
      items: items,
    );
  }
}

Future<CatalogRepository> _buildRepo(
  WidgetTester tester,
  _Catalog catalog,
) async {
  final repo = await tester.runAsync(() async {
    final db = CatalogDatabase.memory();
    addTearDown(db.close);
    final repo = CatalogRepository(db);
    await _fill(repo, catalog);
    return repo;
  });
  return repo!;
}

/// Gives the catalog's queries a real async turn, then settles.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
  }
}

/// The row titled [title]; series cards repeat "Series" as their subtitle.
Finder _section(String title) => find.ancestor(
  of: find.text(title).first,
  matching: find.byType(MediaPreviewSection),
);

void main() {
  // The shown playlist's key and catalog; a test swaps it to switch.
  late StateProvider<(String, _Catalog)> shown;

  Future<CatalogRepository> pumpHome(
    WidgetTester tester,
    _Catalog catalog, {
    VoidCallback? onMoviesMore,
    FavoritesService? liveFavorites,
    bool unreadable = false,
    SportsCapability? sports,
    XtreamService? sportsEditor,
    ValueChanged<Channel>? onChannelSelect,
    VoidCallback? onSportsMore,
    ViewSettingsService? viewSettings,
    bool hasDvr = false,
    bool hasAioStreams = false,
    bool hasRequests = false,
    VoidCallback? onSidebarActivate,
    FavoritesService? vodFavorites,
  }) async {
    // A TV screen: every row is on it.
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    shown = StateProvider<(String, _Catalog)>((_) => ('first', catalog));
    final repo = await _buildRepo(tester, catalog);
    // Every read throws, as after the database closes during a sign-out.
    if (unreadable) await tester.runAsync(repo.close);
    final memory = <String, Object?>{};
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isBootstrappingProvider.overrideWith((_) => false),
          isConfiguredProvider.overrideWith((_) => true),
          sourceErrorProvider.overrideWith((_) => null),
          shownPlaylistKeyProvider.overrideWith((ref) => ref.watch(shown).$1),
          liveCategoriesProvider.overrideWith((ref) {
            final catalog = ref.watch(shown).$2;
            return catalog.categoriesFor(catalog.channels, '10');
          }),
          vodCategoriesProvider.overrideWith((ref) {
            final catalog = ref.watch(shown).$2;
            return catalog.categoriesFor(catalog.movies, '20');
          }),
          seriesCategoriesProvider.overrideWith((ref) {
            final catalog = ref.watch(shown).$2;
            return catalog.categoriesFor(catalog.series, '30');
          }),
          catalogRepositoryProvider.overrideWith((_) => repo),
          progressListProvider.overrideWith((_) => const <Progress>[]),
          hasDvrFeatureProvider.overrideWith((_) => hasDvr),
          dvrRecordingsProvider.overrideWith((_) => const <DvrRecording>[]),
          hasAioStreamsProvider.overrideWith((_) => hasAioStreams),
          hasRequestsFeatureProvider.overrideWith((_) => hasRequests),
          // Sports is off unless a test turns it on
          sportsCapabilityProvider.overrideWith((_) => sports),
          if (sportsEditor != null) ...[
            sportsServiceProvider.overrideWith(
              (_) => SportsService(sportsEditor),
            ),
            sportsSettingsProvider.overrideWith((_) => SportsSettings()),
          ],
          epgServiceProvider.overrideWith((_) => EpgService()),
          recordingChannelIdsProvider.overrideWith((_) => const <int>{}),
          viewSettingsServiceProvider.overrideWith(
            (_) => viewSettings ?? _rowsOnlySettings(),
          ),
          liveFavoritesServiceProvider.overrideWith(
            (_) => liveFavorites ?? FavoritesService(memory: memory),
          ),
          vodFavoritesServiceProvider.overrideWith(
            (_) =>
                vodFavorites ??
                FavoritesService(memory: memory, namespace: 'vod'),
          ),
          seriesFavoritesServiceProvider.overrideWith(
            (_) => FavoritesService(memory: memory, namespace: 'series'),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData.dark(useMaterial3: true),
          home: HomeScreen(
            onChannelSelect: onChannelSelect ?? (_) {},
            onSportsMore: onSportsMore,
            onVodSelect: (_) {},
            onSeriesSelect: (_) {},
            onProgressSelect: (_) {},
            onContinueWatchingMore: () {},
            onLiveTvMore: () {},
            onMoviesMore: onMoviesMore ?? () {},
            onSeriesMore: () {},
            onRecordingsSelect: () {},
            onAioStreamsSelect: () {},
            onRequestsSelect: () {},
            onAioStreamsItemSelect: (_, _) {},
            useSidebarLayout: true,
            onSidebarActivate: onSidebarActivate,
          ),
        ),
      ),
    );
    return repo;
  }

  testWidgets(
    "a Sports row lists today's watchable games, plays one, and opens Sports",
    (tester) async {
      const eventChannel = Channel(
        id: 5,
        name: 'NHL 05: Mammoth @ Maple Leafs',
        streamUrl: 'http://x/5',
        categoryId: '10',
      );
      Map<String, Object?> team(String id, String name, String nickname) => {
        'id': id,
        'display_name': name,
        'short_name': nickname,
        'nickname': nickname,
        'abbreviation': id.toUpperCase(),
      };
      final editor = (await tester.runAsync(() async {
        final service = XtreamService(
          transport: (request) async {
            if (request.action == null) {
              return {
                'user_info': {'auth': 1, 'status': 'Active'},
                'm3u_editor': {
                  'version': '0.14.0',
                  'features': ['sports'],
                },
              };
            }
            if (request.action == 'get_sports_channels') {
              return {
                'channels': {
                  'hockey/nhl:401': [
                    {'stream_id': 5},
                  ],
                },
              };
            }
            return {
              'fixtures': [
                {
                  'id': '401',
                  'league_id': 'hockey/nhl',
                  'start': DateTime.now().toUtc().toIso8601String(),
                  'state': 'live',
                  'status_detail': '1st - 15:00',
                  'home': {
                    'score': '1',
                    'team': team('tor', 'Toronto Maple Leafs', 'Maple Leafs'),
                  },
                  'away': {
                    'score': '0',
                    'team': team('uta', 'Utah Mammoth', 'Mammoth'),
                  },
                },
              ],
            };
          },
        );
        await service.authenticate(
          const UserCredentials(
            server: 'https://editor.example',
            username: 'user',
            password: 'pass',
          ),
        );
        return service;
      }))!;
      final played = <Channel>[];
      var openedSports = 0;

      await pumpHome(
        tester,
        const _Catalog(channels: [..._channels, eventChannel]),
        sports: const SportsCapability(
          leagues: [
            SportsLeague(
              id: 'hockey/nhl',
              name: 'NHL',
              abbreviation: 'NHL',
              isDefault: true,
            ),
          ],
        ),
        sportsEditor: editor,
        onChannelSelect: played.add,
        onSportsMore: () => openedSports++,
      );
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pumpAndSettle();
      }

      final row = _section('Sports');
      expect(row, findsOneWidget);
      final game = find.descendant(
        of: row,
        matching: find.text('Toronto Maple Leafs'),
      );
      expect(game, findsOneWidget);
      expect(
        find.descendant(of: row, matching: find.text('1 channel')),
        findsOneWidget,
      );

      await tester.tap(game);
      await tester.pumpAndSettle();
      expect(played.map((channel) => channel.id), [eventChannel.id]);

      await tester.tap(
        find.descendant(of: row, matching: find.text('View All')),
      );
      await tester.pumpAndSettle();
      expect(openedSports, 1);

      // Unmount so the score refresh timer is cancelled
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('rows keep their height while their first page loads', (
    tester,
  ) async {
    await pumpHome(
      tester,
      const _Catalog(channels: _channels, movies: _movies, series: _series),
    );

    final loadingHeight = tester.getSize(_section('Movies')).height;
    expect(find.text('Big Buck Bunny'), findsNothing);
    expect(find.text('No Movies available'), findsNothing);

    await _settle(tester);

    expect(find.text('Big Buck Bunny'), findsWidgets);
    expect(tester.getSize(_section('Movies')).height, loadingHeight);
  });

  testWidgets('a row with nothing in it is hidden', (tester) async {
    await pumpHome(
      tester,
      const _Catalog(channels: _channels, movies: _movies),
    );
    await _settle(tester);

    expect(find.text('Movies'), findsOneWidget);
    expect(find.text('Series'), findsNothing);
    expect(find.text('No Series available'), findsNothing);
    expect(find.text('Nothing to show yet'), findsNothing);
  });

  testWidgets('rows that cannot be read are hidden, not left loading', (
    tester,
  ) async {
    await pumpHome(
      tester,
      const _Catalog(channels: _channels, movies: _movies, series: _series),
      unreadable: true,
    );
    await _settle(tester);

    expect(find.byType(MediaPreviewSection), findsNothing);
  });

  testWidgets('says so when the playlist has nothing to show', (tester) async {
    await pumpHome(tester, const _Catalog());
    await _settle(tester);

    expect(find.byType(MediaPreviewSection), findsNothing);
    expect(find.text('Nothing to show yet'), findsOneWidget);
  });

  group('nav layout', () {
    const full = _Catalog(
      channels: _channels,
      movies: _movies,
      series: _series,
    );

    Future<ViewSettingsService> serviceWith(
      NavLayout Function(NavLayout) change,
    ) async {
      final service = _rowsOnlySettings();
      await service.setNavLayout(change(NavLayout.defaults));
      return service;
    }

    double rowTop(WidgetTester tester, String title) =>
        tester.getTopLeft(find.text(title).first).dy;

    testWidgets('rows follow the saved order', (tester) async {
      final all = NavLayout.customizableRoutes;
      await pumpHome(
        tester,
        full,
        viewSettings: await serviceWith(
          (layout) => layout.moved(RouteNames.series, -10, all),
        ),
      );
      await _settle(tester);

      expect(rowTop(tester, 'Live TV'), lessThan(rowTop(tester, 'Movies')));
      expect(rowTop(tester, 'Series'), lessThan(rowTop(tester, 'Live TV')));
    });

    testWidgets('a server category row shows just its category, in place', (
      tester,
    ) async {
      final settings = _rowsOnlySettings();
      await settings.applyClientConfig(
        ClientConfig.fromJson(const {
          'revision': 'rev',
          'home_screen': {
            'mode': 'default',
            'sections': [
              {
                'section': 'movies',
                'nav': true,
                'home': true,
                'rows': [
                  {
                    'id': 'shorts',
                    'kind': 'category',
                    'title': 'Animal Shorts',
                    'params': {'category_id': '40'},
                  },
                  {'id': 'default', 'kind': 'default'},
                ],
              },
            ],
          },
        }),
      );
      await pumpHome(
        tester,
        const _Catalog(movies: [..._movies, ..._otherMovies]),
        viewSettings: settings,
      );
      await _settle(tester);

      final shorts = _section('Animal Shorts');
      expect(
        find.descendant(of: shorts, matching: find.text('Elephants Dream')),
        findsWidgets,
      );
      expect(
        find.descendant(of: shorts, matching: find.text('Big Buck Bunny')),
        findsNothing,
      );
      expect(
        rowTop(tester, 'Animal Shorts'),
        lessThan(rowTop(tester, 'Movies')),
      );

      await settings.setHomeRowShown('shorts', shown: false);
      await _settle(tester);
      expect(find.text('Animal Shorts'), findsNothing);
      expect(find.text('Movies'), findsWidgets);
    });

    testWidgets('a row turned off is gone, and its siblings stay', (
      tester,
    ) async {
      await pumpHome(
        tester,
        full,
        viewSettings: await serviceWith(
          (layout) => layout.withHomeRow(RouteNames.vod, shown: false),
        ),
      );
      await _settle(tester);

      expect(find.text('Big Buck Bunny'), findsNothing);
      expect(find.text('Sintel Saga'), findsWidgets);
    });

    testWidgets('AIOStreams and Requests rows are opt-in', (tester) async {
      await pumpHome(
        tester,
        full,
        hasAioStreams: true,
        hasRequests: true,
      );
      await _settle(tester);

      expect(find.text('Browse your AIOStreams catalogs'), findsNothing);
      expect(
        find.text('Search for and request movies and shows'),
        findsNothing,
      );
    });

    testWidgets('AIOStreams and Requests rows show once turned on', (
      tester,
    ) async {
      await pumpHome(
        tester,
        full,
        hasAioStreams: true,
        hasRequests: true,
        viewSettings: await serviceWith(
          (layout) => layout
              .withHomeRow(RouteNames.aiostreams, shown: true)
              .withHomeRow(RouteNames.requests, shown: true),
        ),
      );
      await _settle(tester);

      expect(
        find.text('Browse your AIOStreams catalogs'),
        findsOneWidget,
      );
      expect(
        find.text('Search for and request movies and shows'),
        findsOneWidget,
      );
    });

    testWidgets('a turned-on row without its feature stays hidden', (
      tester,
    ) async {
      await pumpHome(
        tester,
        full,
        viewSettings: await serviceWith(
          (layout) => layout.withHomeRow(RouteNames.aiostreams, shown: true),
        ),
      );
      await _settle(tester);

      expect(find.text('Browse your AIOStreams catalogs'), findsNothing);
    });

    testWidgets('says so when the user hid every row with content', (
      tester,
    ) async {
      await pumpHome(
        tester,
        full,
        viewSettings: await serviceWith((layout) {
          var next = layout;
          for (final route in NavLayout.customizableRoutes) {
            next = next.withHomeRow(route, shown: false);
          }
          return next;
        }),
      );
      await _settle(tester);

      expect(find.byType(MediaPreviewSection), findsNothing);
      expect(find.text('Nothing to show yet'), findsOneWidget);
    });

    testWidgets('a visible DVR entry row counts as something to show', (
      tester,
    ) async {
      await pumpHome(tester, const _Catalog(), hasDvr: true);
      await _settle(tester);

      expect(find.text('DVR Recordings'), findsOneWidget);
      expect(find.text('Nothing to show yet'), findsNothing);
    });

    testWidgets('DVR hidden from Home no longer blocks the empty message', (
      tester,
    ) async {
      await pumpHome(
        tester,
        const _Catalog(),
        hasDvr: true,
        viewSettings: await serviceWith(
          (layout) => layout.withHomeRow(RouteNames.dvr, shown: false),
        ),
      );
      await _settle(tester);

      expect(find.text('Nothing to show yet'), findsOneWidget);
    });

    group('Sports on a day with no games', () {
      const capability = SportsCapability(
        leagues: [
          SportsLeague(
            id: 'hockey/nhl',
            name: 'NHL',
            abbreviation: 'NHL',
            isDefault: true,
          ),
        ],
      );

      Future<XtreamService> gameless(WidgetTester tester) async =>
          (await tester.runAsync(() async {
            final service = XtreamService(
              transport: (request) async {
                if (request.action == null) {
                  return {
                    'user_info': {'auth': 1, 'status': 'Active'},
                    'm3u_editor': {
                      'version': '0.14.0',
                      'features': ['sports'],
                    },
                  };
                }
                return {'fixtures': <Object?>[]};
              },
            );
            await service.authenticate(
              const UserCredentials(
                server: 'https://editor.example',
                username: 'user',
                password: 'pass',
              ),
            );
            return service;
          }))!;

      // Only Sports left on Home, as someone who only wants games would set up.
      NavLayout onlySports(NavLayout layout) {
        var next = layout;
        for (final route in NavLayout.customizableRoutes) {
          if (route != RouteNames.sports) {
            next = next.withHomeRow(route, shown: false);
          }
        }
        return next;
      }

      testWidgets('shows the empty message when Sports is in the nav', (
        tester,
      ) async {
        await pumpHome(
          tester,
          full,
          sports: capability,
          sportsEditor: await gameless(tester),
          onSportsMore: () {},
          viewSettings: await serviceWith(onlySports),
        );
        await _settle(tester);

        expect(find.byType(MediaPreviewSection), findsNothing);
        expect(find.text('Nothing to show yet'), findsOneWidget);
      });

      testWidgets('keeps a way in when Sports is off the nav', (tester) async {
        var opened = 0;
        await pumpHome(
          tester,
          full,
          sports: capability,
          sportsEditor: await gameless(tester),
          onSportsMore: () => opened += 1,
          viewSettings: await serviceWith(
            (layout) =>
                onlySports(layout).withNav(RouteNames.sports, shown: false),
          ),
        );
        await _settle(tester);

        expect(find.text('Nothing to show yet'), findsNothing);
        await tester.tap(find.text('No games on this day').first);
        await tester.pump();
        expect(opened, 1);
      });
    });

    testWidgets('the rich layout shows the empty message too', (tester) async {
      final service = _rowsOnlySettings();
      await service.setHomeScreenStyle(HomeScreenStyle.rich);
      await pumpHome(tester, const _Catalog(), viewSettings: service);
      await _settle(tester);

      expect(find.text('Nothing to show yet'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('left from the empty message opens the sidebar', (
      tester,
    ) async {
      var activations = 0;
      await pumpHome(
        tester,
        const _Catalog(),
        onSidebarActivate: () => activations += 1,
      );
      await _settle(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();

      expect(activations, 1);
    });
  });

  testWidgets('View All at the end of a row opens its full list', (
    tester,
  ) async {
    var opened = 0;
    await pumpHome(
      tester,
      const _Catalog(channels: _channels, movies: _movies, series: _series),
      onMoviesMore: () => opened += 1,
    );
    await _settle(tester);

    for (final title in ['Live TV', 'Movies', 'Series']) {
      expect(
        find.descendant(of: _section(title), matching: find.text('View All')),
        findsOneWidget,
      );
    }
    await tester.tap(
      find.ancestor(
        of: find.descendant(
          of: _section('Movies'),
          matching: find.text('View All'),
        ),
        matching: find.byType(DpadInkWell),
      ),
    );
    expect(opened, 1);
  });

  testWidgets('a playlist switch starts the rows over', (tester) async {
    final repo = await pumpHome(tester, const _Catalog(movies: _movies));
    await _settle(tester);
    expect(find.text('Big Buck Bunny'), findsWidgets);

    const next = _Catalog(movies: _otherMovies);
    await tester.runAsync(() => _fill(repo, next));
    ProviderScope.containerOf(
      tester.element(find.byType(HomeScreen)),
    ).read(shown.notifier).state = (
      'second',
      next,
    );
    await tester.pump();

    // Loading the new playlist's movies, not still showing the last one's.
    expect(find.text('Big Buck Bunny'), findsNothing);
    expect(_section('Movies'), findsOneWidget);

    await _settle(tester);
    expect(find.text('Elephants Dream'), findsWidgets);
  });

  testWidgets('after a switch the Live row waits for that playlist favorites', (
    tester,
  ) async {
    final favorites = _GatedFavorites({1});
    final repo = await pumpHome(
      tester,
      const _Catalog(channels: _channels),
      liveFavorites: favorites,
    );
    await _settle(tester);
    expect(find.text('Favorite Channels'), findsOneWidget);

    // The next playlist has its own channel 1, no favorites, and they are
    // slow to read.
    const next = _Catalog(
      channels: [
        Channel(id: 1, name: 'Sports One', streamUrl: 'http://x/s1'),
      ],
    );
    final gate = Completer<void>();
    favorites
      ..ids = <int>{}
      ..gate = gate
      ..notifyPlaylistChanged();
    await tester.runAsync(() => _fill(repo, next));
    ProviderScope.containerOf(
      tester.element(find.byType(HomeScreen)),
    ).read(shown.notifier).state = (
      'second',
      next,
    );
    await _settle(tester);

    // Not "Favorite Channels" picked by the last playlist's ids.
    expect(find.text('Favorite Channels'), findsNothing);
    expect(find.text('Sports One'), findsNothing);

    gate.complete();
    await _settle(tester);
    expect(_section('Live TV'), findsOneWidget);
    expect(find.text('Sports One'), findsOneWidget);
  });

  testWidgets('a favorite toggled on Home is read back once', (tester) async {
    final favorites = _GatedFavorites(<int>{});
    await pumpHome(
      tester,
      const _Catalog(channels: _channels),
      liveFavorites: favorites,
    );
    await _settle(tester);
    final readsBefore = favorites.reads;

    await tester.longPress(find.text('BBC One'));
    await _settle(tester);

    expect(favorites.reads - readsBefore, 1);
  });

  group('rows follow the order their screen shows', () {
    const movies = <VodItem>[
      VodItem(
        id: 1,
        name: 'Alpha',
        streamUrl: 'http://x/1.mp4',
        containerExtension: 'mp4',
        categoryId: '20',
      ),
      VodItem(
        id: 2,
        name: 'Middle',
        streamUrl: 'http://x/2.mp4',
        containerExtension: 'mp4',
        categoryId: '20',
      ),
      VodItem(
        id: 3,
        name: 'Zulu',
        streamUrl: 'http://x/3.mp4',
        containerExtension: 'mp4',
        categoryId: '20',
      ),
    ];
    const series = <Series>[
      Series(id: 1, name: 'Ant Saga', categoryId: '30'),
      Series(id: 2, name: 'Yak Saga', categoryId: '30'),
    ];
    const channels = <Channel>[
      Channel(id: 1, name: 'Able', streamUrl: 'http://x/1', categoryId: '10'),
      Channel(id: 2, name: 'Baker', streamUrl: 'http://x/2', categoryId: '10'),
    ];

    /// The names in [expected], which must read left to right on screen.
    void expectOrder(WidgetTester tester, List<String> expected) {
      final positions = [
        for (final name in expected)
          tester.getTopLeft(find.text(name).first).dx,
      ];
      expect(positions, orderedEquals([...positions]..sort()));
    }

    testWidgets('Movies re-sorts its row', (tester) async {
      final settings = _rowsOnlySettings();
      await pumpHome(
        tester,
        const _Catalog(movies: movies),
        viewSettings: settings,
      );
      await _settle(tester);
      expectOrder(tester, ['Alpha', 'Middle', 'Zulu']);

      settings.setVodBrowseOrder((
        sort: MediaSortOption.titleDesc,
        favoritesFirst: true,
      ));
      await _settle(tester);

      expectOrder(tester, ['Zulu', 'Middle', 'Alpha']);
    });

    testWidgets('Series re-sorts its row', (tester) async {
      final settings = _rowsOnlySettings();
      await pumpHome(
        tester,
        const _Catalog(series: series),
        viewSettings: settings,
      );
      await _settle(tester);
      expectOrder(tester, ['Ant Saga', 'Yak Saga']);

      settings.setSeriesBrowseOrder((
        sort: MediaSortOption.titleDesc,
        favoritesFirst: true,
      ));
      await _settle(tester);

      expectOrder(tester, ['Yak Saga', 'Ant Saga']);
    });

    testWidgets('Movies Favorites First leads the row with favorites', (
      tester,
    ) async {
      final settings = _rowsOnlySettings();
      await pumpHome(
        tester,
        const _Catalog(movies: movies),
        viewSettings: settings,
        vodFavorites: _GatedFavorites({3}),
      );
      await _settle(tester);
      expectOrder(tester, ['Zulu', 'Alpha', 'Middle']);

      settings.setVodBrowseOrder((
        sort: MediaSortOption.defaultOrder,
        favoritesFirst: false,
      ));
      await _settle(tester);

      expectOrder(tester, ['Alpha', 'Middle', 'Zulu']);
    });

    testWidgets('Live TV re-sorts its row', (tester) async {
      final settings = _rowsOnlySettings();
      await pumpHome(
        tester,
        const _Catalog(channels: channels),
        viewSettings: settings,
      );
      await _settle(tester);
      expectOrder(tester, ['Able', 'Baker']);

      settings.setLiveTvBrowseOrder((
        sort: ChannelSortOption.alphabeticalDesc,
        favoritesFirst: true,
      ));
      await _settle(tester);

      expectOrder(tester, ['Baker', 'Able']);
    });

    testWidgets('the favorites row sorts too, and only shows while they lead', (
      tester,
    ) async {
      final settings = _rowsOnlySettings();
      await pumpHome(
        tester,
        const _Catalog(
          channels: [
            ...channels,
            Channel(
              id: 3,
              name: 'Charlie',
              streamUrl: 'http://x/3',
              categoryId: '10',
            ),
          ],
        ),
        viewSettings: settings,
        liveFavorites: _GatedFavorites({1, 3}),
      );
      await _settle(tester);
      expect(find.text('Baker'), findsNothing);
      expectOrder(tester, ['Able', 'Charlie']);

      settings.setLiveTvBrowseOrder((
        sort: ChannelSortOption.alphabeticalDesc,
        favoritesFirst: true,
      ));
      await _settle(tester);
      expect(find.text('Baker'), findsNothing);
      expectOrder(tester, ['Charlie', 'Able']);

      settings.setLiveTvBrowseOrder((
        sort: ChannelSortOption.alphabeticalDesc,
        favoritesFirst: false,
      ));
      await _settle(tester);
      expectOrder(tester, ['Charlie', 'Baker', 'Able']);
    });
  });
}

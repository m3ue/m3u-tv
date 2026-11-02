import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/home/home_screen.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:m3u_tv/services/catalog_db/catalog_codec.dart';
import 'package:m3u_tv/services/catalog_db/catalog_database.dart';
import 'package:m3u_tv/services/catalog_db/catalog_repository.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/epg_service.dart';
import 'package:m3u_tv/services/favorites_service.dart';
import 'package:m3u_tv/services/view_settings_service.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';

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
      sourceKey: CatalogRepository.activeSource,
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
  }) async {
    // A TV screen: every row is on it.
    await tester.binding.setSurfaceSize(const Size(1920, 1080));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    shown = StateProvider<(String, _Catalog)>((_) => ('first', catalog));
    final repo = await _buildRepo(tester, catalog);
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
          hasDvrFeatureProvider.overrideWith((_) => false),
          epgServiceProvider.overrideWith((_) => EpgService()),
          recordingChannelIdsProvider.overrideWith((_) => const <int>{}),
          viewSettingsServiceProvider.overrideWith(
            (_) => ViewSettingsService(),
          ),
          liveFavoritesServiceProvider.overrideWith(
            (_) => liveFavorites ?? FavoritesService(memory: memory),
          ),
          vodFavoritesServiceProvider.overrideWith(
            (_) => FavoritesService(memory: memory, namespace: 'vod'),
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
            onChannelSelect: (_) {},
            onVodSelect: (_) {},
            onSeriesSelect: (_) {},
            onProgressSelect: (_) {},
            onContinueWatchingMore: () {},
            onLiveTvMore: () {},
            onMoviesMore: onMoviesMore ?? () {},
            onSeriesMore: () {},
            onRecordingsSelect: () {},
            onAioStreamsItemSelect: (_, _) {},
            useSidebarLayout: true,
          ),
        ),
      ),
    );
    return repo;
  }

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
    expect(find.text('This playlist has nothing to show yet'), findsNothing);
  });

  testWidgets('says so when the playlist has nothing to show', (tester) async {
    await pumpHome(tester, const _Catalog());
    await _settle(tester);

    expect(find.byType(MediaPreviewSection), findsNothing);
    expect(find.text('This playlist has nothing to show yet'), findsOneWidget);
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
}

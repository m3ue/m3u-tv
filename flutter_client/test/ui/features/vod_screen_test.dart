import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/vod/vod_screen.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:m3u_tv/services/catalog_db/catalog_codec.dart';
import 'package:m3u_tv/services/catalog_db/catalog_database.dart';
import 'package:m3u_tv/services/catalog_db/catalog_repository.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/favorites_service.dart';
import 'package:m3u_tv/services/view_settings_service.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';

/// Builds a fresh in-memory catalog repository populated with [vodItems].
/// Drift's real I/O does not resolve under flutter_test's default fakeAsync
/// zone, so this - and every subsequent pump that touches the repository -
/// runs via `tester.runAsync`.
Future<CatalogRepository> _buildRepo(
  WidgetTester tester,
  List<VodItem> vodItems,
) async {
  final repo = await tester.runAsync(() async {
    final db = CatalogDatabase.memory();
    addTearDown(db.close);
    final repo = CatalogRepository(db);
    await repo.replaceItems(
      sourceKey: CatalogRepository.activeSource,
      kind: kCatalogKindVod,
      items: vodItems,
    );
    return repo;
  });
  return repo!;
}

Future<void> _settle(WidgetTester tester) => tester.pumpAndSettle();

void main() {
  // Rendering a real poster URL kicks off flutter_cache_manager's disk-cache
  // lookup via path_provider. That's inert under plain fakeAsync (nothing
  // ever runs it for real), but tester.runAsync (needed above for drift)
  // runs in a real zone, so the plugin channel call actually fires and
  // throws MissingPluginException - sometimes attributed to a *later* test
  // since the leaked async chain outlives the test that started it. Give it
  // a real, writable answer instead of leaving the channel unmocked.
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => Directory.systemTemp.path,
        );
  });

  group('VodScreen', () {
    late List<VodItem> testVodItems;
    late List<Category> testCategories;

    setUp(() {
      testVodItems = [
        const VodItem(
          id: 1,
          name: 'Big Buck Bunny',
          streamUrl: 'http://example.com/1.mp4',
          containerExtension: 'mp4',
          logoUrl: 'http://example.com/bunny.jpg',
          categoryId: '20',
          rating: 4.5,
        ),
        const VodItem(
          id: 2,
          name: 'Sintel',
          streamUrl: 'http://example.com/2.mp4',
          containerExtension: 'mp4',
          logoUrl: 'http://example.com/sintel.jpg',
          categoryId: '21',
          rating: 4,
        ),
        const VodItem(
          id: 3,
          name: 'Tears of Steel',
          streamUrl: 'http://example.com/3.mkv',
          containerExtension: 'mkv',
          categoryId: '20',
        ),
      ];
      testCategories = [
        const Category(id: '20', name: 'Action'),
        const Category(id: '21', name: 'Drama'),
      ];
    });

    testWidgets('renders movie grid with names', (tester) async {
      final repo = await _buildRepo(tester, testVodItems);
      await tester.pumpWidget(
        _TestApp(catalogRepository: repo, categories: testCategories),
      );
      await _settle(tester);

      expect(find.text('Big Buck Bunny'), findsOneWidget);
      expect(find.text('Sintel'), findsOneWidget);
      expect(find.text('Tears of Steel'), findsOneWidget);
    });

    testWidgets('narrow phone layout does not overflow movie cards', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = await _buildRepo(tester, testVodItems);
      await tester.pumpWidget(
        _TestApp(catalogRepository: repo, categories: testCategories),
      );
      await _settle(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Big Buck Bunny'), findsOneWidget);
      expect(find.text('★ 4.5'), findsOneWidget);
    });

    testWidgets('large desktop grids keep movie cards comfortably sized', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final manyMovies = List<VodItem>.generate(
        40,
        (index) => VodItem(
          id: index,
          name: 'Desktop Movie $index',
          streamUrl: 'http://example.com/$index.mp4',
          containerExtension: 'mp4',
          categoryId: '20',
        ),
      );
      final repo = await _buildRepo(tester, manyMovies);

      for (final viewport in [
        const Size(1440, 900),
        const Size(1920, 1080),
        const Size(2560, 1440),
      ]) {
        tester.view.physicalSize = viewport;
        await tester.pumpWidget(
          _TestApp(catalogRepository: repo, categories: testCategories),
        );
        await _settle(tester);

        expect(tester.takeException(), isNull);
        final firstMovieCard = find.ancestor(
          of: find.text('Desktop Movie 0'),
          matching: find.byType(DpadInkWell),
        );
        expect(firstMovieCard, findsOneWidget);
        expect(tester.getSize(firstMovieCard).width, lessThanOrEqualTo(220));
      }
    });

    testWidgets('renders All Movies and category tabs', (tester) async {
      final repo = await _buildRepo(tester, testVodItems);
      await tester.pumpWidget(
        _TestApp(catalogRepository: repo, categories: testCategories),
      );
      await _settle(tester);

      expect(find.text('All Movies'), findsOneWidget);
      expect(find.text('Action'), findsOneWidget);
      expect(find.text('Drama'), findsOneWidget);
    });

    testWidgets('tapping category tab filters movies', (tester) async {
      final repo = await _buildRepo(tester, testVodItems);
      await tester.pumpWidget(
        _TestApp(catalogRepository: repo, categories: testCategories),
      );
      await _settle(tester);

      await tester.tap(find.text('Action'));
      await _settle(tester);

      // Only Action movies should be visible
      expect(find.text('Big Buck Bunny'), findsOneWidget);
      expect(find.text('Tears of Steel'), findsOneWidget);
      expect(find.text('Sintel'), findsNothing);
    });

    testWidgets(
      'dynamic category tab filters movies by overlapping category_ids',
      (tester) async {
        // m3u-editor's dynamic TMDB categories overlap the regular groups:
        // a member keeps its primary categoryId and additionally carries the
        // dynamic category id in categoryIds.
        final items = [
          const VodItem(
            id: 1,
            name: 'Big Buck Bunny',
            streamUrl: 'http://example.com/1.mp4',
            containerExtension: 'mp4',
            categoryId: '20',
            categoryIds: ['20', '900000001'],
          ),
          const VodItem(
            id: 2,
            name: 'Sintel',
            streamUrl: 'http://example.com/2.mp4',
            containerExtension: 'mp4',
            categoryId: '20',
          ),
        ];
        final categories = [
          const Category(id: '900000001', name: 'Trending Now'),
          const Category(id: '20', name: 'Action'),
        ];
        final repo = await _buildRepo(tester, items);

        await tester.pumpWidget(
          _TestApp(catalogRepository: repo, categories: categories),
        );
        await _settle(tester);

        await tester.tap(find.text('Trending Now'));
        await _settle(tester);

        expect(find.text('Big Buck Bunny'), findsOneWidget);
        expect(find.text('Sintel'), findsNothing);
      },
    );

    testWidgets('shows not configured message when not connected', (
      tester,
    ) async {
      final repo = await _buildRepo(tester, testVodItems);
      await tester.pumpWidget(
        _TestApp(
          catalogRepository: repo,
          categories: testCategories,
          isConfigured: false,
        ),
      );
      await _settle(tester);

      expect(
        find.text('Please connect to your service in Settings'),
        findsOneWidget,
      );
    });

    testWidgets('category bar and movie grid expose scrollbars', (
      tester,
    ) async {
      final manyCategories = List<Category>.generate(
        16,
        (index) => Category(id: '$index', name: 'Category $index'),
      );
      final repo = await _buildRepo(tester, testVodItems);

      await tester.pumpWidget(
        _TestApp(catalogRepository: repo, categories: manyCategories),
      );
      await _settle(tester);

      expect(find.byType(Scrollbar), findsWidgets);
    });

    testWidgets('inline search filters movies case-insensitively', (
      tester,
    ) async {
      final repo = await _buildRepo(tester, testVodItems);
      await tester.pumpWidget(
        _TestApp(catalogRepository: repo, categories: testCategories),
      );
      await _settle(tester);

      await tester.tap(find.byIcon(Icons.search));
      await _settle(tester);
      await tester.enterText(find.byType(TextField), 'sintel');
      await _settle(tester);

      expect(find.text('Sintel'), findsOneWidget);
      expect(find.text('Big Buck Bunny'), findsNothing);
      expect(find.text('Tears of Steel'), findsNothing);
    });

    testWidgets('replacing a query is debounced; old results stay until the '
        'pause', (tester) async {
      final repo = await _buildRepo(tester, testVodItems);
      await tester.pumpWidget(
        _TestApp(catalogRepository: repo, categories: testCategories),
      );
      await _settle(tester);

      await tester.tap(find.byIcon(Icons.search));
      await _settle(tester);

      // First query applies immediately (no debounce-length empty flash).
      await tester.enterText(find.byType(TextField), 'sintel');
      await _settle(tester);
      expect(find.text('Sintel'), findsOneWidget);

      // Replacing it: the grid keeps showing the previous match for the
      // debounce window, then switches once typing settles.
      await tester.enterText(find.byType(TextField), 'steel');
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Sintel'), findsOneWidget);
      expect(find.text('Tears of Steel'), findsNothing);

      await tester.pump(const Duration(milliseconds: 200));
      await _settle(tester);
      expect(find.text('Sintel'), findsNothing);
      expect(find.text('Tears of Steel'), findsOneWidget);
    });

    testWidgets('inline search composes with category filter', (tester) async {
      final repo = await _buildRepo(tester, testVodItems);
      await tester.pumpWidget(
        _TestApp(catalogRepository: repo, categories: testCategories),
      );
      await _settle(tester);

      await tester.tap(find.text('Action'));
      await _settle(tester);
      await tester.tap(find.byIcon(Icons.search));
      await _settle(tester);
      await tester.enterText(find.byType(TextField), 'steel');
      await _settle(tester);

      expect(find.text('Tears of Steel'), findsOneWidget);
      expect(find.text('Big Buck Bunny'), findsNothing);
      expect(find.text('Sintel'), findsNothing);
    });

    testWidgets('tapping movie triggers onVodSelect callback', (tester) async {
      VodItem? selectedItem;
      final repo = await _buildRepo(tester, testVodItems);
      await tester.pumpWidget(
        _TestApp(
          catalogRepository: repo,
          categories: testCategories,
          onVodSelect: (item) => selectedItem = item,
        ),
      );
      await _settle(tester);

      await tester.tap(find.text('Big Buck Bunny'));
      await _settle(tester);

      expect(selectedItem, isNotNull);
      expect(selectedItem!.id, 1);
    });

    testWidgets('shows rating when available', (tester) async {
      final repo = await _buildRepo(tester, testVodItems);
      await tester.pumpWidget(
        _TestApp(catalogRepository: repo, categories: testCategories),
      );
      await _settle(tester);

      expect(find.text('★ 4.5'), findsOneWidget);
    });

    testWidgets(
      'mobile layout shows a Filter button instead of category chips, '
      'and selecting a category filters the grid',
      (tester) async {
        final repo = await _buildRepo(tester, testVodItems);
        await tester.pumpWidget(
          _TestApp(
            catalogRepository: repo,
            categories: testCategories,
            useSidebarLayout: false,
          ),
        );
        await _settle(tester);

        expect(find.text('Filter'), findsOneWidget);
        expect(find.text('Action'), findsNothing);

        await tester.tap(find.text('Filter'));
        await _settle(tester);

        expect(find.text('Action'), findsOneWidget);
        await tester.tap(find.text('Action'));
        await _settle(tester);

        expect(find.text('Big Buck Bunny'), findsOneWidget);
        expect(find.text('Sintel'), findsNothing);
      },
    );
  });

  // ---------------------------------------------------------------------
  // #235 VOD sort (dedicated "Sort" button next to search, both layouts)
  //
  // All four items are in the same category so the category filter is a
  // no-op and any reorder is purely the sort step. The default (server)
  // order is AAAA → BBBB → CCCC → DDDD; ratingDesc produces
  // AAAA → DDDD → BBBB → CCCC (unrated sinks last).
  // ---------------------------------------------------------------------
  group('VodScreen sort', () {
    late List<VodItem> sortItems;
    late List<Category> sortCategories;

    setUp(() {
      sortItems = const [
        VodItem(
          id: 1,
          name: 'AAAA Highest',
          streamUrl: 'http://example.com/1.mp4',
          containerExtension: 'mp4',
          categoryId: '20',
          rating: 9,
          year: '2020',
        ),
        VodItem(
          id: 2,
          name: 'BBBB Mid',
          streamUrl: 'http://example.com/2.mp4',
          containerExtension: 'mp4',
          categoryId: '20',
          rating: 7,
          year: '1999',
        ),
        VodItem(
          id: 3,
          name: 'CCCC Unrated',
          streamUrl: 'http://example.com/3.mp4',
          containerExtension: 'mp4',
          categoryId: '20',
        ),
        VodItem(
          id: 4,
          name: 'DDDD Third',
          streamUrl: 'http://example.com/4.mp4',
          containerExtension: 'mp4',
          categoryId: '20',
          rating: 8,
          year: '2010',
        ),
      ];
      sortCategories = const [Category(id: '20', name: 'Action')];
    });

    // Reads the four movie titles in document (widget-tree) order. The
    // grid renders them left-to-right, top-to-bottom; `find.byType(Text)`
    // returns matches in tree order, which is the same order the windowed
    // grid paged them in from the catalog repository.
    List<String> gridTitles(WidgetTester tester) {
      const knownNames = {
        'AAAA Highest',
        'BBBB Mid',
        'CCCC Unrated',
        'DDDD Third',
      };
      return tester
          .widgetList<Text>(find.byType(Text))
          .where(
            (text) => text.data != null && knownNames.contains(text.data),
          )
          .map((text) => text.data!)
          .toList();
    }

    testWidgets(
      'tapping Sort opens the sort menu with Default, Rating, Cancel',
      (tester) async {
        final repo = await _buildRepo(tester, sortItems);
        await tester.pumpWidget(
          _TestApp(
            catalogRepository: repo,
            categories: sortCategories,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.sort));
        await tester.pumpAndSettle();

        expect(find.text('Sort Movies By'), findsOneWidget);
        expect(find.text('Default'), findsOneWidget);
        expect(find.text('Rating'), findsOneWidget);
        expect(find.text('Cancel'), findsOneWidget);
      },
    );

    testWidgets(
      'selecting Rating re-sorts the grid descending by rating, unrated last',
      (tester) async {
        final repo = await _buildRepo(tester, sortItems);
        await tester.pumpWidget(
          _TestApp(
            catalogRepository: repo,
            categories: sortCategories,
          ),
        );
        await tester.pumpAndSettle();

        // Sanity: default order has BBBB before DDDD.
        expect(gridTitles(tester), [
          'AAAA Highest',
          'BBBB Mid',
          'CCCC Unrated',
          'DDDD Third',
        ]);

        await tester.tap(find.byIcon(Icons.sort));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Rating'));
        await tester.pumpAndSettle();

        expect(gridTitles(tester), [
          'AAAA Highest',
          'DDDD Third',
          'BBBB Mid',
          'CCCC Unrated',
        ]);
      },
    );

    testWidgets(
      'selecting Default reverts to the original server order',
      (
        tester,
      ) async {
        final repo = await _buildRepo(tester, sortItems);
        await tester.pumpWidget(
          _TestApp(
            catalogRepository: repo,
            categories: sortCategories,
          ),
        );
        await tester.pumpAndSettle();

        // Apply Rating first so we have something to revert.
        await tester.tap(find.byIcon(Icons.sort));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Rating'));
        await tester.pumpAndSettle();

        // Now switch back to Default.
        await tester.tap(find.byIcon(Icons.sort));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Default'));
        await tester.pumpAndSettle();

        expect(gridTitles(tester), [
          'AAAA Highest',
          'BBBB Mid',
          'CCCC Unrated',
          'DDDD Third',
        ]);
      },
    );

    testWidgets(
      'sort dialog autofocuses and checks the currently-active row, not always the first',
      (tester) async {
        final repo = await _buildRepo(tester, sortItems);
        await tester.pumpWidget(
          _TestApp(
            catalogRepository: repo,
            categories: sortCategories,
          ),
        );
        await tester.pumpAndSettle();

        // Switch to Rating first so Default is NOT active.
        await tester.tap(find.byIcon(Icons.sort));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Rating'));
        await tester.pumpAndSettle();

        // Re-open the dialog - Rating should now be the active row.
        await tester.tap(find.byIcon(Icons.sort));
        await tester.pumpAndSettle();

        // The check icon is the active-row indicator. It must sit next to
        // "Rating", not "Default".
        final ratingCheck = find.descendant(
          of: find.ancestor(
            of: find.text('Rating'),
            matching: find.byType(Row),
          ),
          matching: find.byIcon(Icons.check),
        );
        expect(ratingCheck, findsOneWidget);

        final defaultCheck = find.descendant(
          of: find.ancestor(
            of: find.text('Default'),
            matching: find.byType(Row),
          ),
          matching: find.byIcon(Icons.check),
        );
        expect(defaultCheck, findsNothing);
      },
    );

    testWidgets(
      'with rememberMediaSort false (default), restart does not restore Rating sort',
      (tester) async {
        final service = ViewSettingsService();
        // Distinct Keys between pumps force Flutter to recreate the
        // Element/State subtree - otherwise pumpWidget reuses the State
        // because the widget types match, and `_loadSortPreference`'s
        // initState path never runs again.
        const firstKey = ValueKey('restart-first');
        const secondKey = ValueKey('restart-second');
        final repo = await _buildRepo(tester, sortItems);
        await tester.pumpWidget(
          _TestApp(
            key: firstKey,
            catalogRepository: repo,
            categories: sortCategories,
            viewSettingsService: service,
          ),
        );
        await tester.pumpAndSettle();

        // Apply Rating once.
        await tester.tap(find.byIcon(Icons.sort));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Rating'));
        await tester.pumpAndSettle();

        // Per the plan, the service is only written when
        // `rememberMediaSort` is true - session-only choices deliberately
        // leave the on-disk value at the conservative default.
        expect(await service.vodSortOption(), MediaSortOption.defaultOrder);
        expect(await service.rememberMediaSort(), isFalse);

        // Re-mount from scratch with the same persistent service. The new
        // _VodScreenState starts with `_sortOption = defaultOrder` and the
        // remember=false guard skips the persisted vodSortOption read.
        await tester.pumpWidget(
          _TestApp(
            key: secondKey,
            catalogRepository: repo,
            categories: sortCategories,
            viewSettingsService: service,
          ),
        );
        await tester.pumpAndSettle();

        expect(gridTitles(tester), [
          'AAAA Highest',
          'BBBB Mid',
          'CCCC Unrated',
          'DDDD Third',
        ]);
      },
    );

    testWidgets(
      'with rememberMediaSort true, the persisted Rating sort is restored on restart',
      (tester) async {
        final service = ViewSettingsService();
        await service.setRememberMediaSort(true);
        await service.setVodSortOption(MediaSortOption.ratingDesc);

        final repo = await _buildRepo(tester, sortItems);
        await tester.pumpWidget(
          _TestApp(
            catalogRepository: repo,
            categories: sortCategories,
            viewSettingsService: service,
          ),
        );
        await tester.pumpAndSettle();

        // No user interaction with the dialog this run — the grid should
        // already show the persisted rating order because
        // _loadSortPreference read vodSortOption() at startup.
        expect(gridTitles(tester), [
          'AAAA Highest',
          'DDDD Third',
          'BBBB Mid',
          'CCCC Unrated',
        ]);
      },
    );

    testWidgets(
      'mobile (stacked) layout renders the same Sort button next to Filter',
      (tester) async {
        final repo = await _buildRepo(tester, sortItems);
        await tester.pumpWidget(
          _TestApp(
            catalogRepository: repo,
            categories: sortCategories,
            useSidebarLayout: false,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Filter'), findsOneWidget);
        expect(find.text('Sort'), findsOneWidget);

        await tester.tap(find.byIcon(Icons.sort));
        await tester.pumpAndSettle();

        expect(find.text('Sort Movies By'), findsOneWidget);
        await tester.tap(find.text('Rating'));
        await tester.pumpAndSettle();

        expect(gridTitles(tester), [
          'AAAA Highest',
          'DDDD Third',
          'BBBB Mid',
          'CCCC Unrated',
        ]);
      },
    );

    testWidgets(
      'selecting Newest First sorts by release date descending, unknown last',
      (tester) async {
        final repo = await _buildRepo(tester, sortItems);
        await tester.pumpWidget(
          _TestApp(catalogRepository: repo, categories: sortCategories),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.sort));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Newest First'));
        await tester.pumpAndSettle();

        expect(gridTitles(tester), [
          'AAAA Highest', // 2020
          'DDDD Third', // 2010
          'BBBB Mid', // 1999
          'CCCC Unrated', // no year
        ]);
      },
    );

    testWidgets(
      'selecting Oldest First sorts by release date ascending, unknown still last',
      (tester) async {
        final repo = await _buildRepo(tester, sortItems);
        await tester.pumpWidget(
          _TestApp(catalogRepository: repo, categories: sortCategories),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.sort));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Oldest First'));
        await tester.pumpAndSettle();

        expect(gridTitles(tester), [
          'BBBB Mid', // 1999
          'DDDD Third', // 2010
          'AAAA Highest', // 2020
          'CCCC Unrated', // no year - last, not first
        ]);
      },
    );

    testWidgets(
      'the Sort button label reflects the active sort, and reverts to "Sort" for Default',
      (tester) async {
        final repo = await _buildRepo(tester, sortItems);
        await tester.pumpWidget(
          _TestApp(catalogRepository: repo, categories: sortCategories),
        );
        await tester.pumpAndSettle();

        expect(find.text('Sort'), findsOneWidget);

        await tester.tap(find.byIcon(Icons.sort));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Newest First'));
        await tester.pumpAndSettle();

        expect(find.text('Newest First'), findsOneWidget);
        expect(find.text('Sort'), findsNothing);

        await tester.tap(find.byIcon(Icons.sort));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Default'));
        await tester.pumpAndSettle();

        expect(find.text('Sort'), findsOneWidget);
      },
    );
  });

  // ---------------------------------------------------------------------
  // Favorites First (Sort dialog switch, default on). Same four items as
  // the sort group; CCCC (3) and DDDD (4) are favorited, so favorites-first
  // provider order is CCCC -> DDDD -> AAAA -> BBBB.
  // ---------------------------------------------------------------------
  group('VodScreen favorites first', () {
    const items = [
      VodItem(
        id: 1,
        name: 'AAAA Highest',
        streamUrl: 'http://example.com/1.mp4',
        containerExtension: 'mp4',
        categoryId: '20',
        rating: 9,
      ),
      VodItem(
        id: 2,
        name: 'BBBB Mid',
        streamUrl: 'http://example.com/2.mp4',
        containerExtension: 'mp4',
        categoryId: '20',
        rating: 7,
      ),
      VodItem(
        id: 3,
        name: 'CCCC Unrated',
        streamUrl: 'http://example.com/3.mp4',
        containerExtension: 'mp4',
        categoryId: '20',
      ),
      VodItem(
        id: 4,
        name: 'DDDD Third',
        streamUrl: 'http://example.com/4.mp4',
        containerExtension: 'mp4',
        categoryId: '20',
        rating: 8,
      ),
    ];
    const categories = [Category(id: '20', name: 'Action')];

    late FavoritesService favorites;

    setUp(() async {
      favorites = FavoritesService();
      await favorites.add(3);
      await favorites.add(4);
    });

    List<String> gridTitles(WidgetTester tester) {
      final knownNames = items.map((item) => item.name).toSet();
      return tester
          .widgetList<Text>(find.byType(Text))
          .where((text) => knownNames.contains(text.data))
          .map((text) => text.data!)
          .toList();
    }

    Future<void> toggleFavoritesFirst(WidgetTester tester) async {
      await tester.tap(find.byIcon(Icons.sort));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Favorites First'));
      await tester.pumpAndSettle();
      // The switch flips in place rather than closing the dialog.
      expect(find.text('Sort Movies By'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
    }

    testWidgets('is on by default, floating favorites above the rest', (
      tester,
    ) async {
      final repo = await _buildRepo(tester, items);
      await tester.pumpWidget(
        _TestApp(
          catalogRepository: repo,
          categories: categories,
          favoritesService: favorites,
        ),
      );
      await tester.pumpAndSettle();

      expect(gridTitles(tester), [
        'CCCC Unrated',
        'DDDD Third',
        'AAAA Highest',
        'BBBB Mid',
      ]);
    });

    testWidgets('switching it off restores the plain sort order', (
      tester,
    ) async {
      final repo = await _buildRepo(tester, items);
      await tester.pumpWidget(
        _TestApp(
          catalogRepository: repo,
          categories: categories,
          favoritesService: favorites,
        ),
      );
      await tester.pumpAndSettle();

      await toggleFavoritesFirst(tester);

      expect(gridTitles(tester), [
        'AAAA Highest',
        'BBBB Mid',
        'CCCC Unrated',
        'DDDD Third',
      ]);
    });

    testWidgets(
      'applies when the dialog closes, never reloading the grid behind it',
      (tester) async {
        final service = ViewSettingsService();
        await service.setRememberMediaSort(true);
        final repo = await _buildRepo(tester, items);
        await tester.pumpWidget(
          _TestApp(
            catalogRepository: repo,
            categories: categories,
            favoritesService: favorites,
            viewSettingsService: service,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.sort));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Favorites First'));
        await tester.pumpAndSettle();

        // Still open, and the grid behind it is untouched (a reload there
        // rebuilds the autofocus card, which can steal the dialog's focus).
        expect(find.text('Sort Movies By'), findsOneWidget);
        expect(gridTitles(tester), [
          'CCCC Unrated',
          'DDDD Third',
          'AAAA Highest',
          'BBBB Mid',
        ]);
        expect(await service.vodFavoritesFirst(), isTrue);

        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        expect(gridTitles(tester), [
          'AAAA Highest',
          'BBBB Mid',
          'CCCC Unrated',
          'DDDD Third',
        ]);
        expect(await service.vodFavoritesFirst(), isFalse);
      },
    );

    testWidgets('flipping it off and back on before closing changes nothing', (
      tester,
    ) async {
      final memory = <String, Object?>{};
      final service = ViewSettingsService(memory: memory);
      await service.setRememberMediaSort(true);
      final repo = await _buildRepo(tester, items);
      await tester.pumpWidget(
        _TestApp(
          catalogRepository: repo,
          categories: categories,
          favoritesService: favorites,
          viewSettingsService: service,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.sort));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Favorites First'));
      await tester.pump();
      await tester.tap(find.text('Favorites First'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(gridTitles(tester), [
        'CCCC Unrated',
        'DDDD Third',
        'AAAA Highest',
        'BBBB Mid',
      ]);
      expect(
        memory.containsKey(ViewSettingsService.vodFavoritesFirstKey),
        isFalse,
      );
    });

    testWidgets('combines with the chosen sort within each group', (
      tester,
    ) async {
      final repo = await _buildRepo(tester, items);
      await tester.pumpWidget(
        _TestApp(
          catalogRepository: repo,
          categories: categories,
          favoritesService: favorites,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.sort));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Rating'));
      await tester.pumpAndSettle();

      expect(gridTitles(tester), [
        'DDDD Third', // favorite, 8
        'CCCC Unrated', // favorite, unrated
        'AAAA Highest', // 9
        'BBBB Mid', // 7
      ]);
    });

    testWidgets('a newly favorited movie moves up into the favorites group', (
      tester,
    ) async {
      final repo = await _buildRepo(tester, items);
      await tester.pumpWidget(
        _TestApp(
          catalogRepository: repo,
          categories: categories,
          favoritesService: favorites,
        ),
      );
      await tester.pumpAndSettle();

      await tester.longPress(find.text('BBBB Mid'));
      await tester.pumpAndSettle();
      // The toggle -> favorites reload -> window refresh chain hits the
      // repository, which needs a real async turn (see _buildRepo).
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();

      expect(gridTitles(tester), [
        'BBBB Mid',
        'CCCC Unrated',
        'DDDD Third',
        'AAAA Highest',
      ]);
    });

    testWidgets(
      'with rememberMediaSort true, switching it off persists across restart',
      (tester) async {
        final service = ViewSettingsService();
        await service.setRememberMediaSort(true);
        final repo = await _buildRepo(tester, items);
        await tester.pumpWidget(
          _TestApp(
            key: const ValueKey('first'),
            catalogRepository: repo,
            categories: categories,
            favoritesService: favorites,
            viewSettingsService: service,
          ),
        );
        await tester.pumpAndSettle();

        await toggleFavoritesFirst(tester);
        expect(await service.vodFavoritesFirst(), isFalse);
        expect(await service.seriesFavoritesFirst(), isTrue);

        await tester.pumpWidget(
          _TestApp(
            key: const ValueKey('second'),
            catalogRepository: repo,
            categories: categories,
            favoritesService: favorites,
            viewSettingsService: service,
          ),
        );
        await tester.pumpAndSettle();

        expect(gridTitles(tester), [
          'AAAA Highest',
          'BBBB Mid',
          'CCCC Unrated',
          'DDDD Third',
        ]);
      },
    );

    testWidgets(
      'with rememberMediaSort false, switching it off resets to on at restart',
      (tester) async {
        final service = ViewSettingsService();
        final repo = await _buildRepo(tester, items);
        await tester.pumpWidget(
          _TestApp(
            key: const ValueKey('first'),
            catalogRepository: repo,
            categories: categories,
            favoritesService: favorites,
            viewSettingsService: service,
          ),
        );
        await tester.pumpAndSettle();

        await toggleFavoritesFirst(tester);
        expect(await service.vodFavoritesFirst(), isTrue);

        await tester.pumpWidget(
          _TestApp(
            key: const ValueKey('second'),
            catalogRepository: repo,
            categories: categories,
            favoritesService: favorites,
            viewSettingsService: service,
          ),
        );
        await tester.pumpAndSettle();

        expect(gridTitles(tester), [
          'CCCC Unrated',
          'DDDD Third',
          'AAAA Highest',
          'BBBB Mid',
        ]);
      },
    );
  });
}

class _TestApp extends StatelessWidget {
  const _TestApp({
    super.key,
    required this.catalogRepository,
    required this.categories,
    this.isConfigured = true,
    this.useSidebarLayout = true,
    this.onVodSelect,
    this.viewSettingsService,
    this.favoritesService,
  });

  final CatalogRepository catalogRepository;
  final List<Category> categories;
  final bool isConfigured;
  final bool useSidebarLayout;
  final void Function(VodItem)? onVodSelect;
  final ViewSettingsService? viewSettingsService;
  final FavoritesService? favoritesService;

  @override
  Widget build(BuildContext context) {
    final service = viewSettingsService ?? ViewSettingsService();
    return ProviderScope(
      overrides: [
        isBootstrappingProvider.overrideWith((_) => false),
        isConfiguredProvider.overrideWith((_) => isConfigured),
        vodCategoriesProvider.overrideWith((_) => categories),
        viewSettingsServiceProvider.overrideWith((_) => service),
        catalogRepositoryProvider.overrideWith((_) => catalogRepository),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData.dark(useMaterial3: true),
        home: VodScreen(
          useSidebarLayout: useSidebarLayout,
          onVodSelect: onVodSelect ?? (_) {},
          favoritesService: favoritesService,
        ),
      ),
    );
  }
}

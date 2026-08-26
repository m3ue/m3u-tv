import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/vod/vod_screen.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/view_settings_service.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';

void main() {
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
      await tester.pumpWidget(
        _TestApp(vodItems: testVodItems, categories: testCategories),
      );
      await tester.pumpAndSettle();

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

      await tester.pumpWidget(
        _TestApp(vodItems: testVodItems, categories: testCategories),
      );
      await tester.pumpAndSettle();

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

      for (final viewport in [
        const Size(1440, 900),
        const Size(1920, 1080),
        const Size(2560, 1440),
      ]) {
        tester.view.physicalSize = viewport;
        await tester.pumpWidget(
          _TestApp(vodItems: manyMovies, categories: testCategories),
        );
        await tester.pumpAndSettle();

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
      await tester.pumpWidget(
        _TestApp(vodItems: testVodItems, categories: testCategories),
      );
      await tester.pumpAndSettle();

      expect(find.text('All Movies'), findsOneWidget);
      expect(find.text('Action'), findsOneWidget);
      expect(find.text('Drama'), findsOneWidget);
    });

    testWidgets('tapping category tab filters movies', (tester) async {
      await tester.pumpWidget(
        _TestApp(vodItems: testVodItems, categories: testCategories),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Action'));
      await tester.pumpAndSettle();

      // Only Action movies should be visible
      expect(find.text('Big Buck Bunny'), findsOneWidget);
      expect(find.text('Tears of Steel'), findsOneWidget);
    });

    testWidgets('shows loading indicator while fetching', (tester) async {
      await tester.pumpWidget(
        _TestApp(
          vodItems: testVodItems,
          categories: testCategories,
          isLoading: true,
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows not configured message when not connected', (
      tester,
    ) async {
      await tester.pumpWidget(
        _TestApp(
          vodItems: testVodItems,
          categories: testCategories,
          isConfigured: false,
        ),
      );
      await tester.pumpAndSettle();

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

      await tester.pumpWidget(
        _TestApp(vodItems: testVodItems, categories: manyCategories),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Scrollbar), findsWidgets);
    });

    testWidgets('inline search filters movies case-insensitively', (
      tester,
    ) async {
      await tester.pumpWidget(
        _TestApp(vodItems: testVodItems, categories: testCategories),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'sintel');
      await tester.pumpAndSettle();

      expect(find.text('Sintel'), findsOneWidget);
      expect(find.text('Big Buck Bunny'), findsNothing);
      expect(find.text('Tears of Steel'), findsNothing);
    });

    testWidgets('inline search composes with category filter', (tester) async {
      await tester.pumpWidget(
        _TestApp(vodItems: testVodItems, categories: testCategories),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Action'));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.search));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'steel');
      await tester.pumpAndSettle();

      expect(find.text('Tears of Steel'), findsOneWidget);
      expect(find.text('Big Buck Bunny'), findsNothing);
      expect(find.text('Sintel'), findsNothing);
    });

    testWidgets('tapping movie triggers onVodSelect callback', (tester) async {
      VodItem? selectedItem;
      await tester.pumpWidget(
        _TestApp(
          vodItems: testVodItems,
          categories: testCategories,
          onVodSelect: (item) => selectedItem = item,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Big Buck Bunny'));
      await tester.pumpAndSettle();

      expect(selectedItem, isNotNull);
      expect(selectedItem!.id, 1);
    });

    testWidgets('shows rating when available', (tester) async {
      await tester.pumpWidget(
        _TestApp(vodItems: testVodItems, categories: testCategories),
      );
      await tester.pumpAndSettle();

      expect(find.text('★ 4.5'), findsOneWidget);
    });

    testWidgets(
      'mobile layout shows a Filter button instead of category chips, '
      'and selecting a category filters the grid',
      (tester) async {
        await tester.pumpWidget(
          _TestApp(
            vodItems: testVodItems,
            categories: testCategories,
            useSidebarLayout: false,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Filter'), findsOneWidget);
        expect(find.text('Action'), findsNothing);

        await tester.tap(find.text('Filter'));
        await tester.pumpAndSettle();

        expect(find.text('Action'), findsOneWidget);
        await tester.tap(find.text('Action'));
        await tester.pumpAndSettle();

        expect(find.text('Big Buck Bunny'), findsOneWidget);
        expect(find.text('Sintel'), findsNothing);
      },
    );
  });

  // ---------------------------------------------------------------------
  // #235 VOD category sort (long-press affordance + persistence behavior)
  //
  // All four items are in the same category so the category filter is a
  // no-op and any reorder is purely the sort step. The default (server)
  // order is AAAA → BBBB → CCCC → DDDD; ratingDesc produces
  // AAAA → DDDD → BBBB → CCCC (unrated sinks last).
  // ---------------------------------------------------------------------
  group('VodScreen VOD sort by long-press', () {
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
      sortCategories = const [Category(id: '20', name: 'Action')];
    });

    // Reads the four movie titles in document (widget-tree) order. The
    // grid renders them left-to-right, top-to-bottom; `find.byType(Text)`
    // returns matches in tree order, which is the same source order the
    // items were built in by `_filteredItems`.
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
      'long-press on a category chip opens the sort menu with Default, Rating, Cancel',
      (tester) async {
        await tester.pumpWidget(
          _TestApp(
            vodItems: sortItems,
            categories: sortCategories,
          ),
        );
        await tester.pumpAndSettle();

        // Trigger the long-press via the chip's underlying InkWell long-press.
        await tester.longPress(find.text('All Movies'));
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
        await tester.pumpWidget(
          _TestApp(
            vodItems: sortItems,
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

        await tester.longPress(find.text('All Movies'));
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
        await tester.pumpWidget(
          _TestApp(
            vodItems: sortItems,
            categories: sortCategories,
          ),
        );
        await tester.pumpAndSettle();

        // Apply Rating first so we have something to revert.
        await tester.longPress(find.text('All Movies'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Rating'));
        await tester.pumpAndSettle();

        // Now switch back to Default.
        await tester.longPress(find.text('All Movies'));
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
        await tester.pumpWidget(
          _TestApp(
            vodItems: sortItems,
            categories: sortCategories,
          ),
        );
        await tester.pumpAndSettle();

        // Switch to Rating first so Default is NOT active.
        await tester.longPress(find.text('All Movies'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Rating'));
        await tester.pumpAndSettle();

        // Re-open the dialog — Rating should now be the active row.
        await tester.longPress(find.text('All Movies'));
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
      'with rememberVodSort false (default), restart does not restore Rating sort',
      (tester) async {
        final service = ViewSettingsService();
        // Distinct Keys between pumps force Flutter to recreate the
        // Element/State subtree - otherwise pumpWidget reuses the State
        // because the widget types match, and `_loadSortPreference`'s
        // initState path never runs again.
        const firstKey = ValueKey('restart-first');
        const secondKey = ValueKey('restart-second');
        await tester.pumpWidget(
          _TestApp(
            key: firstKey,
            vodItems: sortItems,
            categories: sortCategories,
            viewSettingsService: service,
          ),
        );
        await tester.pumpAndSettle();

        // Apply Rating once.
        await tester.longPress(find.text('All Movies'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Rating'));
        await tester.pumpAndSettle();

        // Per the plan, the service is only written when
        // `rememberVodSort` is true — session-only choices deliberately
        // leave the on-disk value at the conservative default.
        expect(await service.vodSortOption(), VodSortOption.defaultOrder);
        expect(await service.rememberVodSort(), isFalse);

        // Re-mount from scratch with the same persistent service. The new
        // _VodScreenState starts with `_sortOption = defaultOrder` and the
        // remember=false guard skips the persisted vodSortOption read.
        await tester.pumpWidget(
          _TestApp(
            key: secondKey,
            vodItems: sortItems,
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
      'with rememberVodSort true, the persisted Rating sort is restored on restart',
      (tester) async {
        final service = ViewSettingsService();
        await service.setRememberVodSort(true);
        await service.setVodSortOption(VodSortOption.ratingDesc);

        await tester.pumpWidget(
          _TestApp(
            vodItems: sortItems,
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
      'mobile (stacked) layout does not expose the long-press sort affordance',
      (tester) async {
        await tester.pumpWidget(
          _TestApp(
            vodItems: sortItems,
            categories: sortCategories,
            useSidebarLayout: false,
          ),
        );
        await tester.pumpAndSettle();

        // Mobile has a "Filter" button rather than chips in the strip.
        // Long-pressing it should not open the sort dialog — the only
        // existing behavior is the Filter screen push.
        await tester.longPress(find.text('Filter'));
        await tester.pumpAndSettle();

        expect(find.text('Sort Movies By'), findsNothing);
      },
    );
  });
}

class _TestApp extends StatelessWidget {
  const _TestApp({
    super.key,
    required this.vodItems,
    required this.categories,
    this.isLoading = false,
    this.isConfigured = true,
    this.useSidebarLayout = true,
    this.onVodSelect,
    this.viewSettingsService,
  });

  final List<VodItem> vodItems;
  final List<Category> categories;
  final bool isLoading;
  final bool isConfigured;
  final bool useSidebarLayout;
  final void Function(VodItem)? onVodSelect;
  final ViewSettingsService? viewSettingsService;

  @override
  Widget build(BuildContext context) {
    final service = viewSettingsService ?? ViewSettingsService();
    return ProviderScope(
      overrides: [
        isBootstrappingProvider.overrideWith((_) => false),
        isConfiguredProvider.overrideWith((_) => isConfigured),
        isLoadingContentProvider.overrideWith((_) => isLoading),
        vodItemsProvider.overrideWith((_) => vodItems),
        vodCategoriesProvider.overrideWith((_) => categories),
        viewSettingsServiceProvider.overrideWith((_) => service),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData.dark(useMaterial3: true),
        home: VodScreen(
          useSidebarLayout: useSidebarLayout,
          onVodSelect: onVodSelect ?? (_) {},
        ),
      ),
    );
  }
}

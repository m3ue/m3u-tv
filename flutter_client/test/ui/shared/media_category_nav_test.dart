import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';
import 'package:m3u_tv/shared/media_category_nav.dart';

void main() {
  final tabs = [
    const CategoryTabData(id: '', name: 'All'),
    const CategoryTabData(id: '20', name: 'Action'),
    const CategoryTabData(id: '21', name: 'Drama'),
  ];

  Widget buildNav({
    required bool useSidebarLayout,
    List<CategoryTabData>? tabsOverride,
    Map<String, int>? categoryCounts,
    String selectedId = '',
    ValueChanged<String>? onSelected,
  }) {
    return MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(
        body: MediaCategoryNav(
          useSidebarLayout: useSidebarLayout,
          query: '',
          onQueryChanged: (_) {},
          searchHint: 'Search...',
          tabs: tabsOverride ?? tabs,
          selectedId: selectedId,
          onSelected: onSelected ?? (_) {},
          filterButtonLabel: 'Filter',
          filterScreenTitle: 'Categories',
          categoryCounts: categoryCounts,
        ),
      ),
    );
  }

  group('MediaCategoryNav sidebar layout', () {
    testWidgets('renders search field and vertical category list', (
      tester,
    ) async {
      await tester.pumpWidget(buildNav(useSidebarLayout: true));
      await tester.pumpAndSettle();

      // The sidebar strip's search field is click-to-activate (see
      // InlineMediaSearchField.activateOnSelect) — it shows as a
      // DpadInkWell button, not a live TextField, until Select is pressed.
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Search...'), findsOneWidget);
      expect(find.byType(VerticalCategoryList), findsOneWidget);
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Action'), findsOneWidget);
      expect(find.text('Drama'), findsOneWidget);
      expect(find.text('Filter'), findsNothing);
    });

    testWidgets('tapping a category chip calls onSelected', (tester) async {
      String? selected;
      await tester.pumpWidget(
        buildNav(useSidebarLayout: true, onSelected: (id) => selected = id),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Action'));
      await tester.pumpAndSettle();

      expect(selected, '20');
    });

    testWidgets('renders leading and trailing slots', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: Scaffold(
            body: MediaCategoryNav(
              useSidebarLayout: true,
              query: '',
              onQueryChanged: (_) {},
              searchHint: 'Search...',
              tabs: tabs,
              selectedId: '',
              onSelected: (_) {},
              filterButtonLabel: 'Filter',
              filterScreenTitle: 'Categories',
              leading: const Icon(Icons.grid_view),
              trailing: const Text('Multiview'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.grid_view), findsOneWidget);
      expect(find.text('Multiview'), findsOneWidget);
    });

    testWidgets('hides category list when tabs is empty', (tester) async {
      await tester.pumpWidget(
        buildNav(useSidebarLayout: true, tabsOverride: const []),
      );
      await tester.pumpAndSettle();

      expect(find.byType(VerticalCategoryList), findsNothing);
    });
  });

  group('MediaCategoryNav stacked layout', () {
    testWidgets('renders search field and Filter button instead of chips', (
      tester,
    ) async {
      await tester.pumpWidget(buildNav(useSidebarLayout: false));
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Filter'), findsOneWidget);
      expect(find.text('Action'), findsNothing);
    });

    testWidgets('hides Filter button when tabs is empty', (tester) async {
      await tester.pumpWidget(
        buildNav(useSidebarLayout: false, tabsOverride: const []),
      );
      await tester.pumpAndSettle();

      expect(find.text('Filter'), findsNothing);
    });

    testWidgets(
      'tapping Filter pushes MediaCategoryFilterScreen and applies selection',
      (tester) async {
        String? selected;
        await tester.pumpWidget(
          buildNav(useSidebarLayout: false, onSelected: (id) => selected = id),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('Filter'));
        await tester.pumpAndSettle();

        expect(find.byType(MediaCategoryFilterScreen), findsOneWidget);
        expect(find.text('Categories'), findsOneWidget);
        expect(find.text('Action'), findsOneWidget);

        await tester.tap(find.text('Action'));
        await tester.pumpAndSettle();

        expect(find.byType(MediaCategoryFilterScreen), findsNothing);
        expect(selected, '20');
      },
    );
  });

  group('MediaCategoryFilterScreen', () {
    testWidgets('shows all tab names and counts, marks selection', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: MediaCategoryFilterScreen(
            title: 'Categories',
            tabs: tabs,
            selectedId: '20',
            counts: const {'': 3, '20': 2, '21': 1},
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('All'), findsOneWidget);
      expect(find.text('Action'), findsOneWidget);
      expect(find.text('Drama'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);

      final actionTile = tester.widget<ListTile>(
        find.ancestor(
          of: find.text('Action'),
          matching: find.byType(ListTile),
        ),
      );
      expect(actionTile.selected, isTrue);
    });
  });
}

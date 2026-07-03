import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/vod/vod_screen.dart';
import 'package:m3u_tv/services/domain_models.dart';
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
  });
}

class _TestApp extends StatelessWidget {
  const _TestApp({
    required this.vodItems,
    required this.categories,
    this.isLoading = false,
    this.isConfigured = true,
    this.onVodSelect,
  });

  final List<VodItem> vodItems;
  final List<Category> categories;
  final bool isLoading;
  final bool isConfigured;
  final void Function(VodItem)? onVodSelect;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: VodScreen(
        vodItems: vodItems,
        categories: categories,
        isLoading: isLoading,
        isConfigured: isConfigured,
        onVodSelect: onVodSelect ?? (_) {},
      ),
    );
  }
}

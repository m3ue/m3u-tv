import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/series/series_screen.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';

void main() {
  group('SeriesScreen', () {
    late List<Series> testSeriesList;
    late List<Category> testCategories;

    setUp(() {
      testSeriesList = [
        const Series(
          id: 1,
          name: 'Breaking Bad',
          coverUrl: 'http://example.com/bb.jpg',
          categoryId: '30',
          rating: 4.8,
        ),
        const Series(
          id: 2,
          name: 'Stranger Things',
          coverUrl: 'http://example.com/st.jpg',
          categoryId: '31',
          rating: 4.2,
        ),
      ];
      testCategories = [
        const Category(id: '30', name: 'Thriller'),
        const Category(id: '31', name: 'Sci-Fi'),
      ];
    });

    testWidgets('renders series grid with names', (tester) async {
      await tester.pumpWidget(
        _TestApp(seriesList: testSeriesList, categories: testCategories),
      );
      await tester.pumpAndSettle();

      expect(find.text('Breaking Bad'), findsOneWidget);
      expect(find.text('Stranger Things'), findsOneWidget);
    });

    testWidgets('renders All Series and category tabs', (tester) async {
      await tester.pumpWidget(
        _TestApp(seriesList: testSeriesList, categories: testCategories),
      );
      await tester.pumpAndSettle();

      expect(find.text('All Series'), findsOneWidget);
      expect(find.text('Thriller'), findsOneWidget);
      expect(find.text('Sci-Fi'), findsOneWidget);
    });

    testWidgets('large desktop grids keep series cards comfortably sized', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final manySeries = List<Series>.generate(
        40,
        (index) => Series(
          id: index,
          name: 'Desktop Series $index',
          coverUrl: 'http://example.com/$index.jpg',
          categoryId: '30',
        ),
      );

      for (final viewport in [
        const Size(1440, 900),
        const Size(1920, 1080),
        const Size(2560, 1440),
      ]) {
        tester.view.physicalSize = viewport;
        await tester.pumpWidget(
          _TestApp(seriesList: manySeries, categories: testCategories),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        final firstSeriesCard = find.ancestor(
          of: find.text('Desktop Series 0'),
          matching: find.byType(DpadInkWell),
        );
        expect(firstSeriesCard, findsOneWidget);
        expect(tester.getSize(firstSeriesCard).width, lessThanOrEqualTo(220));
      }
    });

    testWidgets('tapping category tab filters series', (tester) async {
      await tester.pumpWidget(
        _TestApp(seriesList: testSeriesList, categories: testCategories),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Thriller'));
      await tester.pumpAndSettle();

      expect(find.text('Breaking Bad'), findsOneWidget);
    });

    testWidgets('shows loading indicator while fetching', (tester) async {
      await tester.pumpWidget(
        _TestApp(
          seriesList: testSeriesList,
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
          seriesList: testSeriesList,
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

    testWidgets('category bar and series grid expose scrollbars', (
      tester,
    ) async {
      final manyCategories = List<Category>.generate(
        16,
        (index) => Category(id: '$index', name: 'Category $index'),
      );

      await tester.pumpWidget(
        _TestApp(seriesList: testSeriesList, categories: manyCategories),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Scrollbar), findsWidgets);
    });

    testWidgets('inline search filters series case-insensitively', (
      tester,
    ) async {
      await tester.pumpWidget(
        _TestApp(seriesList: testSeriesList, categories: testCategories),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'stranger');
      await tester.pumpAndSettle();

      expect(find.text('Stranger Things'), findsOneWidget);
      expect(find.text('Breaking Bad'), findsNothing);
    });

    testWidgets('inline search composes with category filter', (tester) async {
      await tester.pumpWidget(
        _TestApp(seriesList: testSeriesList, categories: testCategories),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Thriller'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'bad');
      await tester.pumpAndSettle();

      expect(find.text('Breaking Bad'), findsOneWidget);
      expect(find.text('Stranger Things'), findsNothing);
    });

    testWidgets('tapping series triggers onSeriesSelect callback', (
      tester,
    ) async {
      Series? selectedSeries;
      await tester.pumpWidget(
        _TestApp(
          seriesList: testSeriesList,
          categories: testCategories,
          onSeriesSelect: (series) => selectedSeries = series,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Breaking Bad'));
      await tester.pumpAndSettle();

      expect(selectedSeries, isNotNull);
      expect(selectedSeries!.id, 1);
    });

    testWidgets('shows rating when available', (tester) async {
      await tester.pumpWidget(
        _TestApp(seriesList: testSeriesList, categories: testCategories),
      );
      await tester.pumpAndSettle();

      expect(find.text('★ 4.8'), findsOneWidget);
    });
  });
}

class _TestApp extends StatelessWidget {
  const _TestApp({
    required this.seriesList,
    required this.categories,
    this.isLoading = false,
    this.isConfigured = true,
    this.onSeriesSelect,
  });

  final List<Series> seriesList;
  final List<Category> categories;
  final bool isLoading;
  final bool isConfigured;
  final void Function(Series)? onSeriesSelect;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: SeriesScreen(
        seriesList: seriesList,
        categories: categories,
        isLoading: isLoading,
        isConfigured: isConfigured,
        onSeriesSelect: onSeriesSelect ?? (_) {},
      ),
    );
  }
}

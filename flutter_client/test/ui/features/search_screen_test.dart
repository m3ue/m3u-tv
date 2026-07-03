import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/search/search_screen.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/shared/dpad_tab_bar.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';

void main() {
  group('SearchScreen', () {
    late List<Channel> testChannels;
    late List<VodItem> testVodItems;
    late List<Series> testSeriesList;

    setUp(() {
      testChannels = [
        const Channel(
          id: 1,
          name: 'BBC News',
          streamUrl: 'http://example.com/1.m3u8',
          logoUrl: 'http://example.com/bbc.png',
          categoryId: '10',
        ),
        const Channel(
          id: 2,
          name: 'CNN International',
          streamUrl: 'http://example.com/2.m3u8',
          categoryId: '11',
        ),
      ];
      testVodItems = [
        const VodItem(
          id: 10,
          name: 'The Matrix',
          streamUrl: 'http://example.com/10.mp4',
          containerExtension: 'mp4',
          logoUrl: 'http://example.com/matrix.jpg',
          categoryId: '20',
        ),
        const VodItem(
          id: 11,
          name: 'Matrix Reloaded',
          streamUrl: 'http://example.com/11.mp4',
          containerExtension: 'mp4',
          categoryId: '20',
        ),
      ];
      testSeriesList = [
        const Series(
          id: 20,
          name: 'Breaking Bad',
          coverUrl: 'http://example.com/breaking-bad.jpg',
          categoryId: '30',
        ),
        const Series(id: 21, name: 'Bad Sisters', categoryId: '31'),
      ];
    });

    testWidgets('renders search field', (tester) async {
      await tester.pumpWidget(
        _TestApp(
          channels: testChannels,
          vodItems: testVodItems,
          seriesList: testSeriesList,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TextField), findsOneWidget);
    });

    testWidgets('renders All/Live TV/Movies/Series tabs', (tester) async {
      await tester.pumpWidget(
        _TestApp(
          channels: testChannels,
          vodItems: testVodItems,
          seriesList: testSeriesList,
        ),
      );
      await tester.pumpAndSettle();

      // Tab bar should have all four tabs
      expect(find.byType(DpadTabBar), findsOneWidget);
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Live TV'), findsOneWidget);
      expect(find.text('Movies'), findsOneWidget);
      expect(find.text('Series'), findsOneWidget);
    });

    testWidgets('shows prompt instead of immediate results before query', (
      tester,
    ) async {
      await tester.pumpWidget(
        _TestApp(
          channels: testChannels,
          vodItems: testVodItems,
          seriesList: testSeriesList,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Type to search'), findsOneWidget);
      expect(find.text('BBC News'), findsNothing);
      expect(find.text('The Matrix'), findsNothing);
      expect(find.text('Breaking Bad'), findsNothing);
    });

    testWidgets('searching filters results case-insensitively', (tester) async {
      await tester.pumpWidget(
        _TestApp(
          channels: testChannels,
          vodItems: testVodItems,
          seriesList: testSeriesList,
        ),
      );
      await tester.pumpAndSettle();

      // Type search query
      await tester.enterText(find.byType(TextField), 'matrix');
      await tester.pumpAndSettle();

      expect(find.text('The Matrix'), findsOneWidget);
      expect(find.text('Matrix Reloaded'), findsOneWidget);
      // BBC News and CNN should not appear in All results
      expect(find.text('BBC News'), findsNothing);
    });

    testWidgets('Live TV tab shows only channels', (tester) async {
      await tester.pumpWidget(
        _TestApp(
          channels: testChannels,
          vodItems: testVodItems,
          seriesList: testSeriesList,
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'news');
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.byType(DpadTabBar),
          matching: find.text('Live TV'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('BBC News'), findsOneWidget);
      expect(find.text('The Matrix'), findsNothing);
    });

    testWidgets('Movies tab shows only VOD items', (tester) async {
      await tester.pumpWidget(
        _TestApp(
          channels: testChannels,
          vodItems: testVodItems,
          seriesList: testSeriesList,
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'matrix');
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.byType(DpadTabBar),
          matching: find.text('Movies'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('The Matrix'), findsOneWidget);
      expect(find.text('Matrix Reloaded'), findsOneWidget);
      expect(find.text('BBC News'), findsNothing);
    });

    testWidgets('Series tab shows only series', (tester) async {
      await tester.pumpWidget(
        _TestApp(
          channels: testChannels,
          vodItems: testVodItems,
          seriesList: testSeriesList,
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'bad');
      await tester.pumpAndSettle();

      await tester.tap(
        find.descendant(
          of: find.byType(DpadTabBar),
          matching: find.text('Series'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Breaking Bad'), findsOneWidget);
      expect(find.text('Bad Sisters'), findsOneWidget);
      expect(find.text('BBC News'), findsNothing);
    });

    testWidgets('search result images use resilient media widgets', (
      tester,
    ) async {
      await tester.pumpWidget(
        _TestApp(
          channels: testChannels,
          vodItems: testVodItems,
          seriesList: testSeriesList,
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'matrix');
      await tester.pumpAndSettle();

      expect(find.byType(CircleAvatar), findsNothing);
      expect(find.byType(ResilientMediaImage), findsWidgets);
    });

    testWidgets('result taps dispatch shared media selection handlers', (
      tester,
    ) async {
      Channel? selectedChannel;
      VodItem? selectedVod;
      Series? selectedSeries;

      await tester.pumpWidget(
        _TestApp(
          channels: testChannels,
          vodItems: testVodItems,
          seriesList: testSeriesList,
          onChannelSelect: (channel) => selectedChannel = channel,
          onVodSelect: (item) => selectedVod = item,
          onSeriesSelect: (series) => selectedSeries = series,
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'bbc');
      await tester.pumpAndSettle();
      await tester.tap(find.text('BBC News'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'matrix');
      await tester.pumpAndSettle();
      await tester.tap(find.text('The Matrix'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'bad');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Breaking Bad'));
      await tester.pumpAndSettle();

      expect(selectedChannel?.id, 1);
      expect(selectedVod?.id, 10);
      expect(selectedSeries?.id, 20);
    });

    testWidgets('shows empty state when no results match', (tester) async {
      await tester.pumpWidget(
        _TestApp(
          channels: testChannels,
          vodItems: testVodItems,
          seriesList: testSeriesList,
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'xyznonexistent');
      await tester.pumpAndSettle();

      expect(find.text('No results found'), findsOneWidget);
    });

    testWidgets('shows not configured message when not connected', (
      tester,
    ) async {
      await tester.pumpWidget(
        _TestApp(
          channels: testChannels,
          vodItems: testVodItems,
          seriesList: testSeriesList,
          isConfigured: false,
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.text('Please connect to your service in Settings'),
        findsOneWidget,
      );
    });
  });
}

class _TestApp extends StatelessWidget {
  const _TestApp({
    required this.channels,
    required this.vodItems,
    required this.seriesList,
    this.isConfigured = true,
    this.onChannelSelect,
    this.onVodSelect,
    this.onSeriesSelect,
  });

  final List<Channel> channels;
  final List<VodItem> vodItems;
  final List<Series> seriesList;
  final bool isConfigured;
  final void Function(Channel)? onChannelSelect;
  final void Function(VodItem)? onVodSelect;
  final void Function(Series)? onSeriesSelect;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: SearchScreen(
        channels: channels,
        vodItems: vodItems,
        seriesList: seriesList,
        isConfigured: isConfigured,
        onChannelSelect: onChannelSelect ?? (_) {},
        onVodSelect: onVodSelect ?? (_) {},
        onSeriesSelect: onSeriesSelect ?? (_) {},
      ),
    );
  }
}

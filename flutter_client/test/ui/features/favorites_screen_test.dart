import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/favorites/favorites_screen.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/favorites_service.dart';

void main() {
  group('FavoritesScreen', () {
    late List<Channel> testChannels;
    late List<VodItem> testVodItems;
    late List<Series> testSeriesList;

    setUp(() {
      testChannels = [
        const Channel(
          id: 1,
          name: 'BBC One',
          streamUrl: 'http://example.com/1.m3u8',
        ),
        const Channel(
          id: 2,
          name: 'CNN',
          streamUrl: 'http://example.com/2.m3u8',
        ),
      ];
      testVodItems = [
        const VodItem(
          id: 10,
          name: 'The Matrix',
          streamUrl: 'http://example.com/10.mp4',
          containerExtension: 'mp4',
        ),
      ];
      testSeriesList = [
        const Series(id: 20, name: 'Breaking Bad'),
      ];
    });

    testWidgets('renders favorites screen with tabs', (tester) async {
      final favoritesService = FavoritesService();
      await favoritesService.add(1);

      final favIds = await favoritesService.all();

      await tester.pumpWidget(
        _TestApp(
          channels: testChannels,
          vodItems: testVodItems,
          seriesList: testSeriesList,
          favoriteChannelIds: favIds,
          favoritesService: favoritesService,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Live TV'), findsOneWidget);
      expect(find.text('Movies'), findsOneWidget);
      expect(find.text('Series'), findsOneWidget);
    });

    testWidgets('shows favorited live channels in Live TV tab', (tester) async {
      final favoritesService = FavoritesService();
      await favoritesService.add(1); // BBC One

      final favIds = await favoritesService.all();

      await tester.pumpWidget(
        _TestApp(
          channels: testChannels,
          vodItems: testVodItems,
          seriesList: testSeriesList,
          favoriteChannelIds: favIds,
          favoritesService: favoritesService,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('BBC One'), findsOneWidget);
    });

    testWidgets('shows favorited VOD items in Movies tab', (tester) async {
      final favoritesService = FavoritesService();

      await tester.pumpWidget(
        _TestApp(
          channels: testChannels,
          vodItems: testVodItems,
          seriesList: testSeriesList,
          favoriteVodIds: const {10},
          favoritesService: favoritesService,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Movies'));
      await tester.pumpAndSettle();

      expect(find.text('The Matrix'), findsOneWidget);
    });

    testWidgets('shows favorited series in Series tab', (tester) async {
      final favoritesService = FavoritesService();

      await tester.pumpWidget(
        _TestApp(
          channels: testChannels,
          vodItems: testVodItems,
          seriesList: testSeriesList,
          favoriteSeriesIds: const {20},
          favoritesService: favoritesService,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Series'));
      await tester.pumpAndSettle();

      expect(find.text('Breaking Bad'), findsOneWidget);
    });

    testWidgets('shows empty state when no favorites', (tester) async {
      await tester.pumpWidget(
        _TestApp(
          channels: testChannels,
          vodItems: testVodItems,
          seriesList: testSeriesList,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('No favorites yet'), findsOneWidget);
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
    this.favoriteChannelIds = const {},
    this.favoriteVodIds = const {},
    this.favoriteSeriesIds = const {},
    this.favoritesService,
    this.isConfigured = true,
  });

  final List<Channel> channels;
  final List<VodItem> vodItems;
  final List<Series> seriesList;
  final Set<int> favoriteChannelIds;
  final Set<int> favoriteVodIds;
  final Set<int> favoriteSeriesIds;
  final FavoritesService? favoritesService;
  final bool isConfigured;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: FavoritesScreen(
        channels: channels,
        vodItems: vodItems,
        seriesList: seriesList,
        favoriteChannelIds: favoriteChannelIds,
        favoriteVodIds: favoriteVodIds,
        favoriteSeriesIds: favoriteSeriesIds,
        isConfigured: isConfigured,
        favoritesService: favoritesService ?? FavoritesService(),
        onChannelSelect: (_) {},
        onVodSelect: (_) {},
        onSeriesSelect: (_) {},
      ),
    );
  }
}

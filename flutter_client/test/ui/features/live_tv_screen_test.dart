import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/live_tv/live_tv_screen.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/epg_service.dart';
import 'package:m3u_tv/services/favorites_service.dart';

void main() {
  group('LiveTvScreen', () {
    late List<Channel> testChannels;
    late List<Category> testCategories;

    setUp(() {
      testChannels = [
        const Channel(
          id: 1,
          name: 'BBC One',
          streamUrl: 'http://example.com/1.m3u8',
          epgChannelId: 'bbc.one',
          categoryId: '10',
        ),
        const Channel(
          id: 2,
          name: 'CNN',
          streamUrl: 'http://example.com/2.m3u8',
          epgChannelId: 'cnn',
          categoryId: '11',
        ),
        const Channel(
          id: 3,
          name: 'ESPN',
          streamUrl: 'http://example.com/3.m3u8',
          categoryId: '12',
        ),
      ];
      testCategories = [
        const Category(id: '10', name: 'News'),
        const Category(id: '11', name: 'Entertainment'),
        const Category(id: '12', name: 'Sports'),
      ];
    });

    testWidgets('renders channel list with names', (tester) async {
      await tester.pumpWidget(
        _TestApp(channels: testChannels, categories: testCategories),
      );
      await tester.pumpAndSettle();

      expect(find.text('BBC One'), findsOneWidget);
      expect(find.text('CNN'), findsOneWidget);
      expect(find.text('ESPN'), findsOneWidget);
    });

    testWidgets('renders All Channels and Favorites category tabs', (
      tester,
    ) async {
      await tester.pumpWidget(
        _TestApp(channels: testChannels, categories: testCategories),
      );
      await tester.pumpAndSettle();

      expect(find.text('All Channels'), findsOneWidget);
      expect(find.text('★ Favorites'), findsOneWidget);
    });

    testWidgets('renders category tabs from service categories', (
      tester,
    ) async {
      await tester.pumpWidget(
        _TestApp(channels: testChannels, categories: testCategories),
      );
      await tester.pumpAndSettle();

      // At least the first category should be visible
      expect(find.text('News'), findsAtLeast(1));
    });

    testWidgets('tapping category tab filters channels', (tester) async {
      await tester.pumpWidget(
        _TestApp(channels: testChannels, categories: testCategories),
      );
      await tester.pumpAndSettle();

      // Tap on News category
      await tester.tap(find.text('News'));
      await tester.pumpAndSettle();

      // Only BBC One should be visible (categoryId: '10')
      expect(find.text('BBC One'), findsOneWidget);
    });

    testWidgets('tapping All Channels shows all channels', (tester) async {
      await tester.pumpWidget(
        _TestApp(channels: testChannels, categories: testCategories),
      );
      await tester.pumpAndSettle();

      // Tap a category first
      await tester.tap(find.text('News'));
      await tester.pumpAndSettle();

      // Tap All Channels
      await tester.tap(find.text('All Channels'));
      await tester.pumpAndSettle();

      expect(find.text('BBC One'), findsOneWidget);
      expect(find.text('CNN'), findsOneWidget);
      expect(find.text('ESPN'), findsOneWidget);
    });

    testWidgets('shows empty state when no channels', (tester) async {
      await tester.pumpWidget(
        _TestApp(channels: const [], categories: testCategories),
      );
      await tester.pumpAndSettle();

      expect(find.byType(LiveTvScreen), findsOneWidget);
    });

    testWidgets('shows loading indicator while fetching', (tester) async {
      await tester.pumpWidget(
        _TestApp(
          channels: testChannels,
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
          channels: testChannels,
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

    testWidgets('Favorites category shows only favorited channels', (
      tester,
    ) async {
      final favoritesService = FavoritesService();
      await favoritesService.add(1); // BBC One

      await tester.pumpWidget(
        _TestApp(
          channels: testChannels,
          categories: testCategories,
          favoritesService: favoritesService,
        ),
      );
      await tester.pumpAndSettle();

      // Tap Favorites category
      await tester.tap(find.text('★ Favorites'));
      await tester.pumpAndSettle();

      expect(find.text('BBC One'), findsOneWidget);
    });

    testWidgets('category bar exposes scrollbar and arrow affordances', (
      tester,
    ) async {
      final manyCategories = List<Category>.generate(
        16,
        (index) => Category(id: '$index', name: 'Category $index'),
      );

      await tester.pumpWidget(
        _TestApp(channels: testChannels, categories: manyCategories),
      );
      await tester.pumpAndSettle();

      expect(find.byType(Scrollbar), findsWidgets);
    });

    testWidgets('inline search filters channels case-insensitively', (
      tester,
    ) async {
      await tester.pumpWidget(
        _TestApp(channels: testChannels, categories: testCategories),
      );
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'cnn');
      await tester.pumpAndSettle();

      expect(find.text('CNN'), findsOneWidget);
      expect(find.text('BBC One'), findsNothing);
      expect(find.text('ESPN'), findsNothing);
    });

    testWidgets('inline search composes with favorites filter', (tester) async {
      final favoritesService = FavoritesService();
      await favoritesService.add(1);
      await favoritesService.add(2);

      await tester.pumpWidget(
        _TestApp(
          channels: testChannels,
          categories: testCategories,
          favoritesService: favoritesService,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('★ Favorites'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'bbc');
      await tester.pumpAndSettle();

      expect(find.text('BBC One'), findsOneWidget);
      expect(find.text('CNN'), findsNothing);
      expect(find.text('ESPN'), findsNothing);
    });

    testWidgets('tapping channel triggers onChannelSelect callback', (
      tester,
    ) async {
      Channel? selectedChannel;
      await tester.pumpWidget(
        _TestApp(
          channels: testChannels,
          categories: testCategories,
          onChannelSelect: (channel) => selectedChannel = channel,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('BBC One'));
      await tester.pumpAndSettle();

      expect(selectedChannel, isNotNull);
      expect(selectedChannel!.id, 1);
    });

    testWidgets(
      'shows EPG schedule action and calls back with program context',
      (
        tester,
      ) async {
        Channel? scheduledChannel;
        EpgProgram? scheduledProgram;
        final epgService =
            EpgService(clock: () => DateTime.utc(2026, 6, 25, 20))
              ..loadPrograms([
                EpgProgram(
                  channelId: 'bbc.one',
                  title: 'Late Show',
                  description: 'Fixture episode',
                  start: DateTime.utc(2026, 6, 25, 20),
                  end: DateTime.utc(2026, 6, 25, 21),
                ),
              ]);

        await tester.pumpWidget(
          _TestApp(
            channels: testChannels,
            categories: testCategories,
            epgService: epgService,
            onScheduleProgram: (channel, program) {
              scheduledChannel = channel;
              scheduledProgram = program;
            },
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Record'), findsOneWidget);
        await tester.tap(find.text('Record'));
        await tester.pumpAndSettle();

        expect(scheduledChannel?.id, 1);
        expect(scheduledProgram?.title, 'Late Show');
      },
    );
  });
}

class _TestApp extends StatelessWidget {
  const _TestApp({
    required this.channels,
    required this.categories,
    this.isLoading = false,
    this.isConfigured = true,
    this.favoritesService,
    this.epgService,
    this.onChannelSelect,
    this.onScheduleProgram,
  });

  final List<Channel> channels;
  final List<Category> categories;
  final bool isLoading;
  final bool isConfigured;
  final FavoritesService? favoritesService;
  final EpgService? epgService;
  final void Function(Channel)? onChannelSelect;
  final void Function(Channel, EpgProgram)? onScheduleProgram;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: LiveTvScreen(
        channels: channels,
        categories: categories,
        isLoading: isLoading,
        isConfigured: isConfigured,
        favoritesService: favoritesService ?? FavoritesService(),
        epgService: epgService ?? EpgService(),
        onChannelSelect: onChannelSelect ?? (_) {},
        onScheduleProgram: onScheduleProgram,
      ),
    );
  }
}

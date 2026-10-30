import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/live_tv/live_tv_screen.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:m3u_tv/services/catalog_db/catalog_codec.dart';
import 'package:m3u_tv/services/catalog_db/catalog_database.dart';
import 'package:m3u_tv/services/catalog_db/catalog_repository.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/epg_service.dart';
import 'package:m3u_tv/services/favorites_service.dart';
import 'package:m3u_tv/services/view_settings_service.dart';
import 'package:m3u_tv/shared/channel_context.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';

/// Live TV paging its channels from the SQLite catalog
/// (`windowedLiveTvProvider`). Drift's real I/O needs a real async turn, so
/// every step that queries the catalog settles through [settle].

/// Provider order differs from every sort under test.
const _channels = [
  Channel(
    id: 4,
    name: 'ESPN 10',
    streamUrl: 'http://example.com/4',
    categoryId: '10',
  ),
  Channel(
    id: 2,
    name: 'CNN',
    streamUrl: 'http://example.com/2',
    categoryId: '11',
    channelNumber: 1,
  ),
  Channel(
    id: 1,
    name: 'BBC One',
    streamUrl: 'http://example.com/1',
    categoryId: '10',
    channelNumber: 3,
  ),
  Channel(
    id: 3,
    name: 'ESPN 2',
    streamUrl: 'http://example.com/3',
    categoryId: '10',
    channelNumber: 2,
  ),
];

const _categories = [
  Category(id: '10', name: 'Sports & UK'),
  Category(id: '11', name: 'News'),
];

Future<CatalogRepository> _buildRepo(WidgetTester tester) async {
  final repo = await tester.runAsync(() async {
    final db = CatalogDatabase.memory();
    addTearDown(db.close);
    final repo = CatalogRepository(db);
    await repo.replaceItems(
      sourceKey: CatalogRepository.activeSource,
      kind: kCatalogKindLive,
      items: _channels,
    );
    return repo;
  });
  return repo!;
}

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pumpAndSettle();
  }
}

List<String> listTitles(WidgetTester tester) {
  final names = _channels.map((channel) => channel.name).toSet();
  return tester
      .widgetList<Text>(find.byType(Text))
      .where((text) => names.contains(text.data))
      .map((text) => text.data!)
      .toList();
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Channel logos reach flutter_cache_manager's path_provider lookup once
    // runAsync lets real async work run (see vod_screen_test).
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (call) async => Directory.systemTemp.path,
        );
  });

  testWidgets('lists the catalog in provider order and filters by category', (
    tester,
  ) async {
    final repo = await _buildRepo(tester);
    await tester.pumpWidget(_TestApp(repository: repo));
    await settle(tester);

    expect(listTitles(tester), ['ESPN 10', 'CNN', 'BBC One', 'ESPN 2']);

    await tester.tap(find.text('Sports & UK'));
    await settle(tester);
    expect(listTitles(tester), ['ESPN 10', 'BBC One', 'ESPN 2']);
  });

  testWidgets('a remembered sort orders the page in SQL', (tester) async {
    final repo = await _buildRepo(tester);
    final viewSettings = ViewSettingsService();
    await viewSettings.setRememberMediaSort(true);
    await viewSettings.setLiveTvFavoritesFirst(false);

    await viewSettings.setLiveTvSortOption(ChannelSortOption.alphabeticalAsc);
    await tester.pumpWidget(
      _TestApp(
        key: const ValueKey('a-z'),
        repository: repo,
        viewSettingsService: viewSettings,
      ),
    );
    await settle(tester);
    // Natural order: "ESPN 2" before "ESPN 10".
    expect(listTitles(tester), ['BBC One', 'CNN', 'ESPN 2', 'ESPN 10']);

    await viewSettings.setLiveTvSortOption(ChannelSortOption.channelNumber);
    await tester.pumpWidget(
      _TestApp(
        key: const ValueKey('number'),
        repository: repo,
        viewSettingsService: viewSettings,
      ),
    );
    await settle(tester);
    expect(listTitles(tester), ['CNN', 'ESPN 2', 'BBC One', 'ESPN 10']);
  });

  testWidgets('favorites float first, and the Favorites tab shows only them', (
    tester,
  ) async {
    final repo = await _buildRepo(tester);
    final favorites = FavoritesService();
    await favorites.add(3);
    await tester.pumpWidget(
      _TestApp(repository: repo, favoritesService: favorites),
    );
    await settle(tester);
    expect(listTitles(tester), ['ESPN 2', 'ESPN 10', 'CNN', 'BBC One']);

    await tester.tap(find.text('★ Favorites'));
    await settle(tester);
    expect(listTitles(tester), ['ESPN 2']);
  });

  testWidgets('a favorite added elsewhere moves up in place', (tester) async {
    final repo = await _buildRepo(tester);
    final favorites = FavoritesService();
    await tester.pumpWidget(
      _TestApp(repository: repo, favoritesService: favorites),
    );
    await settle(tester);
    expect(listTitles(tester), ['ESPN 10', 'CNN', 'BBC One', 'ESPN 2']);

    // E.g. a detail page or a server sync, not this screen's own menu.
    await tester.runAsync(() => favorites.add(1));
    await settle(tester);
    expect(listTitles(tester), ['BBC One', 'ESPN 10', 'CNN', 'ESPN 2']);
  });

  testWidgets('search narrows the page through the catalog', (tester) async {
    final repo = await _buildRepo(tester);
    await tester.pumpWidget(_TestApp(repository: repo));
    await settle(tester);

    final field = find.byType(InlineMediaSearchField);
    if (find.byType(TextField).evaluate().isEmpty) {
      await tester.tap(field);
      await tester.pumpAndSettle();
    }
    await tester.enterText(field, 'espn');
    await settle(tester);
    expect(listTitles(tester), ['ESPN 10', 'ESPN 2']);
  });

  testWidgets(
    'a tapped row hands the player its slice, so channel up stays in it',
    (tester) async {
      final repo = await _buildRepo(tester);
      ChannelContext? reported;
      Channel? selected;
      await tester.pumpWidget(
        _TestApp(
          repository: repo,
          onChannelContextChanged: (context) => reported = context,
          onChannelSelect: (channel) => selected = channel,
        ),
      );
      await settle(tester);
      await tester.tap(find.text('Sports & UK'));
      await settle(tester);

      await tester.tap(find.text('ESPN 2'));
      await settle(tester);
      expect(selected?.id, 3);
      expect(reported, isA<CatalogChannelContext>());

      final context = reported!;
      // Sports & UK: ESPN 10, BBC One, ESPN 2 - both ends wrap.
      final next = await tester.runAsync(() => context.neighbour(3, 1));
      final previous = await tester.runAsync(() => context.neighbour(4, -1));
      expect(next?.name, 'ESPN 10');
      expect(previous?.name, 'ESPN 2');
    },
  );

  testWidgets('the guide renders catalog rows', (tester) async {
    final repo = await _buildRepo(tester);
    final favorites = FavoritesService();
    await favorites.setLastViewMode('epgGrid');
    await tester.pumpWidget(
      _TestApp(repository: repo, favoritesService: favorites),
    );
    await settle(tester);

    for (final channel in _channels) {
      expect(
        find.byKey(ValueKey('timeline-row-${channel.id}')),
        findsOneWidget,
      );
    }
  });
}

class _TestApp extends StatelessWidget {
  const _TestApp({
    super.key,
    required this.repository,
    this.favoritesService,
    this.viewSettingsService,
    this.onChannelSelect,
    this.onChannelContextChanged,
  });

  final CatalogRepository repository;
  final FavoritesService? favoritesService;
  final ViewSettingsService? viewSettingsService;
  final void Function(Channel)? onChannelSelect;
  final void Function(ChannelContext)? onChannelContextChanged;

  @override
  Widget build(BuildContext context) {
    final viewSettings = viewSettingsService ?? ViewSettingsService();
    return ProviderScope(
      overrides: [
        windowedLiveTvProvider.overrideWith((_) => true),
        catalogRepositoryProvider.overrideWith((_) => repository),
        viewSettingsServiceProvider.overrideWith((_) => viewSettings),
        isBootstrappingProvider.overrideWith((_) => false),
        isConfiguredProvider.overrideWith((_) => true),
        isLoadingContentProvider.overrideWith((_) => false),
        liveChannelsProvider.overrideWith((_) => const <Channel>[]),
        liveCategoriesProvider.overrideWith((_) => _categories),
        epgServiceProvider.overrideWith((_) => EpgService()),
        dvrRecordingsProvider.overrideWith((_) => const <DvrRecording>[]),
        recordingChannelIdsProvider.overrideWith((_) => const <int>{}),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData.dark(useMaterial3: true),
        home: LiveTvScreen(
          favoritesService: favoritesService ?? FavoritesService(),
          viewSettingsService: viewSettings,
          onChannelSelect: onChannelSelect ?? (_) {},
          onChannelContextChanged: onChannelContextChanged,
          useSidebarLayout: true,
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/live_tv/live_tv_screen.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/epg_service.dart';
import 'package:m3u_tv/services/favorites_service.dart';

void main() {
  testWidgets('long press opens channel menu and favorites explicitly', (
    tester,
  ) async {
    final favorites = FavoritesService(memory: <String, Object?>{});
    final epg = EpgService(clock: () => DateTime.utc(2026, 1, 1, 12));
    const channels = [
      Channel(
        id: 101,
        name: 'Route News',
        streamUrl: 'https://example.com/news.m3u8',
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isBootstrappingProvider.overrideWith((_) => false),
          isConfiguredProvider.overrideWith((_) => true),
          isLoadingContentProvider.overrideWith((_) => false),
          liveChannelsProvider.overrideWith((_) => channels),
          liveCategoriesProvider.overrideWith((_) => const []),
          epgServiceProvider.overrideWith((_) => epg),
          dvrRecordingsProvider.overrideWith((_) => const []),
          recordingChannelIdsProvider.overrideWith((_) => const <int>{}),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          home: LiveTvScreen(
            favoritesService: favorites,
            onChannelSelect: (_) {},
            useSidebarLayout: true,
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.longPress(find.text('Route News'));
    await tester.pumpAndSettle();

    expect(find.text('Route News'), findsWidgets);
    expect(find.text('Favorite'), findsOneWidget);
    expect(await favorites.isFavorite(101), isFalse);

    await tester.tap(find.text('Favorite'));
    await tester.pumpAndSettle();

    expect(await favorites.isFavorite(101), isTrue);
  });

  testWidgets(
    'long press menu exposes record when DVR scheduling is available',
    (tester) async {
      final favorites = FavoritesService(memory: <String, Object?>{});
      final now = DateTime.utc(2026, 1, 1, 12);
      final epg = EpgService(clock: () => now)
        ..loadPrograms([
          EpgProgram(
            channelId: 'news.epg',
            title: 'Noon News',
            description: 'News',
            start: now.subtract(const Duration(minutes: 30)),
            end: now.add(const Duration(minutes: 30)),
          ),
        ]);
      Channel? recordedChannel;
      EpgProgram? recordedProgram;
      const channels = [
        Channel(
          id: 101,
          name: 'Route News',
          streamUrl: 'https://example.com/news.m3u8',
          epgChannelId: 'news.epg',
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            isBootstrappingProvider.overrideWith((_) => false),
            isConfiguredProvider.overrideWith((_) => true),
            isLoadingContentProvider.overrideWith((_) => false),
            liveChannelsProvider.overrideWith((_) => channels),
            liveCategoriesProvider.overrideWith((_) => const []),
            epgServiceProvider.overrideWith((_) => epg),
            dvrRecordingsProvider.overrideWith((_) => const []),
            recordingChannelIdsProvider.overrideWith((_) => const <int>{}),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: LiveTvScreen(
              favoritesService: favorites,
              onChannelSelect: (_) {},
              useSidebarLayout: true,
              onScheduleProgram: (channel, program) {
                recordedChannel = channel;
                recordedProgram = program;
              },
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.longPress(find.text('Route News'));
      await tester.pumpAndSettle();

      expect(find.text('Record'), findsWidgets);
      expect(find.text('Noon News'), findsWidgets);

      await tester.tap(find.text('Record').last);
      await tester.pumpAndSettle();

      expect(recordedChannel?.id, 101);
      expect(recordedProgram?.title, 'Noon News');
    },
  );

  testWidgets(
    'long press menu shows Catchup shows only when channel supports it',
    (tester) async {
      final favorites = FavoritesService(memory: <String, Object?>{});
      final epg = EpgService(clock: () => DateTime.utc(2026, 1, 1, 12));
      const channels = [
        Channel(
          id: 101,
          name: 'Route News',
          streamUrl: 'https://example.com/news.m3u8',
          catchupSupported: true,
        ),
        Channel(
          id: 202,
          name: 'Plain Sports',
          streamUrl: 'https://example.com/sports.m3u8',
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            isBootstrappingProvider.overrideWith((_) => false),
            isConfiguredProvider.overrideWith((_) => true),
            isLoadingContentProvider.overrideWith((_) => false),
            liveChannelsProvider.overrideWith((_) => channels),
            liveCategoriesProvider.overrideWith((_) => const []),
            epgServiceProvider.overrideWith((_) => epg),
            dvrRecordingsProvider.overrideWith((_) => const []),
            recordingChannelIdsProvider.overrideWith((_) => const <int>{}),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: LiveTvScreen(
              favoritesService: favorites,
              onChannelSelect: (_) {},
              useSidebarLayout: true,
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.longPress(find.text('Route News'));
      await tester.pumpAndSettle();
      expect(find.text('Catchup shows'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('Plain Sports'));
      await tester.pumpAndSettle();
      expect(find.text('Catchup shows'), findsNothing);
    },
  );

  testWidgets(
    'selecting a catchup show from the list starts catchup playback',
    (tester) async {
      final favorites = FavoritesService(memory: <String, Object?>{});
      final now = DateTime.utc(2026, 1, 1, 12);
      final epg = EpgService(clock: () => now)
        ..loadPrograms([
          EpgProgram(
            channelId: 'news.epg',
            title: 'Morning Report',
            description: 'News',
            start: now.subtract(const Duration(hours: 3)),
            end: now.subtract(const Duration(hours: 2)),
          ),
        ]);
      Channel? selectedChannel;
      EpgProgram? selectedProgram;
      const channels = [
        Channel(
          id: 101,
          name: 'Route News',
          streamUrl: 'https://example.com/news.m3u8',
          epgChannelId: 'news.epg',
          catchupSupported: true,
          catchupDays: 7,
        ),
      ];

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            isBootstrappingProvider.overrideWith((_) => false),
            isConfiguredProvider.overrideWith((_) => true),
            isLoadingContentProvider.overrideWith((_) => false),
            liveChannelsProvider.overrideWith((_) => channels),
            liveCategoriesProvider.overrideWith((_) => const []),
            epgServiceProvider.overrideWith((_) => epg),
            dvrRecordingsProvider.overrideWith((_) => const []),
            recordingChannelIdsProvider.overrideWith((_) => const <int>{}),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: LiveTvScreen(
              favoritesService: favorites,
              onChannelSelect: (_) {},
              useSidebarLayout: true,
              onCatchupProgramSelect: (channel, program) {
                selectedChannel = channel;
                selectedProgram = program;
              },
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.longPress(find.text('Route News'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Catchup shows'));
      await tester.pumpAndSettle();

      expect(find.text('Morning Report'), findsOneWidget);

      await tester.tap(find.text('Morning Report'));
      await tester.pumpAndSettle();

      expect(selectedChannel?.id, 101);
      expect(selectedProgram?.title, 'Morning Report');
    },
  );

  testWidgets('list clears stale current and next guide data', (tester) async {
    final now = DateTime.utc(2026, 1, 1, 12);
    final favorites = FavoritesService(memory: <String, Object?>{});
    final epg = EpgService(clock: () => now)
      ..loadPrograms([
        EpgProgram(
          channelId: 'news.epg',
          title: 'Stale Noon News',
          description: 'News',
          start: now.subtract(const Duration(minutes: 30)),
          end: now.add(const Duration(minutes: 30)),
        ),
      ]);
    const channels = [
      Channel(
        id: 101,
        name: 'Route News',
        streamUrl: 'https://example.com/news.m3u8',
        epgChannelId: 'news.epg',
      ),
    ];

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          isBootstrappingProvider.overrideWith((_) => false),
          isConfiguredProvider.overrideWith((_) => true),
          isLoadingContentProvider.overrideWith((_) => false),
          liveChannelsProvider.overrideWith((_) => channels),
          liveCategoriesProvider.overrideWith((_) => const []),
          epgServiceProvider.overrideWith((_) => epg),
          dvrRecordingsProvider.overrideWith((_) => const []),
          recordingChannelIdsProvider.overrideWith((_) => const <int>{}),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: LiveTvScreen(
            favoritesService: favorites,
            onChannelSelect: (_) {},
            useSidebarLayout: true,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Stale Noon News'), findsOneWidget);

    epg.loadPrograms(const []);
    await tester.pump();

    expect(find.text('Stale Noon News'), findsNothing);
  });
}

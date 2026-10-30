import 'dart:async';

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
          windowedLiveTvProvider.overrideWith((_) => false),
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
            windowedLiveTvProvider.overrideWith((_) => false),
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
            windowedLiveTvProvider.overrideWith((_) => false),
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
            windowedLiveTvProvider.overrideWith((_) => false),
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
          windowedLiveTvProvider.overrideWith((_) => false),
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

  testWidgets(
    'catchup row shows the show title, not the episode subtitle',
    (tester) async {
      final favorites = FavoritesService(memory: <String, Object?>{});
      final now = DateTime.utc(2026, 1, 1, 12);
      final epg = EpgService(clock: () => now)
        ..loadPrograms([
          EpgProgram(
            channelId: 'news.epg',
            title: 'The Simpsons',
            subtitle: 'Aug 28 Episode',
            description: 'Animated sitcom',
            start: now.subtract(const Duration(hours: 3)),
            end: now.subtract(const Duration(hours: 2)),
          ),
        ]);
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
            windowedLiveTvProvider.overrideWith((_) => false),
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
      await tester.tap(find.text('Catchup shows'));
      await tester.pumpAndSettle();

      expect(find.text('The Simpsons'), findsOneWidget);
      expect(find.textContaining('Aug 28 Episode'), findsOneWidget);
      expect(find.textContaining('Aug 28 Episode · '), findsOneWidget);
    },
  );

  testWidgets(
    'catchup row falls back to subtitle as label when title is blank',
    (tester) async {
      final favorites = FavoritesService(memory: <String, Object?>{});
      final now = DateTime.utc(2026, 1, 1, 12);
      final epg = EpgService(clock: () => now)
        ..loadPrograms([
          EpgProgram(
            channelId: 'news.epg',
            title: '',
            subtitle: 'Evening Bulletin',
            description: 'News',
            start: now.subtract(const Duration(hours: 3)),
            end: now.subtract(const Duration(hours: 2)),
          ),
        ]);
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
            windowedLiveTvProvider.overrideWith((_) => false),
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
      await tester.tap(find.text('Catchup shows'));
      await tester.pumpAndSettle();

      expect(find.text('Evening Bulletin'), findsOneWidget);
      expect(find.textContaining('Evening Bulletin · '), findsNothing);
    },
  );

  testWidgets(
    'opening catchup dialog kicks onCatchupEpgRequested exactly once',
    (tester) async {
      final favorites = FavoritesService(memory: <String, Object?>{});
      final now = DateTime.utc(2026, 1, 1, 12);
      final epg = EpgService(clock: () => now);
      const channels = [
        Channel(
          id: 101,
          name: 'Route News',
          streamUrl: 'https://example.com/news.m3u8',
          catchupSupported: true,
          catchupDays: 7,
        ),
      ];
      Channel? fetchedFor;
      var callCount = 0;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            windowedLiveTvProvider.overrideWith((_) => false),
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
              onCatchupEpgRequested: (channel) {
                fetchedFor = channel;
                callCount += 1;
                return Future<void>.value();
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

      expect(callCount, 1);
      expect(fetchedFor?.id, 101);
    },
  );

  testWidgets(
    'catchup dialog live-updates as history arrives',
    (tester) async {
      final favorites = FavoritesService(memory: <String, Object?>{});
      final now = DateTime.utc(2026, 1, 1, 12);
      final epg = EpgService(clock: () => now);
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
      final loadComplete = Completer<void>();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            windowedLiveTvProvider.overrideWith((_) => false),
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
              onCatchupEpgRequested: (channel) => loadComplete.future,
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.longPress(find.text('Route News'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Catchup shows'));
      await tester.pump();

      expect(find.text('Loading catchup shows…'), findsOneWidget);

      epg.mergePrograms(
        [
          EpgProgram(
            channelId: 'news.epg',
            title: 'Yesterday Plus',
            description: 'News',
            start: now.subtract(const Duration(hours: 27)),
            end: now.subtract(const Duration(hours: 26)),
          ),
        ],
        channelIds: const ['news.epg'],
        replaceExisting: false,
        markFresh: false,
      );
      loadComplete.complete();
      await tester.pumpAndSettle();

      expect(find.text('Yesterday Plus'), findsOneWidget);
      expect(find.text('No catchup shows available'), findsNothing);
    },
  );
}

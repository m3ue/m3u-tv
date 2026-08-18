import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/epg/timeline_epg_view.dart';
import 'package:m3u_tv/features/live_tv/live_tv_screen.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/providers/app_providers.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/epg_service.dart';
import 'package:m3u_tv/services/favorites_service.dart';
import 'package:m3u_tv/services/persistent_store.dart';
import 'package:m3u_tv/services/view_settings_service.dart';
import 'package:m3u_tv/shared/dpad_tab_bar.dart';
import 'package:m3u_tv/shared/media_browsing_widgets.dart';

/// #217 made the Live TV search field `activateOnSelect: true` - on TV it
/// renders as a non-editing button facade until activated, so there is no
/// `TextField` in the tree to type into. Activate first, then type.
Future<void> enterQuery(WidgetTester tester, String query) async {
  final field = find.byType(InlineMediaSearchField);
  if (find.byType(TextField).evaluate().isEmpty) {
    await tester.tap(field);
    await tester.pumpAndSettle();
  }
  await tester.enterText(field, query);
}

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

    testWidgets(
      'mobile layout shows a Filter button instead of category chips, '
      'and selecting a category filters the channel list',
      (tester) async {
        await tester.pumpWidget(
          _TestApp(
            channels: testChannels,
            categories: testCategories,
            useSidebarLayout: false,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Filter'), findsOneWidget);
        expect(find.text('News'), findsNothing);

        await tester.tap(find.text('Filter'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('News'));
        await tester.pumpAndSettle();

        expect(find.text('BBC One'), findsOneWidget);
      },
    );

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

      await tester.tap(find.byIcon(Icons.search));
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
      await tester.tap(find.byIcon(Icons.search));
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
      'tapping a channel reports the current filtered list as context',
      (tester) async {
        final favoritesService = FavoritesService();
        await favoritesService.add(1);
        List<Channel>? reportedContext;

        await tester.pumpWidget(
          _TestApp(
            channels: testChannels,
            categories: testCategories,
            favoritesService: favoritesService,
            onChannelContextChanged: (channels) => reportedContext = channels,
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('★ Favorites'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('BBC One'));
        await tester.pumpAndSettle();

        expect(reportedContext, isNotNull);
        expect(reportedContext!.map((c) => c.id), [1]);
      },
    );

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

        await tester.longPress(find.text('BBC One'));
        await tester.pumpAndSettle();

        expect(find.text('Record'), findsOneWidget);
        await tester.tap(find.text('Record'));
        await tester.pumpAndSettle();

        expect(scheduledChannel?.id, 1);
        expect(scheduledProgram?.title, 'Late Show');
      },
    );

    testWidgets(
      'shows a recording indicator for a channel with an in-progress recording',
      (tester) async {
        await tester.pumpWidget(
          _TestApp(
            channels: testChannels,
            categories: testCategories,
            dvrRecordings: const [
              DvrRecording(
                uuid: 'rec-1',
                title: 'Late Show',
                status: DvrRecordingStatus.recording,
                channelId: 1,
              ),
            ],
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(const Key('recording-dot')), findsOneWidget);
      },
    );

    testWidgets(
      'bootstrap layout mapping loads list, grid and timeline correctly',
      (tester) async {
        for (final layout in LiveTvLayout.values) {
          final service = ViewSettingsService(memory: <String, Object?>{});
          await service.setLiveTvLayout(layout);

          await tester.pumpWidget(
            _TestApp(
              channels: testChannels,
              categories: testCategories,
              viewSettingsService: service,
            ),
          );
          await tester.pumpAndSettle();

          switch (layout) {
            case LiveTvLayout.list:
              expect(
                find.byKey(const ValueKey('timeline-previous-day')),
                findsNothing,
              );
            case LiveTvLayout.grid:
              expect(find.byType(ScrollbarGridView), findsOneWidget);
            case LiveTvLayout.timeline:
              expect(
                find.byKey(const ValueKey('timeline-previous-day')),
                findsOneWidget,
              );
          }
        }
      },
    );

    testWidgets(
      'D-pad Right from the Channels column enters the program grid',
      (tester) async {
        final favoritesService = FavoritesService();
        await favoritesService.setLastViewMode('epgGrid');
        final now = DateTime.now();
        final program = EpgProgram(
          channelId: 'bbc.one',
          title: 'Evening News',
          description: 'x',
          start: now.subtract(const Duration(minutes: 15)),
          end: now.add(const Duration(minutes: 15)),
        );
        final epgService = EpgService()..loadPrograms([program]);
        await tester.pumpWidget(
          _TestApp(
            channels: testChannels,
            categories: testCategories,
            favoritesService: favoritesService,
            epgService: epgService,
          ),
        );
        await tester.pumpAndSettle();

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();

        final programBlockKey = ValueKey(
          'timeline-program-${program.channelId}-'
          '${program.start.toIso8601String()}',
        );
        final focusWidgets = tester
            .widgetList<Focus>(
              find.descendant(
                of: find.byKey(programBlockKey),
                matching: find.byType(Focus),
              ),
            )
            .where((focus) => focus.focusNode != null);
        expect(focusWidgets.any((focus) => focus.focusNode!.hasFocus), isTrue);
      },
    );

    testWidgets(
      'migrates legacy favorites-service layout into a fresh view settings service',
      (tester) async {
        final favoritesService = FavoritesService();
        await favoritesService.setLastViewMode('epgGrid');
        final service = ViewSettingsService(memory: <String, Object?>{});

        await tester.pumpWidget(
          _TestApp(
            channels: testChannels,
            categories: testCategories,
            favoritesService: favoritesService,
            viewSettingsService: service,
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('timeline-previous-day')),
          findsOneWidget,
        );
        expect(await service.liveTvLayout(), LiveTvLayout.timeline);
      },
    );

    testWidgets(
      'replacement view settings service is picked up while screen is mounted',
      (tester) async {
        final firstService = ViewSettingsService(memory: <String, Object?>{});
        await firstService.setLiveTvLayout(LiveTvLayout.list);
        await tester.pumpWidget(
          _TestApp(
            channels: testChannels,
            categories: testCategories,
            viewSettingsService: firstService,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('timeline-previous-day')),
          findsNothing,
        );

        final secondService = ViewSettingsService(memory: <String, Object?>{});
        await secondService.setLiveTvLayout(LiveTvLayout.timeline);
        await tester.pumpWidget(
          _TestApp(
            channels: testChannels,
            categories: testCategories,
            viewSettingsService: secondService,
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('timeline-previous-day')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'retained screen updates view mode when view settings change while mounted',
      (tester) async {
        final service = ViewSettingsService(memory: <String, Object?>{});
        await service.setLiveTvLayout(LiveTvLayout.list);

        await tester.pumpWidget(
          _TestApp(
            channels: testChannels,
            categories: testCategories,
            viewSettingsService: service,
          ),
        );
        await tester.pumpAndSettle();

        // List view renders channel rows; timeline day controls are absent.
        expect(find.text('BBC One'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('timeline-previous-day')),
          findsNothing,
        );

        await service.setLiveTvLayout(LiveTvLayout.timeline);
        await tester.pumpAndSettle();

        // Timeline view renders day controls instead of list rows.
        expect(
          find.byKey(const ValueKey('timeline-previous-day')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'retained screen updates EPG start view when settings change while mounted',
      (tester) async {
        final service = ViewSettingsService(memory: <String, Object?>{});
        await service.setLiveTvLayout(LiveTvLayout.timeline);
        await service.setEpgStartView(EpgStartView.currentTime);

        await tester.pumpWidget(
          _TestApp(
            channels: testChannels,
            categories: testCategories,
            viewSettingsService: service,
          ),
        );
        await tester.pumpAndSettle();

        final currentOffset = _timelineHorizontalOffset(tester);

        await service.setEpgStartView(EpgStartView.primeTime);
        await tester.pumpAndSettle();

        final primeOffset = _timelineHorizontalOffset(tester);
        expect(primeOffset, isNot(currentOffset));
      },
    );
    testWidgets('stale reload from replaced service is ignored', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final dir = await Directory.systemTemp.createTemp(
          'live_tv_view_settings',
        );
        addTearDown(() => dir.delete(recursive: true));

        final firstFile = File('${dir.path}/service_a.json');
        final secondFile = File('${dir.path}/service_b.json');

        final slowStoreA = _SlowPersistentJsonStore(
          file: firstFile,
          readDelay: const Duration(milliseconds: 100),
        );
        final serviceA = ViewSettingsService(store: slowStoreA);
        await serviceA.setLiveTvLayout(LiveTvLayout.list);
        await serviceA.setEpgStartView(EpgStartView.currentTime);

        await tester.pumpWidget(
          _TestApp(
            channels: testChannels,
            categories: testCategories,
            viewSettingsService: serviceA,
          ),
        );
        await tester.pumpAndSettle();

        final storeB = PersistentJsonStore(file: secondFile);
        final serviceB = ViewSettingsService(store: storeB);
        await serviceB.setLiveTvLayout(LiveTvLayout.timeline);
        await serviceB.setEpgStartView(EpgStartView.primeTime);

        await tester.pumpWidget(
          _TestApp(
            channels: testChannels,
            categories: testCategories,
            viewSettingsService: serviceB,
          ),
        );
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('timeline-previous-day')),
          findsOneWidget,
        );
        final primeOffset = _timelineHorizontalOffset(tester);

        // Let service A's delayed read finish after B has already won.
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('timeline-previous-day')),
          findsOneWidget,
        );
        expect(_timelineHorizontalOffset(tester), primeOffset);
      });
    });

    testWidgets('stale reload after rapid view settings updates is ignored', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final dir = await Directory.systemTemp.createTemp(
          'live_tv_view_settings',
        );
        addTearDown(() => dir.delete(recursive: true));

        final slowStore = _SlowPersistentJsonStore(
          file: File('${dir.path}/store.json'),
        );
        final service = ViewSettingsService(store: slowStore);
        await service.setLiveTvLayout(LiveTvLayout.list);
        await service.setEpgStartView(EpgStartView.currentTime);

        await tester.pumpWidget(
          _TestApp(
            channels: testChannels,
            categories: testCategories,
            viewSettingsService: service,
          ),
        );
        await tester.pumpAndSettle();

        // Queue two rapid changes while reads are held; only the latest wins.
        slowStore.holdReads();
        final firstLayout = service.setLiveTvLayout(LiveTvLayout.grid);
        final secondLayout = service.setLiveTvLayout(LiveTvLayout.timeline);
        final firstEpg = service.setEpgStartView(EpgStartView.primeTime);
        await Future.wait([firstLayout, secondLayout, firstEpg]);
        slowStore.releaseReads();
        await Future<void>.delayed(const Duration(milliseconds: 200));
        await tester.pumpAndSettle();

        expect(
          find.byKey(const ValueKey('timeline-previous-day')),
          findsOneWidget,
        );
      });
    });
  });

  group('LiveTvScreen search results', () {
    late List<Channel> channels;
    late List<Category> categories;
    late DateTime futureTime;

    setUp(() {
      futureTime = DateTime.now().toUtc().add(const Duration(hours: 1));
      channels = [
        const Channel(
          id: 1,
          name: 'BBC One',
          streamUrl: 'http://example.com/1.m3u8',
          categoryId: '10',
        ),
        const Channel(
          id: 2,
          name: 'CNN',
          streamUrl: 'http://example.com/2.m3u8',
          categoryId: '11',
        ),
        const Channel(
          id: 3,
          name: 'ESPN',
          streamUrl: 'http://example.com/3.m3u8',
          categoryId: '12',
        ),
      ];
      categories = [
        const Category(id: '10', name: 'News'),
        const Category(id: '11', name: 'Entertainment'),
        const Category(id: '12', name: 'Sports'),
      ];
    });

    Future<List<EpgShow>> Function(String) staticResults(
      List<EpgShow> results,
    ) {
      return (query) async => results;
    }

    final tabBarFinder = find.byType(DpadTabBar);
    final allTab = find.text('All');
    final onNowTab = find.text('On Now');
    final upcomingTab = find.text('Upcoming');

    testWidgets('null onSearchShows keeps the channel list, no tab bar', (
      tester,
    ) async {
      await tester.pumpWidget(
        _TestApp(channels: channels, categories: categories),
      );
      await tester.pumpAndSettle();

      await enterQuery(tester, 'bbc');
      await tester.pumpAndSettle();

      expect(tabBarFinder, findsNothing);
      // Channel-name filter still applies synchronously.
      expect(find.text('BBC One'), findsOneWidget);
      expect(find.text('CNN'), findsNothing);
    });

    testWidgets('query under 2 chars keeps the channel list, no tab bar', (
      tester,
    ) async {
      await tester.pumpWidget(
        _TestApp(
          channels: channels,
          categories: categories,
          onSearchShows: staticResults(const []),
        ),
      );
      await tester.pumpAndSettle();

      await enterQuery(tester, 'b');
      await tester.pumpAndSettle();

      expect(tabBarFinder, findsNothing);
      expect(find.text('BBC One'), findsOneWidget);
    });

    testWidgets(
      'qualifying query with onSearchShows replaces the channel list with tabs',
      (tester) async {
        await tester.pumpWidget(
          _TestApp(
            channels: channels,
            categories: categories,
            onSearchShows: staticResults(const []),
          ),
        );
        await tester.pumpAndSettle();

        await enterQuery(tester, 'bb');
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();

        expect(tabBarFinder, findsOneWidget);
        expect(allTab, findsOneWidget);
        expect(onNowTab, findsOneWidget);
        expect(upcomingTab, findsOneWidget);
        // Channel-name-filtered channel list is gone while search is active.
        expect(find.text('BBC One'), findsNothing);
      },
    );

    testWidgets(
      'D-pad Right from the nav strip enters the search results, not a '
      'dead grid scope',
      (tester) async {
        await tester.pumpWidget(
          _TestApp(
            channels: channels,
            categories: categories,
            onSearchShows: staticResults([
              EpgShow(
                normalizedTitle: 'show',
                displayTitle: 'Show',
                channelCount: 1,
                channels: const [],
                episodeCount: 0,
                recentEpisodes: [
                  EpgShowEpisode(
                    channelId: 1,
                    channelName: 'Channel',
                    title: 'Episode',
                    startTime: futureTime,
                    endTime: futureTime.add(const Duration(hours: 1)),
                  ),
                ],
              ),
            ]),
          ),
        );
        await tester.pumpAndSettle();

        await enterQuery(tester, 'sh');
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();

        // Move focus onto a plain category chip rather than leaving it in
        // the search TextField - EditableText intercepts Right for cursor
        // movement, which would make this test pass or fail for the wrong
        // reason regardless of the strip's edge-handoff wiring.
        await tester.tap(find.text('News'));
        await tester.pumpAndSettle();

        // MediaCategoryNav's strip still hands right-edge focus to
        // gridFocusScopeNode, which must now point at the search-results
        // scope (not the empty channel-grid one) while results are shown.
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();

        final resultsFocus = tester
            .widgetList<Focus>(
              find.descendant(
                of: find.byType(DpadTabBarView),
                matching: find.byType(Focus),
              ),
            )
            .where((focus) => focus.focusNode != null);
        expect(
          resultsFocus.any((focus) => focus.focusNode!.hasFocus),
          isTrue,
        );
      },
    );

    testWidgets('clearing the query restores the channel list', (
      tester,
    ) async {
      await tester.pumpWidget(
        _TestApp(
          channels: channels,
          categories: categories,
          onSearchShows: staticResults(const []),
        ),
      );
      await tester.pumpAndSettle();

      await enterQuery(tester, 'bb');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      expect(tabBarFinder, findsOneWidget);

      await enterQuery(tester, '');
      await tester.pumpAndSettle();
      expect(tabBarFinder, findsNothing);
      expect(find.text('BBC One'), findsOneWidget);
    });

    testWidgets(
      'throwing onSearchShows renders search-failed on the All tab',
      (tester) async {
        await tester.pumpWidget(
          _TestApp(
            channels: channels,
            categories: categories,
            onSearchShows: (query) async => throw StateError('boom'),
          ),
        );
        await tester.pumpAndSettle();

        await enterQuery(tester, 'bbc');
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();

        expect(find.text('Search failed'), findsOneWidget);
        expect(find.text('No shows match your search'), findsNothing);
      },
    );

    testWidgets(
      'synchronously shows loading on first qualifying keystroke',
      (tester) async {
        final pending = Completer<List<EpgShow>>();
        await tester.pumpWidget(
          _TestApp(
            channels: channels,
            categories: categories,
            onSearchShows: (query) => pending.future,
          ),
        );
        await tester.pumpAndSettle();

        await enterQuery(tester, 'bb');
        // Pump exactly one frame - the debounce hasn't fired yet (350ms),
        // but the All tab should already render "Searching shows…" instead
        // of "No shows match your search".
        await tester.pump();
        expect(find.text('Searching shows…'), findsOneWidget);
        expect(find.text('No shows match your search'), findsNothing);

        pending.complete(const <EpgShow>[]);
        await tester.pumpAndSettle();
      },
    );

    group('All tab', () {
      testWidgets('shows On Now first, then Upcoming', (tester) async {
        await tester.pumpWidget(
          _TestApp(
            channels: channels,
            categories: categories,
            onSearchShows: staticResults([
              EpgShow(
                normalizedTitle: 'live-show',
                displayTitle: 'Live Show',
                channelCount: 1,
                channels: const [],
                episodeCount: 0,
                recentEpisodes: const [],
                airingNow: [
                  EpgShowEpisode(
                    channelId: 1,
                    channelName: 'BBC One',
                    title: 'Live Episode',
                    startTime: futureTime.subtract(const Duration(minutes: 10)),
                    endTime: futureTime.add(const Duration(minutes: 50)),
                  ),
                ],
              ),
              EpgShow(
                normalizedTitle: 'future-show',
                displayTitle: 'Future Show',
                channelCount: 1,
                channels: const [],
                episodeCount: 0,
                recentEpisodes: [
                  EpgShowEpisode(
                    channelId: 2,
                    channelName: 'CNN',
                    title: 'Future Episode',
                    startTime: futureTime.add(const Duration(hours: 2)),
                    endTime: futureTime.add(const Duration(hours: 3)),
                  ),
                ],
              ),
            ]),
          ),
        );
        await tester.pumpAndSettle();

        await enterQuery(tester, 'show');
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();

        final liveTitle = tester.getCenter(find.text('Live Show'));
        final futureTitle = tester.getCenter(find.text('Future Show'));
        expect(liveTitle.dy, lessThan(futureTitle.dy));
      });

      testWidgets(
        'a show airing now is not duplicated as an Upcoming row for the same channel',
        (tester) async {
          await tester.pumpWidget(
            _TestApp(
              channels: channels,
              categories: categories,
              onSearchShows: staticResults([
                EpgShow(
                  normalizedTitle: 'rerun-show',
                  displayTitle: 'Rerun Show',
                  channelCount: 1,
                  channels: const [],
                  episodeCount: 0,
                  recentEpisodes: [
                    // A later rerun of the SAME channel the show is
                    // currently airing on - must be suppressed, since the
                    // On Now row already represents this (show, channel).
                    EpgShowEpisode(
                      channelId: 1,
                      channelName: 'BBC One',
                      title: 'Rerun Episode',
                      startTime: futureTime.add(const Duration(hours: 4)),
                      endTime: futureTime.add(const Duration(hours: 5)),
                    ),
                  ],
                  airingNow: [
                    EpgShowEpisode(
                      channelId: 1,
                      channelName: 'BBC One',
                      title: 'Rerun Episode',
                      startTime: futureTime.subtract(
                        const Duration(minutes: 10),
                      ),
                      endTime: futureTime.add(const Duration(minutes: 50)),
                    ),
                  ],
                ),
              ]),
            ),
          );
          await tester.pumpAndSettle();

          await enterQuery(tester, 'rerun');
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pumpAndSettle();

          // Exactly one "Rerun Show" row - the On Now one.
          expect(find.text('Rerun Show'), findsOneWidget);
        },
      );

      testWidgets(
        'a show airing now on one channel still shows Upcoming on a different channel',
        (tester) async {
          await tester.pumpWidget(
            _TestApp(
              channels: channels,
              categories: categories,
              onSearchShows: staticResults([
                EpgShow(
                  normalizedTitle: 'syndicated-show',
                  displayTitle: 'Syndicated Show',
                  channelCount: 2,
                  channels: const [],
                  episodeCount: 0,
                  recentEpisodes: [
                    EpgShowEpisode(
                      channelId: 2,
                      channelName: 'CNN',
                      title: 'Later Airing',
                      startTime: futureTime.add(const Duration(hours: 4)),
                      endTime: futureTime.add(const Duration(hours: 5)),
                    ),
                  ],
                  airingNow: [
                    EpgShowEpisode(
                      channelId: 1,
                      channelName: 'BBC One',
                      title: 'Now Airing',
                      startTime: futureTime.subtract(
                        const Duration(minutes: 10),
                      ),
                      endTime: futureTime.add(const Duration(minutes: 50)),
                    ),
                  ],
                ),
              ]),
            ),
          );
          await tester.pumpAndSettle();

          await enterQuery(tester, 'synd');
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pumpAndSettle();

          // Two distinct rows: one On Now (BBC One), one Upcoming (CNN).
          expect(find.text('Syndicated Show'), findsNWidgets(2));
        },
      );
    });

    group('On Now tab', () {
      testWidgets('shows only currently-airing entries', (tester) async {
        await tester.pumpWidget(
          _TestApp(
            channels: channels,
            categories: categories,
            onSearchShows: staticResults([
              EpgShow(
                normalizedTitle: 'live-show',
                displayTitle: 'Live Show',
                channelCount: 1,
                channels: const [],
                episodeCount: 0,
                recentEpisodes: const [],
                airingNow: [
                  EpgShowEpisode(
                    channelId: 1,
                    channelName: 'BBC One',
                    title: 'Live Episode',
                    startTime: futureTime.subtract(const Duration(minutes: 10)),
                    endTime: futureTime.add(const Duration(minutes: 50)),
                  ),
                ],
              ),
              EpgShow(
                normalizedTitle: 'future-show',
                displayTitle: 'Future Show',
                channelCount: 1,
                channels: const [],
                episodeCount: 0,
                recentEpisodes: [
                  EpgShowEpisode(
                    channelId: 2,
                    channelName: 'CNN',
                    title: 'Future Episode',
                    startTime: futureTime.add(const Duration(hours: 2)),
                    endTime: futureTime.add(const Duration(hours: 3)),
                  ),
                ],
              ),
            ]),
          ),
        );
        await tester.pumpAndSettle();

        await enterQuery(tester, 'show');
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();

        await tester.tap(onNowTab);
        await tester.pumpAndSettle();

        expect(find.text('Live Show'), findsOneWidget);
        expect(find.text('Future Show'), findsNothing);
      });

      testWidgets(
        'omits airingNow entries whose channelId matches no Channel',
        (tester) async {
          await tester.pumpWidget(
            _TestApp(
              channels: channels,
              categories: categories,
              onSearchShows: staticResults([
                EpgShow(
                  normalizedTitle: 'orphan-show',
                  displayTitle: 'Orphan Show',
                  channelCount: 1,
                  channels: const [],
                  episodeCount: 0,
                  recentEpisodes: const [],
                  airingNow: [
                    EpgShowEpisode(
                      channelId: 999,
                      channelName: 'Unknown Channel',
                      title: 'Orphan Episode',
                      startTime: futureTime.subtract(
                        const Duration(minutes: 10),
                      ),
                      endTime: futureTime.add(const Duration(minutes: 50)),
                    ),
                  ],
                ),
              ]),
            ),
          );
          await tester.pumpAndSettle();

          await enterQuery(tester, 'orphan');
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pumpAndSettle();

          await tester.tap(onNowTab);
          await tester.pumpAndSettle();

          expect(find.text('Orphan Show'), findsNothing);
          expect(find.text('No shows match your search'), findsOneWidget);
        },
      );

      testWidgets('tapping a row tunes the channel and updates context', (
        tester,
      ) async {
        Channel? tapped;
        List<Channel>? context;
        await tester.pumpWidget(
          _TestApp(
            channels: channels,
            categories: categories,
            onChannelSelect: (channel) => tapped = channel,
            onChannelContextChanged: (ctx) => context = ctx,
            onSearchShows: staticResults([
              EpgShow(
                normalizedTitle: 'live-show',
                displayTitle: 'Live Show',
                channelCount: 1,
                channels: const [],
                episodeCount: 0,
                recentEpisodes: const [],
                airingNow: [
                  EpgShowEpisode(
                    channelId: 1,
                    channelName: 'BBC One',
                    title: 'Live Episode',
                    startTime: futureTime.subtract(const Duration(minutes: 10)),
                    endTime: futureTime.add(const Duration(minutes: 50)),
                  ),
                ],
              ),
            ]),
          ),
        );
        await tester.pumpAndSettle();

        await enterQuery(tester, 'live');
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Live Show'));
        await tester.pumpAndSettle();

        expect(tapped?.id, 1);
        expect(context, isNotNull);
        expect(context!.map((c) => c.id), [1]);
      });

      testWidgets(
        'subtitle falls back to channel name with no episode subtitle',
        (
          tester,
        ) async {
          await tester.pumpWidget(
            _TestApp(
              channels: channels,
              categories: categories,
              onSearchShows: staticResults([
                EpgShow(
                  normalizedTitle: 'live-show',
                  displayTitle: 'Live Show',
                  channelCount: 1,
                  channels: const [],
                  episodeCount: 0,
                  recentEpisodes: const [],
                  airingNow: [
                    EpgShowEpisode(
                      channelId: 1,
                      channelName: 'BBC One',
                      title: 'Live Episode',
                      startTime: futureTime.subtract(
                        const Duration(minutes: 10),
                      ),
                      endTime: futureTime.add(const Duration(minutes: 50)),
                    ),
                  ],
                ),
              ]),
            ),
          );
          await tester.pumpAndSettle();

          await enterQuery(tester, 'live');
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pumpAndSettle();

          expect(find.text('BBC One'), findsOneWidget);
        },
      );

      testWidgets(
        'whitespace-only channel name does not render a blank subtitle',
        (tester) async {
          await tester.pumpWidget(
            _TestApp(
              channels: channels,
              categories: categories,
              onSearchShows: staticResults([
                EpgShow(
                  normalizedTitle: 'live-show',
                  displayTitle: 'Live Show',
                  channelCount: 1,
                  channels: const [],
                  episodeCount: 0,
                  recentEpisodes: const [],
                  airingNow: [
                    EpgShowEpisode(
                      channelId: 1,
                      channelName: ' ',
                      title: 'Live Episode',
                      startTime: futureTime.subtract(
                        const Duration(minutes: 10),
                      ),
                      endTime: futureTime.add(const Duration(minutes: 50)),
                    ),
                  ],
                ),
              ]),
            ),
          );
          await tester.pumpAndSettle();

          await enterQuery(tester, 'live');
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pumpAndSettle();

          // Only the title Text renders under the row - no blank subtitle.
          final row = find.ancestor(
            of: find.text('Live Show'),
            matching: find.byType(Column),
          );
          final blankTexts = tester
              .widgetList<Text>(
                find.descendant(of: row.first, matching: find.byType(Text)),
              )
              .where((t) => t.data != null && t.data!.trim().isEmpty);
          expect(blankTexts, isEmpty);
        },
      );
    });

    group('Upcoming tab', () {
      testWidgets('shows only future entries', (tester) async {
        await tester.pumpWidget(
          _TestApp(
            channels: channels,
            categories: categories,
            onSearchShows: staticResults([
              EpgShow(
                normalizedTitle: 'live-show',
                displayTitle: 'Live Show',
                channelCount: 1,
                channels: const [],
                episodeCount: 0,
                recentEpisodes: const [],
                airingNow: [
                  EpgShowEpisode(
                    channelId: 1,
                    channelName: 'BBC One',
                    title: 'Live Episode',
                    startTime: futureTime.subtract(const Duration(minutes: 10)),
                    endTime: futureTime.add(const Duration(minutes: 50)),
                  ),
                ],
              ),
              EpgShow(
                normalizedTitle: 'future-show',
                displayTitle: 'Future Show',
                channelCount: 1,
                channels: const [],
                episodeCount: 0,
                recentEpisodes: [
                  EpgShowEpisode(
                    channelId: 2,
                    channelName: 'CNN',
                    title: 'Future Episode',
                    startTime: futureTime.add(const Duration(hours: 2)),
                    endTime: futureTime.add(const Duration(hours: 3)),
                  ),
                ],
              ),
            ]),
          ),
        );
        await tester.pumpAndSettle();

        await enterQuery(tester, 'show');
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();

        await tester.tap(upcomingTab);
        await tester.pumpAndSettle();

        expect(find.text('Future Show'), findsOneWidget);
        expect(find.text('Live Show'), findsNothing);
      });

      testWidgets('drops past airings', (tester) async {
        await tester.pumpWidget(
          _TestApp(
            channels: channels,
            categories: categories,
            onSearchShows: staticResults([
              EpgShow(
                normalizedTitle: 'show',
                displayTitle: 'Show',
                channelCount: 1,
                channels: const [],
                episodeCount: 0,
                recentEpisodes: [
                  EpgShowEpisode(
                    channelId: 1,
                    channelName: 'Channel',
                    title: 'Past Episode',
                    startTime: futureTime.subtract(const Duration(hours: 2)),
                    endTime: futureTime.subtract(const Duration(hours: 1)),
                  ),
                  EpgShowEpisode(
                    channelId: 1,
                    channelName: 'Channel',
                    title: 'Future Episode',
                    startTime: futureTime.add(const Duration(hours: 1)),
                    endTime: futureTime.add(const Duration(hours: 2)),
                  ),
                ],
              ),
            ]),
          ),
        );
        await tester.pumpAndSettle();

        await enterQuery(tester, 'sh');
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();

        await tester.tap(upcomingTab);
        await tester.pumpAndSettle();

        // Only one row for the show, and its trailing time reflects the
        // single future episode, not the dropped past one.
        expect(find.text('Show'), findsOneWidget);
      });

      testWidgets('drops blank-title episodes', (tester) async {
        await tester.pumpWidget(
          _TestApp(
            channels: channels,
            categories: categories,
            onSearchShows: staticResults([
              EpgShow(
                normalizedTitle: 'good',
                displayTitle: 'Good Show',
                channelCount: 1,
                channels: const [],
                episodeCount: 0,
                recentEpisodes: [
                  EpgShowEpisode(
                    channelId: 1,
                    channelName: 'BBC One',
                    title: 'Good Episode',
                    startTime: futureTime,
                    endTime: futureTime.add(const Duration(hours: 1)),
                  ),
                ],
              ),
              EpgShow(
                normalizedTitle: 'bad',
                displayTitle: 'Bad Show',
                channelCount: 1,
                channels: const [],
                episodeCount: 0,
                recentEpisodes: [
                  EpgShowEpisode(
                    channelId: 2,
                    channelName: 'BBC Two',
                    title: '',
                    startTime: futureTime,
                    endTime: futureTime.add(const Duration(hours: 1)),
                  ),
                ],
              ),
            ]),
          ),
        );
        await tester.pumpAndSettle();

        await enterQuery(tester, 'sh');
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();

        await tester.tap(upcomingTab);
        await tester.pumpAndSettle();

        expect(find.text('Good Show'), findsOneWidget);
        expect(find.text('Bad Show'), findsNothing);
      });

      testWidgets(
        'groups repeated airings of the same show+channel into one row',
        (tester) async {
          await tester.pumpWidget(
            _TestApp(
              channels: channels,
              categories: categories,
              onSearchShows: staticResults([
                EpgShow(
                  normalizedTitle: 'grace-and-frankie',
                  displayTitle: 'Grace and Frankie',
                  channelCount: 1,
                  channels: const [],
                  episodeCount: 0,
                  recentEpisodes: List.generate(
                    5,
                    (i) => EpgShowEpisode(
                      channelId: 1,
                      channelName: 'BBC One',
                      title: 'Episode $i',
                      startTime: futureTime.add(Duration(hours: i)),
                      endTime: futureTime.add(Duration(hours: i + 1)),
                    ),
                  ),
                ),
              ]),
            ),
          );
          await tester.pumpAndSettle();

          await enterQuery(tester, 'grace');
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pumpAndSettle();

          await tester.tap(upcomingTab);
          await tester.pumpAndSettle();

          // One row, not five - and a "+N more" affordance for the airings
          // beyond the first 3 shown.
          expect(find.text('Grace and Frankie'), findsOneWidget);
          expect(find.textContaining('more'), findsOneWidget);
        },
      );

      testWidgets('same show on two channels renders two rows', (
        tester,
      ) async {
        await tester.pumpWidget(
          _TestApp(
            channels: channels,
            categories: categories,
            onSearchShows: staticResults([
              EpgShow(
                normalizedTitle: 'show',
                displayTitle: 'Show',
                channelCount: 2,
                channels: const [],
                episodeCount: 0,
                recentEpisodes: [
                  EpgShowEpisode(
                    channelId: 1,
                    channelName: 'BBC One',
                    title: 'Episode A',
                    startTime: futureTime,
                    endTime: futureTime.add(const Duration(hours: 1)),
                  ),
                  EpgShowEpisode(
                    channelId: 2,
                    channelName: 'CNN',
                    title: 'Episode B',
                    startTime: futureTime.add(const Duration(hours: 1)),
                    endTime: futureTime.add(const Duration(hours: 2)),
                  ),
                ],
              ),
            ]),
          ),
        );
        await tester.pumpAndSettle();

        await enterQuery(tester, 'sh');
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();

        await tester.tap(upcomingTab);
        await tester.pumpAndSettle();

        expect(find.text('Show'), findsNWidgets(2));
      });

      testWidgets('groups order by earliest airing across shows', (
        tester,
      ) async {
        await tester.pumpWidget(
          _TestApp(
            channels: channels,
            categories: categories,
            onSearchShows: staticResults([
              EpgShow(
                normalizedTitle: 'later',
                displayTitle: 'Later Show',
                channelCount: 1,
                channels: const [],
                episodeCount: 0,
                recentEpisodes: [
                  EpgShowEpisode(
                    channelId: 1,
                    channelName: 'Channel',
                    title: 'Episode',
                    startTime: futureTime.add(const Duration(hours: 5)),
                    endTime: futureTime.add(const Duration(hours: 6)),
                  ),
                ],
              ),
              EpgShow(
                normalizedTitle: 'sooner',
                displayTitle: 'Sooner Show',
                channelCount: 1,
                channels: const [],
                episodeCount: 0,
                recentEpisodes: [
                  EpgShowEpisode(
                    channelId: 2,
                    channelName: 'Channel',
                    title: 'Episode',
                    startTime: futureTime.add(const Duration(hours: 1)),
                    endTime: futureTime.add(const Duration(hours: 2)),
                  ),
                ],
              ),
            ]),
          ),
        );
        await tester.pumpAndSettle();

        await enterQuery(tester, 'show');
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();

        await tester.tap(upcomingTab);
        await tester.pumpAndSettle();

        final soonerPos = tester.getCenter(find.text('Sooner Show'));
        final laterPos = tester.getCenter(find.text('Later Show'));
        expect(soonerPos.dy, lessThan(laterPos.dy));
      });

      testWidgets(
        'renders a day-relative airing time on the row',
        (tester) async {
          final now = DateTime.now();
          final laterToday = DateTime(now.year, now.month, now.day, 23).toUtc();
          await tester.pumpWidget(
            _TestApp(
              channels: channels,
              categories: categories,
              onSearchShows: staticResults([
                EpgShow(
                  normalizedTitle: 'local-time',
                  displayTitle: 'Local Time Check',
                  channelCount: 1,
                  channels: const [
                    EpgShowChannel(channelId: 1, channelName: 'BBC One'),
                  ],
                  episodeCount: 0,
                  recentEpisodes: [
                    EpgShowEpisode(
                      channelId: 1,
                      channelName: 'BBC One',
                      title: 'Episode Slot',
                      startTime: laterToday.isAfter(DateTime.now().toUtc())
                          ? laterToday
                          : laterToday.add(const Duration(days: 1)),
                      endTime: laterToday.add(const Duration(hours: 1)),
                    ),
                  ],
                ),
              ]),
            ),
          );
          await tester.pumpAndSettle();

          await enterQuery(tester, 'loc');
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pumpAndSettle();

          expect(find.text('Local Time Check'), findsOneWidget);
          expect(find.text('BBC One'), findsOneWidget);
        },
      );

      testWidgets('tapping a row invokes onShowSelect with the parent show', (
        tester,
      ) async {
        EpgShow? tapped;
        // "Nightly Report", not "News" - the fixture categories in this
        // file already include a "News" category tab, which stays visible
        // in the nav strip above the results and would collide.
        final parent = EpgShow(
          normalizedTitle: 'nightly-report',
          displayTitle: 'Nightly Report',
          channelCount: 1,
          channels: const [],
          episodeCount: 0,
          recentEpisodes: [
            EpgShowEpisode(
              channelId: 1,
              channelName: 'BBC One',
              title: 'Nightly Report Episode',
              startTime: futureTime,
              endTime: futureTime.add(const Duration(hours: 1)),
            ),
          ],
        );
        await tester.pumpWidget(
          _TestApp(
            channels: channels,
            categories: categories,
            onSearchShows: (_) async => [parent],
            onShowSelect: (show) => tapped = show,
          ),
        );
        await tester.pumpAndSettle();

        await enterQuery(tester, 'ni');
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Nightly Report'));
        await tester.pumpAndSettle();

        expect(tapped, isNotNull);
        expect(tapped!.normalizedTitle, 'nightly-report');
      });

      testWidgets('null onShowSelect is a no-op, not a throw', (
        tester,
      ) async {
        await tester.pumpWidget(
          _TestApp(
            channels: channels,
            categories: categories,
            onSearchShows: staticResults([
              EpgShow(
                normalizedTitle: 'nightly-report',
                displayTitle: 'Nightly Report',
                channelCount: 1,
                channels: const [],
                episodeCount: 0,
                recentEpisodes: [
                  EpgShowEpisode(
                    channelId: 1,
                    channelName: 'Channel',
                    title: 'Nightly Report Episode',
                    startTime: futureTime,
                    endTime: futureTime.add(const Duration(hours: 1)),
                  ),
                ],
              ),
            ]),
            // No onShowSelect callback.
          ),
        );
        await tester.pumpAndSettle();

        await enterQuery(tester, 'ni');
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();

        await tester.tap(find.text('Nightly Report'));
        await tester.pumpAndSettle();
      });
    });

    testWidgets(
      'starting a new qualifying search resets the tab back to All',
      (tester) async {
        // "Nightly Report" is upcoming-only; "Weather" is on-now-only (the
        // "News" category tab in the fixture categories would otherwise
        // collide with a show named "News"). If the tab is still on
        // Upcoming after the reset, Weather stays hidden; if the reset
        // actually landed back on All, both are visible.
        final results = staticResults([
          EpgShow(
            normalizedTitle: 'nightly-report',
            displayTitle: 'Nightly Report',
            channelCount: 1,
            channels: const [],
            episodeCount: 0,
            recentEpisodes: [
              EpgShowEpisode(
                channelId: 1,
                channelName: 'Channel',
                title: 'Nightly Report Episode',
                startTime: futureTime,
                endTime: futureTime.add(const Duration(hours: 1)),
              ),
            ],
          ),
          EpgShow(
            normalizedTitle: 'weather',
            displayTitle: 'Weather',
            channelCount: 1,
            channels: const [],
            episodeCount: 0,
            recentEpisodes: const [],
            airingNow: [
              EpgShowEpisode(
                channelId: 2,
                channelName: 'Channel',
                title: 'Weather Episode',
                startTime: futureTime.subtract(const Duration(minutes: 10)),
                endTime: futureTime.add(const Duration(minutes: 50)),
              ),
            ],
          ),
        ]);
        await tester.pumpWidget(
          _TestApp(
            channels: channels,
            categories: categories,
            onSearchShows: results,
          ),
        );
        await tester.pumpAndSettle();

        await enterQuery(tester, 'ni');
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();

        await tester.tap(upcomingTab);
        await tester.pumpAndSettle();
        expect(find.text('Nightly Report'), findsOneWidget);
        expect(find.text('Weather'), findsNothing);

        // Drop below the 2-char threshold, then start a fresh search.
        await enterQuery(tester, '');
        await tester.pumpAndSettle();
        await enterQuery(tester, 'ni');
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pumpAndSettle();

        // Back on the All tab - both rows render again.
        expect(find.text('Nightly Report'), findsOneWidget);
        expect(find.text('Weather'), findsOneWidget);
      },
    );
  });
}

class _SlowPersistentJsonStore extends PersistentJsonStore {
  _SlowPersistentJsonStore({
    required super.file,
    this.readDelay = Duration.zero,
  });

  final Duration readDelay;
  final _pending = <Completer<void>>[];
  var _hold = false;

  void holdReads() => _hold = true;

  void releaseReads() {
    _hold = false;
    for (final completer in _pending) {
      completer.complete();
    }
    _pending.clear();
  }

  @override
  Future<Object?> read(String key) async {
    if (_hold) {
      final completer = Completer<void>();
      _pending.add(completer);
      await completer.future;
    }
    if (readDelay > Duration.zero) {
      await Future<void>.delayed(readDelay);
    }
    return super.read(key);
  }
}

Scrollable _timelineHorizontalOffsetRow(WidgetTester tester) {
  return tester.widget<Scrollable>(
    find
        .descendant(
          of: find.byType(TimelineEpgView),
          matching: find.byWidgetPredicate(
            (widget) => widget is Scrollable && widget.axis == Axis.horizontal,
          ),
        )
        .first,
  );
}

double _timelineHorizontalOffset(WidgetTester tester) {
  return _timelineHorizontalOffsetRow(tester).controller!.offset;
}

class _TestApp extends StatelessWidget {
  const _TestApp({
    required this.channels,
    required this.categories,
    this.isLoading = false,
    this.isConfigured = true,
    this.favoritesService,
    this.viewSettingsService,
    this.epgService,
    this.onChannelSelect,
    this.onChannelContextChanged,
    this.onScheduleProgram,
    this.dvrRecordings = const [],
    this.useSidebarLayout = true,
    this.onSearchShows,
    this.onShowSelect,
  });

  final List<Channel> channels;
  final List<Category> categories;
  final bool isLoading;
  final bool isConfigured;
  final FavoritesService? favoritesService;
  final ViewSettingsService? viewSettingsService;
  final EpgService? epgService;
  final void Function(Channel)? onChannelSelect;
  final void Function(List<Channel>)? onChannelContextChanged;
  final void Function(Channel, EpgProgram)? onScheduleProgram;
  final List<DvrRecording> dvrRecordings;
  final bool useSidebarLayout;
  final Future<List<EpgShow>> Function(String query)? onSearchShows;
  final void Function(EpgShow)? onShowSelect;

  @override
  Widget build(BuildContext context) {
    final epg = epgService ?? EpgService();
    return ProviderScope(
      overrides: [
        isBootstrappingProvider.overrideWith((_) => false),
        isConfiguredProvider.overrideWith((_) => isConfigured),
        isLoadingContentProvider.overrideWith((_) => isLoading),
        liveChannelsProvider.overrideWith((_) => channels),
        liveCategoriesProvider.overrideWith((_) => categories),
        epgServiceProvider.overrideWith((_) => epg),
        dvrRecordingsProvider.overrideWith((_) => dvrRecordings),
        recordingChannelIdsProvider.overrideWith(
          (_) => dvrRecordings
              .where((recording) => recording.isInProgress)
              .map((recording) => recording.channelId)
              .whereType<int>()
              .toSet(),
        ),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: ThemeData.dark(useMaterial3: true),
        home: LiveTvScreen(
          favoritesService: favoritesService ?? FavoritesService(),
          viewSettingsService: viewSettingsService,
          onChannelSelect: onChannelSelect ?? (_) {},
          useSidebarLayout: useSidebarLayout,
          onChannelContextChanged: onChannelContextChanged,
          onScheduleProgram: onScheduleProgram,
          onSearchShows: onSearchShows,
          onShowSelect: onShowSelect,
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/search/search_screen.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/providers/app_providers.dart';
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

    testWidgets(
      'tapping a channel reports the current search results as context',
      (tester) async {
        List<Channel>? reportedContext;

        await tester.pumpWidget(
          _TestApp(
            channels: testChannels,
            vodItems: testVodItems,
            seriesList: testSeriesList,
            onChannelContextChanged: (channels) => reportedContext = channels,
          ),
        );
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField), 'bbc');
        await tester.pumpAndSettle();
        await tester.tap(find.text('BBC News'));
        await tester.pumpAndSettle();

        expect(reportedContext, isNotNull);
        expect(reportedContext!.map((c) => c.id), [1]);
      },
    );

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

    // --- EPG show search wiring (#227) ---

    group('EPG show search', () {
      // Now/future-relative fixtures: `airingNow` must be within [start,
      // end]; `recentEpisodes` for the Upcoming row must be in the future.
      final now = DateTime.now();
      final pastStart = now.subtract(const Duration(minutes: 5));
      final pastEnd = now.add(const Duration(minutes: 30));
      final futureStart = now.add(const Duration(hours: 1));
      final futureEnd = futureStart.add(const Duration(minutes: 30));

      final onNowShow = EpgShow(
        normalizedTitle: 'nightly-report',
        displayTitle: 'Nightly Report',
        channelCount: 1,
        channels: const [],
        episodeCount: 1,
        recentEpisodes: const [],
        airingNow: [
          EpgShowEpisode(
            channelId: 1,
            channelName: 'BBC News',
            title: 'Nightly Report Episode',
            startTime: pastStart,
            endTime: pastEnd,
          ),
        ],
      );
      final upcomingShow = EpgShow(
        normalizedTitle: 'bear',
        displayTitle: 'Bear',
        channelCount: 1,
        channels: const [],
        episodeCount: 1,
        recentEpisodes: [
          EpgShowEpisode(
            channelId: 2,
            channelName: 'CNN International',
            title: 'Bear Episode',
            startTime: futureStart,
            endTime: futureEnd,
          ),
        ],
      );
      final showResults = [onNowShow, upcomingShow];

      Future<List<EpgShow>> Function(String) staticShows(
        List<EpgShow> results,
      ) {
        return (query) async => results;
      }

      testWidgets(
        'Live TV tab replaces channel list with On Now/Upcoming sub-tabs on '
        'qualifying query',
        (tester) async {
          await tester.pumpWidget(
            _TestApp(
              channels: testChannels,
              vodItems: testVodItems,
              seriesList: testSeriesList,
              onSearchShows: staticShows(showResults),
            ),
          );
          await tester.pumpAndSettle();

          await tester.enterText(find.byType(TextField), 'be');
          // Cross the 350ms debounce + the future async resolution.
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pumpAndSettle();

          // On the Live TV tab, the channel-name-filter list is gone,
          // replaced by the All/On Now/Upcoming sub-tab view.
          await tester.tap(
            find.descendant(
              of: find.byType(DpadTabBar),
              matching: find.text('Live TV'),
            ),
          );
          await tester.pumpAndSettle();

          // The outer SearchScreen DpadTabBar still has its 4 tabs
          // (All / Live TV / Movies / Series); ShowSearchResultsView
          // contributes a nested DpadTabBar for the sub-tabs.
          expect(find.byType(DpadTabBar), findsNWidgets(2));
          expect(find.text('All'), findsWidgets);
          expect(find.text('On Now'), findsOneWidget);
          expect(find.text('Upcoming'), findsOneWidget);
          // The channel-tile list is gone (ShowSearchResultsView replaced
          // it). ScrollbarListView is the new view's scroll container;
          // the old Live TV tab used a plain ListView.builder.
          expect(find.byType(ScrollbarListView), findsOneWidget);
        },
      );

      testWidgets(
        'Live TV tab renders EPG sub-tabs even when no channel name matches '
        'the query (regression guard for channel-list-source bug)',
        (tester) async {
          // Query "bear" matches no channel name (BBC News, CNN), no VOD
          // (Matrix…), no series (Breaking Bad…). Only the EPG show
          // "Bear" matches. Without the full-channels lookup, this test
          // would silently render the empty-state.
          await tester.pumpWidget(
            _TestApp(
              channels: testChannels,
              vodItems: testVodItems,
              seriesList: testSeriesList,
              onSearchShows: (query) async {
                return query == 'bear' ? showResults : const [];
              },
            ),
          );
          await tester.pumpAndSettle();

          await tester.enterText(find.byType(TextField), 'bear');
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pumpAndSettle();

          await tester.tap(
            find.descendant(
              of: find.byType(DpadTabBar),
              matching: find.text('Live TV'),
            ),
          );
          await tester.pumpAndSettle();

          // ShowSearchResultsView's nested DpadTabBar must be present.
          expect(find.text('On Now'), findsOneWidget);
          expect(find.text('Upcoming'), findsOneWidget);
          // The "Bear" show still appears in the upcoming results.
          expect(find.text('Bear'), findsOneWidget);
          // Empty-state must NOT be shown.
          expect(find.text('No results found'), findsNothing);
        },
      );

      testWidgets(
        'All tab renders On Now + Upcoming sections above the Live TV '
        'channel-match section for a qualifying query',
        (tester) async {
          await tester.pumpWidget(
            _TestApp(
              channels: testChannels,
              vodItems: testVodItems,
              seriesList: testSeriesList,
              onSearchShows: staticShows(showResults),
            ),
          );
          await tester.pumpAndSettle();

          await tester.enterText(find.byType(TextField), 'be');
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pumpAndSettle();

          // We're on All by default.
          expect(find.text('Nightly Report'), findsOneWidget);
          expect(find.text('Bear'), findsOneWidget);
          // Channel-name matches still appear below the EPG sections.
          expect(find.text('BBC News'), findsOneWidget);
        },
      );

      testWidgets(
        'All tab renders EPG sections when query matches no '
        'channel/VOD/series name but matches a show (regression guard '
        'for empty-state-guard bug)',
        (tester) async {
          // Query "bear" matches only the EPG show "Bear"; no channel
          // name, VOD name, or series name contains "bear". Without the
          // empty-state-guard fix, the EPG sections would be hidden by
          // the "all empty -> show empty state" early-return.
          await tester.pumpWidget(
            _TestApp(
              channels: testChannels,
              vodItems: testVodItems,
              seriesList: testSeriesList,
              onSearchShows: (query) async {
                return query == 'bear' ? showResults : const [];
              },
            ),
          );
          await tester.pumpAndSettle();

          await tester.enterText(find.byType(TextField), 'bear');
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pumpAndSettle();

          expect(find.text('Bear'), findsOneWidget);
          // Empty-state must NOT be shown.
          expect(find.text('No results found'), findsNothing);
        },
      );

      testWidgets(
        'tapping an On Now row calls onChannelContextChanged then '
        'onChannelSelect with the right channel',
        (tester) async {
          List<Channel>? reportedContext;
          Channel? selectedChannel;

          await tester.pumpWidget(
            _TestApp(
              channels: testChannels,
              vodItems: testVodItems,
              seriesList: testSeriesList,
              onSearchShows: staticShows(showResults),
              onChannelSelect: (channel) => selectedChannel = channel,
              onChannelContextChanged: (channels) => reportedContext = channels,
            ),
          );
          await tester.pumpAndSettle();

          await tester.enterText(find.byType(TextField), 'be');
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pumpAndSettle();

          await tester.tap(find.text('Nightly Report'));
          await tester.pumpAndSettle();

          expect(reportedContext, isNotNull);
          expect(reportedContext!.map((c) => c.id), [1]);
          expect(selectedChannel?.id, 1);
        },
      );

      testWidgets(
        'tapping an Upcoming row calls onShowSelect with the parent show',
        (tester) async {
          EpgShow? selectedShow;

          await tester.pumpWidget(
            _TestApp(
              channels: testChannels,
              vodItems: testVodItems,
              seriesList: testSeriesList,
              onSearchShows: staticShows(showResults),
              onShowSelect: (show) => selectedShow = show,
            ),
          );
          await tester.pumpAndSettle();

          await tester.enterText(find.byType(TextField), 'be');
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pumpAndSettle();

          await tester.tap(find.text('Bear'));
          await tester.pumpAndSettle();

          expect(selectedShow, isNotNull);
          expect(selectedShow!.normalizedTitle, 'bear');
        },
      );

      testWidgets(
        'null onSearchShows keeps the channel-name results; no EPG '
        'sections/sub-tabs anywhere',
        (tester) async {
          await tester.pumpWidget(
            _TestApp(
              channels: testChannels,
              vodItems: testVodItems,
              seriesList: testSeriesList,
              // No onSearchShows callback - the screen should behave
              // exactly like pre-#227.
            ),
          );
          await tester.pumpAndSettle();

          await tester.enterText(find.byType(TextField), 'bbc');
          await tester.pumpAndSettle();

          // Only one DpadTabBar (the screen's outer one) - no nested
          // sub-tabs from ShowSearchResultsView.
          expect(find.byType(DpadTabBar), findsOneWidget);
          // No EPG section headers rendered.
          expect(find.text('On Now'), findsNothing);
          expect(find.text('Upcoming'), findsNothing);
          // Channel-name filter still works.
          expect(find.text('BBC News'), findsOneWidget);
        },
      );

      testWidgets(
        'Movies and Series tabs are unaffected by EPG show search wiring',
        (tester) async {
          await tester.pumpWidget(
            _TestApp(
              channels: testChannels,
              vodItems: testVodItems,
              seriesList: testSeriesList,
              onSearchShows: staticShows(showResults),
            ),
          );
          await tester.pumpAndSettle();

          // Movies tab: a query matching VOD items only.
          await tester.enterText(find.byType(TextField), 'matrix');
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pumpAndSettle();

          await tester.tap(
            find.descendant(
              of: find.byType(DpadTabBar),
              matching: find.text('Movies'),
            ),
          );
          await tester.pumpAndSettle();
          // The Movies tab still shows the VOD matches; the EPG show
          // search results are scoped to All/Live TV only.
          expect(find.text('The Matrix'), findsOneWidget);
          expect(find.text('Nightly Report'), findsNothing);
          expect(find.text('Bear'), findsNothing);

          // Series tab: a different query matching series.
          await tester.enterText(find.byType(TextField), 'bad');
          await tester.pump(const Duration(milliseconds: 400));
          await tester.pumpAndSettle();

          await tester.tap(
            find.descendant(
              of: find.byType(DpadTabBar),
              matching: find.text('Series'),
            ),
          );
          await tester.pumpAndSettle();
          expect(find.text('Breaking Bad'), findsOneWidget);
          expect(find.text('Nightly Report'), findsNothing);
          expect(find.text('Bear'), findsNothing);
        },
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
    this.onChannelContextChanged,
    this.onVodSelect,
    this.onSeriesSelect,
    this.onSearchShows,
    this.onShowSelect,
  });

  final List<Channel> channels;
  final List<VodItem> vodItems;
  final List<Series> seriesList;
  final bool isConfigured;
  final void Function(Channel)? onChannelSelect;
  final void Function(List<Channel>)? onChannelContextChanged;
  final void Function(VodItem)? onVodSelect;
  final void Function(Series)? onSeriesSelect;
  final Future<List<EpgShow>> Function(String)? onSearchShows;
  final void Function(EpgShow)? onShowSelect;

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        isBootstrappingProvider.overrideWith((_) => false),
        isConfiguredProvider.overrideWith((_) => isConfigured),
        liveChannelsProvider.overrideWith((_) => channels),
        vodItemsProvider.overrideWith((_) => vodItems),
        seriesListProvider.overrideWith((_) => seriesList),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: ThemeData.dark(useMaterial3: true),
        home: SearchScreen(
          onChannelSelect: onChannelSelect ?? (_) {},
          onChannelContextChanged: onChannelContextChanged,
          onVodSelect: onVodSelect ?? (_) {},
          onSeriesSelect: onSeriesSelect ?? (_) {},
          onSearchShows: onSearchShows,
          onShowSelect: onShowSelect,
        ),
      ),
    );
  }
}

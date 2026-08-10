import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
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
import 'package:m3u_tv/shared/media_browsing_widgets.dart';

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
          onChannelContextChanged: onChannelContextChanged,
          onScheduleProgram: onScheduleProgram,
        ),
      ),
    );
  }
}

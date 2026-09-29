import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/epg/timeline_epg_view.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/epg_service.dart';
import 'package:m3u_tv/services/view_settings_service.dart';

void main() {
  final observesBerlinDst =
      DateTime(2026, 3, 29).timeZoneOffset == const Duration(hours: 1) &&
      DateTime(2026, 3, 30).timeZoneOffset == const Duration(hours: 2) &&
      DateTime(2026, 10, 25).timeZoneOffset == const Duration(hours: 2) &&
      DateTime(2026, 10, 26).timeZoneOffset == const Duration(hours: 1);

  const bbcOne = Channel(
    id: 101,
    name: 'BBC One',
    streamUrl: 'https://streams.example/live/101.m3u8',
    epgChannelId: 'bbc.one',
    catchupSupported: true,
    catchupDays: 7,
  );

  Future<void> pumpGuide(
    WidgetTester tester, {
    required List<Channel> channels,
    required EpgService epgService,
    DateTime Function()? clock,
    void Function(Channel)? onChannelSelect,
    CatchupProgramSelect? onCatchupProgramSelect,
    CatchupProgramSelect? onChannelLongPress,
    EnsureEpg? onEnsureEpg,
    EpgStartView epgStartView = EpgStartView.currentTime,
    int futureDays = 7,
    bool showPreview = false,
    bool tapOpensDetails = false,
    double width = 800,
    double height = 300,
    bool inRegion = false,
    Key? guideKey,
    VoidCallback? onCursorMove,
  }) async {
    Widget guide = SizedBox(
      width: width,
      height: height,
      child: TimelineEpgView(
        key: guideKey,
        channels: channels,
        epgService: epgService,
        onChannelSelect: onChannelSelect ?? (_) {},
        onCatchupProgramSelect: onCatchupProgramSelect,
        onChannelLongPress: onChannelLongPress,
        onEnsureEpg: onEnsureEpg,
        epgStartView: epgStartView,
        futureDays: futureDays,
        showPreview: showPreview,
        tapOpensDetails: tapOpensDetails,
        clock: clock ?? DateTime.now,
        onCursorMove: onCursorMove,
      ),
    );
    if (inRegion) {
      // Matches the production wrapping in live_tv_screen.dart's
      // `_buildEpgGrid` (`horizontalEdge: stop`).
      guide = DpadRegion(horizontalEdge: DpadEdgeBehavior.stop, child: guide);
    }
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Align(alignment: Alignment.topLeft, child: guide),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Finder programCell(EpgProgram program) => find.byKey(
    ValueKey(
      'timeline-program-${program.channelId}-'
      '${program.start.toIso8601String()}',
    ),
  );

  bool cursorOn(Finder cell) => find
      .descendant(
        of: cell,
        matching: find.byKey(const ValueKey('timeline-cursor')),
      )
      .evaluate()
      .isNotEmpty;

  final anyProgramCell = find.byWidgetPredicate((widget) {
    final key = widget.key;
    return key is ValueKey<String> && key.value.startsWith('timeline-program-');
  });

  bool cursorOnChannelCell() {
    final rings = find.byKey(const ValueKey('timeline-cursor'));
    if (rings.evaluate().length != 1) return false;
    return find
        .descendant(of: anyProgramCell, matching: rings)
        .evaluate()
        .isEmpty;
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  group('TimelineEpgView', () {
    testWidgets('catchup channels show replay availability indicator', (
      tester,
    ) async {
      await pumpGuide(
        tester,
        channels: const [
          bbcOne,
          Channel(
            id: 102,
            name: 'BBC Two',
            streamUrl: 'https://streams.example/live/102.m3u8',
          ),
        ],
        epgService: EpgService(),
      );

      expect(find.byIcon(Icons.replay_rounded), findsOneWidget);
      expect(find.text('7d'), findsOneWidget);
    });

    testWidgets(
      'past programs on catchup channels render per-program replay icon',
      (tester) async {
        final now = DateTime.now();
        final pastProgram = EpgProgram(
          channelId: 'bbc.one',
          title: 'Archived Show',
          description: 'Replayable fixture',
          start: now.subtract(const Duration(minutes: 60)),
          end: now.subtract(const Duration(minutes: 30)),
        );
        final futureProgram = EpgProgram(
          channelId: 'bbc.one',
          title: 'Upcoming Show',
          description: 'Future fixture',
          start: now.add(const Duration(minutes: 30)),
          end: now.add(const Duration(minutes: 60)),
        );
        await pumpGuide(
          tester,
          channels: const [bbcOne],
          epgService: EpgService()..loadPrograms([pastProgram, futureProgram]),
        );

        // One from the channel's catchup badge, one on the past programme.
        expect(find.byIcon(Icons.replay_rounded), findsNWidgets(2));
        expect(
          find.descendant(
            of: programCell(pastProgram),
            matching: find.byIcon(Icons.replay_rounded),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: programCell(futureProgram),
            matching: find.byIcon(Icons.replay_rounded),
          ),
          findsNothing,
        );
      },
    );

    testWidgets(
      'past programs on non-catchup channels do not render per-program replay icon',
      (tester) async {
        final now = DateTime.now();
        await pumpGuide(
          tester,
          channels: const [
            Channel(
              id: 102,
              name: 'BBC Two',
              streamUrl: 'https://streams.example/live/102.m3u8',
              epgChannelId: 'bbc.two',
            ),
          ],
          epgService: EpgService()
            ..loadPrograms([
              EpgProgram(
                channelId: 'bbc.two',
                title: 'Old Show',
                description: 'Not replayable',
                start: now.subtract(const Duration(minutes: 60)),
                end: now.subtract(const Duration(minutes: 30)),
              ),
            ]),
        );

        expect(find.byIcon(Icons.replay_rounded), findsNothing);
      },
    );

    testWidgets('placeholder programmes read as no data, not the channel', (
      tester,
    ) async {
      final now = DateTime(2026, 7, 31, 12);
      await pumpGuide(
        tester,
        clock: () => now,
        channels: const [bbcOne],
        epgService: EpgService(clock: () => now)
          ..loadPrograms([
            EpgProgram(
              channelId: 'bbc.one',
              title: 'BBC One',
              description: 'No information available',
              start: DateTime(2026, 7, 31, 11, 30),
              end: DateTime(2026, 7, 31, 12, 30),
              isPlaceholder: true,
            ),
          ]),
      );

      expect(find.text('No EPG data'), findsOneWidget);
      expect(find.text('BBC One'), findsNothing);
    });

    testWidgets('navigates days, displays the date, and returns to now', (
      tester,
    ) async {
      final now = DateTime(2026, 7, 31, 12);
      final requestedDates = <DateTime>[];
      await pumpGuide(
        tester,
        clock: () => now,
        channels: const [bbcOne],
        epgService: EpgService(clock: () => now),
        onEnsureEpg: (channels, {startDate, endDate}) {
          requestedDates.add(startDate!);
        },
      );

      expect(find.text('Jul 31, 2026'), findsOneWidget);
      expect(find.text('Today'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('timeline-previous-day')));
      await tester.pump();
      expect(find.text('Jul 30, 2026'), findsOneWidget);
      expect(find.text('Yesterday'), findsOneWidget);
      expect(requestedDates.last, DateTime(2026, 7, 30));

      await tester.tap(find.byKey(const ValueKey('timeline-next-day')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('timeline-next-day')));
      await tester.pump();
      expect(find.text('Aug 1, 2026'), findsOneWidget);
      expect(find.text('Tomorrow'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('timeline-now')));
      await tester.pump();
      expect(find.text('Jul 31, 2026'), findsOneWidget);
      expect(requestedDates.last, DateTime(2026, 7, 31));

      for (var day = 0; day < 8; day += 1) {
        await tester.tap(find.byKey(const ValueKey('timeline-previous-day')));
        await tester.pump();
      }
      expect(find.text('Jul 24, 2026'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('timeline-now')));
      await tester.pump();
      for (var day = 0; day < 8; day += 1) {
        await tester.tap(find.byKey(const ValueKey('timeline-next-day')));
        await tester.pump();
      }
      expect(find.text('Aug 7, 2026'), findsOneWidget);

      for (final key in const [
        ValueKey('timeline-previous-day'),
        ValueKey('timeline-now'),
        ValueKey('timeline-next-day'),
      ]) {
        expect(
          find.descendant(
            of: find.byKey(key),
            matching: find.byType(DpadFocusable),
          ),
          findsOneWidget,
        );
      }
    });

    testWidgets('requests EPG for a look-ahead window past the visible rows', (
      tester,
    ) async {
      final now = DateTime(2026, 7, 31, 12);
      final channels = <Channel>[
        for (var i = 1; i <= 40; i += 1)
          Channel(
            id: i,
            name: 'Channel $i',
            streamUrl: 'https://streams.example/live/$i.m3u8',
            epgChannelId: 'chan.$i',
          ),
      ];
      final requestedIndexes = <int>{};
      var sawMultiChannelBatch = false;

      await pumpGuide(
        tester,
        clock: () => now,
        channels: channels,
        epgService: EpgService(clock: () => now),
        onEnsureEpg: (batch, {startDate, endDate}) {
          if (batch.length > 1) sawMultiChannelBatch = true;
          for (final channel in batch) {
            requestedIndexes.add(channel.id - 1);
          }
        },
      );

      // Each built row also queues a forward slice, so the guide asks for
      // channels well beyond the handful that fit on screen.
      expect(sawMultiChannelBatch, isTrue);
      expect(
        requestedIndexes.reduce((a, b) => a > b ? a : b),
        greaterThanOrEqualTo(20),
      );
    });

    testWidgets('null catchup metadata uses a finite seven-day retention', (
      tester,
    ) async {
      final now = DateTime(2026, 7, 31, 12);
      final olderProgram = EpgProgram(
        channelId: 'bbc.one',
        title: 'Outside Fallback',
        description: 'Started before the fallback cutoff',
        start: DateTime(2026, 7, 24, 10),
        end: DateTime(2026, 7, 24, 11),
      );
      final retainedProgram = EpgProgram(
        channelId: 'bbc.one',
        title: 'Inside Fallback',
        description: 'Started after the fallback cutoff',
        start: DateTime(2026, 7, 24, 13),
        end: DateTime(2026, 7, 24, 14),
      );
      final replayedPrograms = <EpgProgram>[];
      final selectedChannels = <Channel>[];

      await pumpGuide(
        tester,
        clock: () => now,
        channels: const [
          Channel(
            id: 101,
            name: 'BBC One',
            streamUrl: 'https://streams.example/live/101.m3u8',
            epgChannelId: 'bbc.one',
            catchupSupported: true,
          ),
          Channel(
            id: 102,
            name: 'Short Archive',
            streamUrl: 'https://streams.example/live/102.m3u8',
            catchupSupported: true,
            catchupDays: 2,
          ),
          Channel(
            id: 103,
            name: 'No Archive',
            streamUrl: 'https://streams.example/live/103.m3u8',
          ),
        ],
        epgService: EpgService(clock: () => now)
          ..loadPrograms([olderProgram, retainedProgram]),
        onChannelSelect: selectedChannels.add,
        onCatchupProgramSelect: (_, program) => replayedPrograms.add(program),
      );

      for (var day = 0; day < 7; day += 1) {
        await tester.tap(find.byKey(const ValueKey('timeline-previous-day')));
        await tester.pump();
      }
      expect(find.text('Jul 24, 2026'), findsOneWidget);
      expect(
        _dateControlFocusable(
          tester,
          const ValueKey('timeline-previous-day'),
        ).enabled,
        isFalse,
      );
      await tester.tap(find.byKey(const ValueKey('timeline-previous-day')));
      await tester.pump();
      expect(find.text('Jul 24, 2026'), findsOneWidget);

      expect(
        find.descendant(
          of: programCell(retainedProgram),
          matching: find.byIcon(Icons.replay_rounded),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: programCell(olderProgram),
          matching: find.byIcon(Icons.replay_rounded),
        ),
        findsNothing,
      );

      // OK on each block via the guide cursor: the older one is outside
      // the retention window, so only the retained one replays.
      await tester.pumpAndSettle();
      final grid = find.byWidgetPredicate(
        (widget) => widget is DpadFocusable && widget.debugLabel == 'epg-guide',
      );
      tester.widget<DpadFocusable>(grid).focusNode!.requestFocus();
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(cursorOn(programCell(olderProgram)), isTrue);
      await press(tester, LogicalKeyboardKey.select);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(cursorOn(programCell(retainedProgram)), isTrue);
      await press(tester, LogicalKeyboardKey.select);

      expect(replayedPrograms, [retainedProgram]);
      expect(selectedChannels, isEmpty);
    });

    testWidgets('zero and negative catchup retention remain unavailable', (
      tester,
    ) async {
      final now = DateTime(2026, 7, 31, 12);
      final programs = [
        EpgProgram(
          channelId: 'zero',
          title: 'Zero Archive',
          description: 'Unavailable with zero retention',
          start: DateTime(2026, 7, 31, 10),
          end: DateTime(2026, 7, 31, 11),
        ),
        EpgProgram(
          channelId: 'negative',
          title: 'Negative Archive',
          description: 'Unavailable with negative retention',
          start: DateTime(2026, 7, 31, 10),
          end: DateTime(2026, 7, 31, 11),
        ),
      ];
      final replayedPrograms = <EpgProgram>[];
      final selectedChannels = <Channel>[];

      await pumpGuide(
        tester,
        clock: () => now,
        channels: const [
          Channel(
            id: 101,
            name: 'Zero',
            streamUrl: 'https://streams.example/live/101.m3u8',
            epgChannelId: 'zero',
            catchupSupported: true,
            catchupDays: 0,
          ),
          Channel(
            id: 102,
            name: 'Negative',
            streamUrl: 'https://streams.example/live/102.m3u8',
            epgChannelId: 'negative',
            catchupSupported: true,
            catchupDays: -1,
          ),
        ],
        epgService: EpgService(clock: () => now)..loadPrograms(programs),
        onChannelSelect: selectedChannels.add,
        onCatchupProgramSelect: (_, program) => replayedPrograms.add(program),
      );

      expect(
        _dateControlFocusable(
          tester,
          const ValueKey('timeline-previous-day'),
        ).enabled,
        isFalse,
      );
      for (final program in programs) {
        expect(
          find.descendant(
            of: programCell(program),
            matching: find.byIcon(Icons.replay_rounded),
          ),
          findsNothing,
        );
      }

      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(cursorOn(programCell(programs[0])), isTrue);
      await press(tester, LogicalKeyboardKey.select);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(cursorOn(programCell(programs[1])), isTrue);
      await press(tester, LogicalKeyboardKey.select);

      expect(replayedPrograms, isEmpty);
      expect(selectedChannels, isEmpty);
    });

    testWidgets(
      'spring-forward navigation and window keep calendar boundaries',
      (tester) async {
        final now = DateTime(2026, 3, 30, 12);
        await pumpGuide(
          tester,
          clock: () => now,
          // Prime time puts the late-evening programmes on screen.
          epgStartView: EpgStartView.primeTime,
          channels: const [bbcOne],
          epgService: EpgService(clock: () => now)
            ..loadPrograms([
              EpgProgram(
                channelId: 'bbc.one',
                title: 'Late Sunday',
                description: 'Inside Sunday',
                start: DateTime(2026, 3, 29, 23, 30),
                end: DateTime(2026, 3, 29, 23, 50),
              ),
              EpgProgram(
                channelId: 'bbc.one',
                title: 'Early Monday',
                description: 'Outside Sunday',
                start: DateTime(2026, 3, 30, 0, 15),
                end: DateTime(2026, 3, 30, 0, 45),
              ),
            ]),
        );

        await tester.tap(find.byKey(const ValueKey('timeline-previous-day')));
        await tester.pumpAndSettle();

        expect(find.text('Mar 29, 2026'), findsOneWidget);
        expect(find.text('Late Sunday'), findsOneWidget);
        expect(find.text('Early Monday'), findsNothing);
      },
      skip: !observesBerlinDst,
    );

    testWidgets(
      'fall-back navigation and window keep calendar boundaries',
      (tester) async {
        final now = DateTime(2026, 10, 24, 12);
        await pumpGuide(
          tester,
          clock: () => now,
          epgStartView: EpgStartView.primeTime,
          channels: const [bbcOne],
          epgService: EpgService(clock: () => now)
            ..loadPrograms([
              EpgProgram(
                channelId: 'bbc.one',
                title: 'Late Sunday',
                description: 'Inside Sunday',
                start: DateTime(2026, 10, 25, 23, 30),
                end: DateTime(2026, 10, 25, 23, 50),
              ),
            ]),
        );

        await tester.tap(find.byKey(const ValueKey('timeline-next-day')));
        await tester.pumpAndSettle();
        expect(find.text('Oct 25, 2026'), findsOneWidget);
        expect(find.text('Late Sunday'), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('timeline-next-day')));
        await tester.pumpAndSettle();
        expect(find.text('Oct 26, 2026'), findsOneWidget);
        expect(find.text('Late Sunday'), findsNothing);
      },
      skip: !observesBerlinDst,
    );

    testWidgets('keeps horizontal pointer scrolling available', (tester) async {
      final now = DateTime(2026, 7, 31, 12);
      await pumpGuide(
        tester,
        clock: () => now,
        channels: const [bbcOne],
        epgService: EpgService(clock: () => now),
      );

      final before = _horizontalScrollOffset(tester);
      await tester.drag(find.byType(TimelineEpgView), const Offset(-300, 0));
      await tester.pumpAndSettle();

      expect(_horizontalScrollOffset(tester), greaterThan(before));
    });

    testWidgets('date controls traverse and activate with D-pad keys', (
      tester,
    ) async {
      final now = DateTime(2026, 7, 31, 12);
      await pumpGuide(
        tester,
        clock: () => now,
        inRegion: true,
        channels: const [bbcOne],
        epgService: EpgService(clock: () => now),
      );

      // The programme grid is the default landing focus; move to the day
      // toolbar explicitly before exercising its key sequences.
      _dateControlFocusable(
        tester,
        const ValueKey('timeline-previous-day'),
      ).focusNode?.requestFocus();
      await tester.pump();

      await press(tester, LogicalKeyboardKey.select);
      expect(find.text('Jul 30, 2026'), findsOneWidget);

      await press(tester, LogicalKeyboardKey.arrowRight);
      await press(tester, LogicalKeyboardKey.select);
      expect(find.text('Jul 31, 2026'), findsOneWidget);
      await press(tester, LogicalKeyboardKey.select);
      expect(find.text('Aug 1, 2026'), findsOneWidget);

      await press(tester, LogicalKeyboardKey.arrowRight);
      await press(tester, LogicalKeyboardKey.select);
      expect(find.text('Jul 31, 2026'), findsOneWidget);

      await press(tester, LogicalKeyboardKey.arrowLeft);
      await press(tester, LogicalKeyboardKey.select);
      expect(find.text('Aug 1, 2026'), findsOneWidget);
    });

    testWidgets('D-pad skips disabled previous control at catchup boundary', (
      tester,
    ) async {
      final now = DateTime(2026, 7, 31, 12);
      await pumpGuide(
        tester,
        clock: () => now,
        inRegion: true,
        channels: const [
          Channel(
            id: 101,
            name: 'BBC One',
            streamUrl: 'https://streams.example/live/101.m3u8',
            catchupSupported: true,
            catchupDays: 0,
          ),
        ],
        epgService: EpgService(clock: () => now),
      );

      expect(
        _dateControlFocusable(
          tester,
          const ValueKey('timeline-previous-day'),
        ).enabled,
        isFalse,
      );
      final next = _dateControlFocusable(
        tester,
        const ValueKey('timeline-next-day'),
      );
      next.focusNode?.requestFocus();
      await tester.pump();

      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(next.focusNode?.hasFocus, isTrue);
      await press(tester, LogicalKeyboardKey.select);
      expect(find.text('Aug 1, 2026'), findsOneWidget);

      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(
        _dateControlFocusable(
          tester,
          const ValueKey('timeline-now'),
        ).focusNode?.hasFocus,
        isTrue,
      );
      await press(tester, LogicalKeyboardKey.select);
      expect(find.text('Jul 31, 2026'), findsOneWidget);
    });

    testWidgets('D-pad skips disabled next control at future boundary', (
      tester,
    ) async {
      final now = DateTime(2026, 7, 31, 12);
      await pumpGuide(
        tester,
        clock: () => now,
        inRegion: true,
        futureDays: 0,
        channels: const [bbcOne],
        epgService: EpgService(clock: () => now),
      );

      expect(
        _dateControlFocusable(
          tester,
          const ValueKey('timeline-next-day'),
        ).enabled,
        isFalse,
      );
      _dateControlFocusable(
        tester,
        const ValueKey('timeline-previous-day'),
      ).focusNode?.requestFocus();
      await tester.pump();

      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(
        _dateControlFocusable(
          tester,
          const ValueKey('timeline-now'),
        ).focusNode?.hasFocus,
        isTrue,
      );
      await press(tester, LogicalKeyboardKey.select);
      expect(find.text('Jul 31, 2026'), findsOneWidget);

      await press(tester, LogicalKeyboardKey.arrowLeft);
      await press(tester, LogicalKeyboardKey.select);
      expect(find.text('Jul 30, 2026'), findsOneWidget);
    });

    testWidgets('replay stays bounded by each channel catchup range', (
      tester,
    ) async {
      final now = DateTime(2026, 7, 31, 12);
      final shortProgram = EpgProgram(
        channelId: 'short',
        title: 'Short Archive',
        description: 'Outside one-day archive',
        start: DateTime(2026, 7, 28, 10),
        end: DateTime(2026, 7, 28, 11),
      );
      final longProgram = EpgProgram(
        channelId: 'long',
        title: 'Long Archive',
        description: 'Inside seven-day archive',
        start: DateTime(2026, 7, 28, 10),
        end: DateTime(2026, 7, 28, 11),
      );
      await pumpGuide(
        tester,
        clock: () => now,
        channels: const [
          Channel(
            id: 101,
            name: 'Short',
            streamUrl: 'https://streams.example/live/101.m3u8',
            epgChannelId: 'short',
            catchupSupported: true,
            catchupDays: 1,
          ),
          Channel(
            id: 102,
            name: 'Long',
            streamUrl: 'https://streams.example/live/102.m3u8',
            epgChannelId: 'long',
            catchupSupported: true,
            catchupDays: 7,
          ),
        ],
        epgService: EpgService(clock: () => now)
          ..loadPrograms([shortProgram, longProgram]),
      );
      for (var day = 0; day < 3; day += 1) {
        await tester.tap(find.byKey(const ValueKey('timeline-previous-day')));
        await tester.pump();
      }
      await tester.pumpAndSettle();

      expect(
        find.descendant(
          of: programCell(shortProgram),
          matching: find.byIcon(Icons.replay_rounded),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: programCell(longProgram),
          matching: find.byIcon(Icons.replay_rounded),
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      're-initializes horizontal scroll offset when epgStartView prop changes',
      (tester) async {
        final now = DateTime(2026, 7, 31, 14, 30);
        await pumpGuide(
          tester,
          clock: () => now,
          channels: const [bbcOne],
          epgService: EpgService(clock: () => now),
        );
        final currentOffset = _horizontalScrollOffset(tester);

        await pumpGuide(
          tester,
          clock: () => now,
          epgStartView: EpgStartView.primeTime,
          channels: const [bbcOne],
          epgService: EpgService(clock: () => now),
        );

        expect(_horizontalScrollOffset(tester), isNot(currentOffset));
      },
    );

    testWidgets('day navigation keeps the prime-time scroll offset', (
      tester,
    ) async {
      final now = DateTime(2026, 7, 31, 14, 30);
      await pumpGuide(
        tester,
        clock: () => now,
        epgStartView: EpgStartView.primeTime,
        channels: const [bbcOne],
        epgService: EpgService(clock: () => now),
      );
      final initialOffset = _horizontalScrollOffset(tester);

      await tester.tap(find.byKey(const ValueKey('timeline-next-day')));
      await tester.pumpAndSettle();

      expect(_horizontalScrollOffset(tester), initialOffset);
    });
  });

  group('TimelineEpgView D-pad cursor', () {
    final now = DateTime(2026, 7, 31, 12);
    const channelA = Channel(
      id: 1,
      name: 'Alpha',
      streamUrl: 'https://streams.example/live/1.m3u8',
      epgChannelId: 'alpha',
    );
    const channelB = Channel(
      id: 2,
      name: 'Bravo',
      streamUrl: 'https://streams.example/live/2.m3u8',
      epgChannelId: 'bravo',
    );
    const channelC = Channel(
      id: 3,
      name: 'Charlie',
      streamUrl: 'https://streams.example/live/3.m3u8',
      epgChannelId: 'charlie',
    );
    EpgProgram program(String channel, String title, DateTime s, DateTime e) =>
        EpgProgram(
          channelId: channel,
          title: title,
          description: '$title description',
          start: s,
          end: e,
        );
    DateTime at(int hour, [int minute = 0]) =>
        DateTime(2026, 7, 31, hour, minute);

    final a1 = program('alpha', 'A1', at(11, 30), at(12, 30));
    final a2 = program('alpha', 'A2', at(12, 30), at(13));
    final b1 = program('bravo', 'B1', at(11), at(12, 10));
    final b2 = program('bravo', 'B2', at(12, 10), at(13));
    final c1 = program('charlie', 'C1', at(11, 50), at(12, 40));

    EpgService service() =>
        EpgService(clock: () => now)..loadPrograms([a1, a2, b1, b2, c1]);

    testWidgets('lands on the channel, then steps through programmes', (
      tester,
    ) async {
      await pumpGuide(
        tester,
        clock: () => now,
        channels: const [channelA, channelB, channelC],
        epgService: service(),
      );

      expect(cursorOnChannelCell(), isTrue);

      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(cursorOn(programCell(a1)), isTrue, reason: 'enters on "now"');

      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(cursorOn(programCell(a2)), isTrue);

      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(cursorOn(programCell(a1)), isTrue);

      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(cursorOnChannelCell(), isTrue);
    });

    testWidgets('up and down keep the same time column', (tester) async {
      await pumpGuide(
        tester,
        clock: () => now,
        channels: const [channelA, channelB, channelC],
        epgService: service(),
      );

      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(cursorOn(programCell(a1)), isTrue);

      // Anchored on "now" (12:00) while on live programmes.
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(cursorOn(programCell(b1)), isTrue);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(cursorOn(programCell(c1)), isTrue);
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(cursorOn(programCell(b1)), isTrue);

      // Moving right re-anchors on B2's start (12:10), which A1 covers.
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(cursorOn(programCell(b2)), isTrue);
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(cursorOn(programCell(a1)), isTrue);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(cursorOn(programCell(b2)), isTrue);
    });

    testWidgets('OK plays live, replays catchup and opens upcoming options', (
      tester,
    ) async {
      final selected = <Channel>[];
      final options = <EpgProgram>[];
      await pumpGuide(
        tester,
        clock: () => now,
        channels: const [channelA, channelB, channelC],
        epgService: service(),
        onChannelSelect: selected.add,
        onChannelLongPress: (_, program) => options.add(program),
      );

      // On the channel cell: tune the channel.
      await press(tester, LogicalKeyboardKey.select);
      expect(selected, [channelA]);

      // On a live programme: tune the channel.
      await press(tester, LogicalKeyboardKey.arrowRight);
      await press(tester, LogicalKeyboardKey.select);
      expect(selected, [channelA, channelA]);

      // On an upcoming programme: open its options instead of playing.
      await press(tester, LogicalKeyboardKey.arrowRight);
      await press(tester, LogicalKeyboardKey.select);
      expect(options, [a2]);
      expect(selected, hasLength(2));
    });

    testWidgets('right past the last programme moves to the next day', (
      tester,
    ) async {
      final lateNow = DateTime(2026, 7, 31, 21, 30);
      final tonight = program('alpha', 'Tonight', at(22), DateTime(2026, 8));
      final tomorrow = program(
        'alpha',
        'Tomorrow Early',
        DateTime(2026, 8),
        DateTime(2026, 8, 1, 1),
      );
      await pumpGuide(
        tester,
        clock: () => lateNow,
        channels: const [channelA],
        epgService: EpgService(clock: () => lateNow)
          ..loadPrograms([tonight, tomorrow]),
      );

      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(cursorOn(programCell(tonight)), isTrue);

      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(find.text('Aug 1, 2026'), findsOneWidget);
      expect(cursorOn(programCell(tomorrow)), isTrue);
    });

    testWidgets('reports cursor moves, but not presses that go nowhere', (
      tester,
    ) async {
      var moves = 0;
      await pumpGuide(
        tester,
        clock: () => now,
        channels: const [channelA, channelB],
        epgService: service(),
        onCursorMove: () => moves += 1,
      );

      await press(tester, LogicalKeyboardKey.arrowRight);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(moves, 2);

      // Already on the last row: consumed, but nothing moved.
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(moves, 2);
    });

    testWidgets('Back returns to the channel, then falls through', (
      tester,
    ) async {
      final key = GlobalKey<TimelineEpgViewState>();
      await pumpGuide(
        tester,
        guideKey: key,
        clock: () => now,
        channels: const [channelA, channelB],
        epgService: service(),
      );

      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(cursorOn(programCell(a1)), isTrue);

      expect(key.currentState!.handleBack(), isTrue);
      await tester.pumpAndSettle();
      expect(cursorOnChannelCell(), isTrue);

      // Already on the channel: let the shell handle Back (sidebar/exit).
      expect(key.currentState!.handleBack(), isFalse);
    });

    testWidgets('up on the day toolbar stays put under the preview panel', (
      tester,
    ) async {
      await pumpGuide(
        tester,
        clock: () => now,
        inRegion: true,
        showPreview: true,
        height: 600,
        channels: const [channelA, channelB],
        epgService: service(),
      );

      final nowButton = _dateControlFocusable(
        tester,
        const ValueKey('timeline-now'),
      );
      nowButton.focusNode?.requestFocus();
      await tester.pump();

      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(nowButton.focusNode?.hasFocus, isTrue);

      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(cursorOnChannelCell(), isTrue);
    });

    testWidgets('up from the top row moves focus to the day toolbar', (
      tester,
    ) async {
      await pumpGuide(
        tester,
        clock: () => now,
        inRegion: true,
        channels: const [channelA, channelB],
        epgService: service(),
      );

      await press(tester, LogicalKeyboardKey.arrowUp);

      final toolbarFocused =
          [
            const ValueKey('timeline-previous-day'),
            const ValueKey('timeline-now'),
            const ValueKey('timeline-next-day'),
          ].any(
            (key) =>
                _dateControlFocusable(tester, key).focusNode?.hasFocus ?? false,
          );
      expect(toolbarFocused, isTrue);
    });
  });

  group('TimelineEpgView details', () {
    final now = DateTime(2026, 7, 31, 12);
    final richProgram = EpgProgram(
      channelId: 'bbc.one',
      title: 'Detective Show',
      subtitle: 'The Final Clue',
      description: 'Our heroes crack the case at last.',
      start: DateTime(2026, 7, 31, 11, 30),
      end: DateTime(2026, 7, 31, 12, 30),
      category: 'Drama',
      rating: 'TV-14',
      season: 2,
      episode: 5,
      isNew: true,
    );

    testWidgets('preview panel shows the programme under the cursor', (
      tester,
    ) async {
      await pumpGuide(
        tester,
        clock: () => now,
        showPreview: true,
        width: 1200,
        height: 800,
        channels: const [bbcOne],
        epgService: EpgService(clock: () => now)..loadPrograms([richProgram]),
      );

      expect(find.text('Detective Show'), findsOneWidget);
      expect(find.text('S2 E5 · The Final Clue'), findsOneWidget);
      expect(find.text('Our heroes crack the case at last.'), findsOneWidget);
      expect(find.text('Drama'), findsOneWidget);
      expect(find.text('TV-14'), findsOneWidget);
      expect(find.text('LIVE'), findsOneWidget);
      expect(find.text('NEW'), findsWidgets);
      expect(find.byType(ImageFiltered), findsNothing);
    });

    testWidgets('preview artwork sits over a blurred fill of itself', (
      tester,
    ) async {
      final withArt = EpgProgram(
        channelId: 'bbc.one',
        title: 'Square Art',
        description: '',
        start: DateTime(2026, 7, 31, 11, 30),
        end: DateTime(2026, 7, 31, 12, 30),
        iconUrl: 'http://example.com/square.jpg',
      );
      await pumpGuide(
        tester,
        clock: () => now,
        showPreview: true,
        width: 1200,
        height: 800,
        channels: const [bbcOne],
        epgService: EpgService(clock: () => now)..loadPrograms([withArt]),
      );

      expect(find.byType(ImageFiltered), findsOneWidget);
      expect(
        find.byKey(const ValueKey('http://example.com/square.jpg')),
        findsOneWidget,
      );
    });

    testWidgets('preview panel is skipped when the guide is too short', (
      tester,
    ) async {
      await pumpGuide(
        tester,
        clock: () => now,
        showPreview: true,
        channels: const [bbcOne],
        epgService: EpgService(clock: () => now)..loadPrograms([richProgram]),
      );

      expect(find.text('Our heroes crack the case at last.'), findsNothing);
    });

    testWidgets('tap opens a details sheet on touch devices', (tester) async {
      final selected = <Channel>[];
      await pumpGuide(
        tester,
        clock: () => now,
        tapOpensDetails: true,
        width: 400,
        height: 700,
        channels: const [bbcOne],
        epgService: EpgService(clock: () => now)..loadPrograms([richProgram]),
        onChannelSelect: selected.add,
      );

      await tester.tap(programCell(richProgram));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('epg-program-details-sheet')),
        findsOneWidget,
      );
      expect(find.text('Our heroes crack the case at last.'), findsOneWidget);
      expect(selected, isEmpty);

      await tester.tap(find.text('Watch live'));
      await tester.pumpAndSettle();
      expect(selected, [bbcOne]);
      expect(
        find.byKey(const ValueKey('epg-program-details-sheet')),
        findsNothing,
      );
    });
  });
}

DpadFocusable _dateControlFocusable(WidgetTester tester, ValueKey<String> key) {
  return tester.widget<DpadFocusable>(
    find.descendant(of: find.byKey(key), matching: find.byType(DpadFocusable)),
  );
}

double _horizontalScrollOffset(WidgetTester tester) {
  final scrollable = tester.widget<Scrollable>(
    find
        .byWidgetPredicate(
          (widget) => widget is Scrollable && widget.axis == Axis.horizontal,
        )
        .first,
  );
  return scrollable.controller!.offset;
}

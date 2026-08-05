import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/epg/timeline_epg_view.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/epg_service.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';

void main() {
  final observesBerlinDst =
      DateTime(2026, 3, 29).timeZoneOffset == const Duration(hours: 1) &&
      DateTime(2026, 3, 30).timeZoneOffset == const Duration(hours: 2) &&
      DateTime(2026, 10, 25).timeZoneOffset == const Duration(hours: 2) &&
      DateTime(2026, 10, 26).timeZoneOffset == const Duration(hours: 1);

  group('TimelineEpgView', () {
    testWidgets('catchup channels show replay availability indicator', (
      tester,
    ) async {
      final epgService = EpgService();

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 300,
              child: TimelineEpgView(
                channels: const [
                  Channel(
                    id: 101,
                    name: 'BBC One',
                    streamUrl: 'https://streams.example/live/101.m3u8',
                    catchupSupported: true,
                    catchupDays: 7,
                  ),
                  Channel(
                    id: 102,
                    name: 'BBC Two',
                    streamUrl: 'https://streams.example/live/102.m3u8',
                  ),
                ],
                epgService: epgService,
                onChannelSelect: (_) {},
              ),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.replay_rounded), findsOneWidget);
      expect(find.text('7d'), findsOneWidget);
    });

    testWidgets('tapping past catchup program invokes catchup callback', (
      tester,
    ) async {
      final now = DateTime.now();
      const channel = Channel(
        id: 101,
        name: 'BBC One',
        streamUrl: 'https://streams.example/live/101.m3u8',
        epgChannelId: 'bbc.one',
        catchupSupported: true,
        catchupDays: 7,
      );
      final program = EpgProgram(
        channelId: 'bbc.one',
        title: 'Archived News',
        description: 'Replayable fixture',
        start: now.subtract(const Duration(minutes: 45)),
        end: now.subtract(const Duration(minutes: 15)),
      );
      final epgService = EpgService()..loadPrograms([program]);
      Channel? selectedChannel;
      EpgProgram? selectedProgram;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 300,
              child: TimelineEpgView(
                channels: const [channel],
                epgService: epgService,
                onChannelSelect: (_) {},
                onCatchupProgramSelect: (channel, program) {
                  selectedChannel = channel;
                  selectedProgram = program;
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final programBlock = tester.widget<DpadInkWell>(
        find.byKey(
          ValueKey(
            'timeline-program-${program.channelId}-${program.start.toIso8601String()}',
          ),
        ),
      );
      programBlock.onTap?.call();
      await tester.pumpAndSettle();

      expect(selectedChannel, channel);
      expect(selectedProgram, program);
    });

    testWidgets('program blocks use D-pad focusable selection affordance', (
      tester,
    ) async {
      final now = DateTime.now();
      const channel = Channel(
        id: 101,
        name: 'BBC One',
        streamUrl: 'https://streams.example/live/101.m3u8',
        epgChannelId: 'bbc.one',
      );
      final program = EpgProgram(
        channelId: 'bbc.one',
        title: 'Evening News',
        description: 'Focusable fixture',
        start: now.subtract(const Duration(minutes: 15)),
        end: now.add(const Duration(minutes: 15)),
      );
      final epgService = EpgService()..loadPrograms([program]);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: DpadRegion(
              child: SizedBox(
                width: 800,
                height: 300,
                child: TimelineEpgView(
                  channels: const [channel],
                  epgService: epgService,
                  onChannelSelect: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final programText = find.text('Evening News');
      expect(programText, findsOneWidget);
      expect(
        find.ancestor(of: programText, matching: find.byType(DpadInkWell)),
        findsOneWidget,
      );
    });

    testWidgets(
      'past programs on catchup channels render per-program replay icon',
      (tester) async {
        final now = DateTime.now();
        const channel = Channel(
          id: 101,
          name: 'BBC One',
          streamUrl: 'https://streams.example/live/101.m3u8',
          epgChannelId: 'bbc.one',
          catchupSupported: true,
          catchupDays: 7,
        );
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
        final epgService = EpgService()
          ..loadPrograms([pastProgram, futureProgram]);

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(useMaterial3: true),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 300,
                child: TimelineEpgView(
                  channels: const [channel],
                  epgService: epgService,
                  onChannelSelect: (_) {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        // The channel-level badge contributes one replay icon (channel column).
        // The per-program icon adds one for the past program only.
        expect(find.byIcon(Icons.replay_rounded), findsNWidgets(2));

        // The past program block contains its own replay icon.
        final pastBlockKey = ValueKey(
          'timeline-program-${pastProgram.channelId}-${pastProgram.start.toIso8601String()}',
        );
        expect(
          find.descendant(
            of: find.byKey(pastBlockKey),
            matching: find.byIcon(Icons.replay_rounded),
          ),
          findsOneWidget,
        );

        // The future program block does not.
        final futureBlockKey = ValueKey(
          'timeline-program-${futureProgram.channelId}-${futureProgram.start.toIso8601String()}',
        );
        expect(
          find.descendant(
            of: find.byKey(futureBlockKey),
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
        const channel = Channel(
          id: 102,
          name: 'BBC Two',
          streamUrl: 'https://streams.example/live/102.m3u8',
          epgChannelId: 'bbc.two',
        );
        final pastProgram = EpgProgram(
          channelId: 'bbc.two',
          title: 'Old Show',
          description: 'Not replayable',
          start: now.subtract(const Duration(minutes: 60)),
          end: now.subtract(const Duration(minutes: 30)),
        );
        final epgService = EpgService()..loadPrograms([pastProgram]);

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(useMaterial3: true),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 300,
                child: TimelineEpgView(
                  channels: const [channel],
                  epgService: epgService,
                  onChannelSelect: (_) {},
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.replay_rounded), findsNothing);
      },
    );

    testWidgets('navigates days, displays the date, and returns to now', (
      tester,
    ) async {
      final now = DateTime(2026, 7, 31, 12);
      final requestedDates = <DateTime>[];

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 300,
              child: TimelineEpgView(
                channels: const [
                  Channel(
                    id: 101,
                    name: 'BBC One',
                    streamUrl: 'https://streams.example/live/101.m3u8',
                    catchupSupported: true,
                    catchupDays: 7,
                  ),
                ],
                epgService: EpgService(clock: () => now),
                onChannelSelect: (_) {},
                onEnsureEpg: (channels, {startDate, endDate}) {
                  requestedDates.add(startDate!);
                },
                clock: () => now,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Jul 31, 2026'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('timeline-previous-day')));
      await tester.pump();
      expect(find.text('Jul 30, 2026'), findsOneWidget);
      expect(requestedDates.last, DateTime(2026, 7, 30));

      await tester.tap(find.byKey(const ValueKey('timeline-next-day')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('timeline-next-day')));
      await tester.pump();
      expect(find.text('Aug 1, 2026'), findsOneWidget);

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

    testWidgets(
      'null catchup metadata uses a finite seven-day retention',
      (tester) async {
        final now = DateTime(2026, 7, 31, 12);
        const channel = Channel(
          id: 101,
          name: 'BBC One',
          streamUrl: 'https://streams.example/live/101.m3u8',
          epgChannelId: 'bbc.one',
          catchupSupported: true,
        );
        const channels = [
          channel,
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
        ];
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
        final epg = EpgService(clock: () => now)
          ..loadPrograms([olderProgram, retainedProgram]);
        final replayedPrograms = <EpgProgram>[];
        final selectedChannels = <Channel>[];

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(useMaterial3: true),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 300,
                child: TimelineEpgView(
                  channels: channels,
                  epgService: epg,
                  onChannelSelect: selectedChannels.add,
                  onCatchupProgramSelect: (_, program) {
                    replayedPrograms.add(program);
                  },
                  clock: () => now,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        for (var day = 0; day < 7; day += 1) {
          await tester.tap(
            find.byKey(const ValueKey('timeline-previous-day')),
          );
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

        final retainedBlock = find.byKey(
          ValueKey(
            'timeline-program-bbc.one-${retainedProgram.start.toIso8601String()}',
          ),
        );
        final olderBlock = find.byKey(
          ValueKey(
            'timeline-program-bbc.one-${olderProgram.start.toIso8601String()}',
          ),
        );
        expect(
          find.descendant(
            of: retainedBlock,
            matching: find.byIcon(Icons.replay_rounded),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: olderBlock,
            matching: find.byIcon(Icons.replay_rounded),
          ),
          findsNothing,
        );

        tester.widget<DpadInkWell>(retainedBlock).onTap?.call();
        tester.widget<DpadInkWell>(olderBlock).onTap?.call();

        expect(replayedPrograms, [retainedProgram]);
        expect(selectedChannels, [channel]);
      },
    );

    testWidgets('zero and negative catchup retention remain unavailable', (
      tester,
    ) async {
      final now = DateTime(2026, 7, 31, 12);
      const channels = [
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
      ];
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
      final epg = EpgService(clock: () => now)..loadPrograms(programs);
      final replayedPrograms = <EpgProgram>[];
      final selectedChannels = <Channel>[];

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 300,
              child: TimelineEpgView(
                channels: channels,
                epgService: epg,
                onChannelSelect: selectedChannels.add,
                onCatchupProgramSelect: (_, program) {
                  replayedPrograms.add(program);
                },
                clock: () => now,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        _dateControlFocusable(
          tester,
          const ValueKey('timeline-previous-day'),
        ).enabled,
        isFalse,
      );
      for (final program in programs) {
        final block = find.byKey(
          ValueKey(
            'timeline-program-${program.channelId}-${program.start.toIso8601String()}',
          ),
        );
        expect(
          find.descendant(
            of: block,
            matching: find.byIcon(Icons.replay_rounded),
          ),
          findsNothing,
        );
        tester.widget<DpadInkWell>(block).onTap?.call();
      }

      expect(replayedPrograms, isEmpty);
      expect(selectedChannels, channels);
    });

    testWidgets(
      'spring-forward navigation and window keep calendar boundaries',
      (tester) async {
        final now = DateTime(2026, 3, 30, 12);
        final lateProgram = EpgProgram(
          channelId: 'bbc.one',
          title: 'Late Sunday',
          description: 'Inside Sunday',
          start: DateTime(2026, 3, 29, 23, 30),
          end: DateTime(2026, 3, 29, 23, 50),
        );
        final nextDayProgram = EpgProgram(
          channelId: 'bbc.one',
          title: 'Early Monday',
          description: 'Outside Sunday',
          start: DateTime(2026, 3, 30, 0, 15),
          end: DateTime(2026, 3, 30, 0, 45),
        );
        final epg = EpgService(clock: () => now)
          ..loadPrograms([lateProgram, nextDayProgram]);

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(useMaterial3: true),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 300,
                child: TimelineEpgView(
                  channels: const [
                    Channel(
                      id: 101,
                      name: 'BBC One',
                      streamUrl: 'https://streams.example/live/101.m3u8',
                      epgChannelId: 'bbc.one',
                      catchupSupported: true,
                      catchupDays: 7,
                    ),
                  ],
                  epgService: epg,
                  onChannelSelect: (_) {},
                  clock: () => now,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('timeline-previous-day')));
        await tester.pump();

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
        final lateProgram = EpgProgram(
          channelId: 'bbc.one',
          title: 'Late Sunday',
          description: 'Inside Sunday',
          start: DateTime(2026, 10, 25, 23, 30),
          end: DateTime(2026, 10, 25, 23, 50),
        );
        final epg = EpgService(clock: () => now)..loadPrograms([lateProgram]);

        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(useMaterial3: true),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: SizedBox(
                width: 800,
                height: 300,
                child: TimelineEpgView(
                  channels: const [
                    Channel(
                      id: 101,
                      name: 'BBC One',
                      streamUrl: 'https://streams.example/live/101.m3u8',
                      epgChannelId: 'bbc.one',
                    ),
                  ],
                  epgService: epg,
                  onChannelSelect: (_) {},
                  clock: () => now,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byKey(const ValueKey('timeline-next-day')));
        await tester.pump();
        expect(find.text('Oct 25, 2026'), findsOneWidget);
        expect(find.text('Late Sunday'), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('timeline-next-day')));
        await tester.pump();
        expect(find.text('Oct 26, 2026'), findsOneWidget);
        expect(find.text('Late Sunday'), findsNothing);
      },
      skip: !observesBerlinDst,
    );

    testWidgets('keeps horizontal pointer scrolling available', (tester) async {
      final now = DateTime(2026, 7, 31, 12);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 300,
              child: TimelineEpgView(
                channels: const [
                  Channel(
                    id: 101,
                    name: 'BBC One',
                    streamUrl: 'https://streams.example/live/101.m3u8',
                  ),
                ],
                epgService: EpgService(clock: () => now),
                onChannelSelect: (_) {},
                clock: () => now,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final row = find.byKey(const ValueKey('timeline-row-scroll-101'));
      final scrollable = find.descendant(
        of: row,
        matching: find.byType(Scrollable),
      );
      final before = tester.state<ScrollableState>(scrollable).position.pixels;
      await tester.drag(row, const Offset(-300, 0));
      await tester.pumpAndSettle();

      expect(
        tester.state<ScrollableState>(scrollable).position.pixels,
        greaterThan(before),
      );
    });

    testWidgets('date controls traverse and activate with D-pad keys', (
      tester,
    ) async {
      final now = DateTime(2026, 7, 31, 12);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: DpadRegion(
              child: SizedBox(
                width: 800,
                height: 300,
                child: TimelineEpgView(
                  channels: const [
                    Channel(
                      id: 101,
                      name: 'BBC One',
                      streamUrl: 'https://streams.example/live/101.m3u8',
                      catchupSupported: true,
                      catchupDays: 7,
                    ),
                  ],
                  epgService: EpgService(clock: () => now),
                  onChannelSelect: (_) {},
                  clock: () => now,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(find.text('Jul 30, 2026'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(find.text('Jul 31, 2026'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(find.text('Aug 1, 2026'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(find.text('Jul 31, 2026'), findsOneWidget);
    });

    testWidgets('D-pad skips disabled previous control at catchup boundary', (
      tester,
    ) async {
      final now = DateTime(2026, 7, 31, 12);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: DpadRegion(
              child: SizedBox(
                width: 800,
                height: 300,
                child: TimelineEpgView(
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
                  onChannelSelect: (_) {},
                  clock: () => now,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final previous = _dateControlFocusable(
        tester,
        const ValueKey('timeline-previous-day'),
      );
      expect(previous.enabled, isFalse);
      expect(
        _dateControlFocusable(
          tester,
          const ValueKey('timeline-now'),
        ).focusNode?.hasFocus,
        isTrue,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      expect(
        _dateControlFocusable(
          tester,
          const ValueKey('timeline-now'),
        ).focusNode?.hasFocus,
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(find.text('Jul 31, 2026'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(
        _dateControlFocusable(
          tester,
          const ValueKey('timeline-next-day'),
        ).focusNode?.hasFocus,
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(find.text('Aug 1, 2026'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(find.text('Jul 31, 2026'), findsOneWidget);
    });

    testWidgets('D-pad skips disabled next control at future boundary', (
      tester,
    ) async {
      final now = DateTime(2026, 7, 31, 12);
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: DpadRegion(
              child: SizedBox(
                width: 800,
                height: 300,
                child: TimelineEpgView(
                  channels: const [
                    Channel(
                      id: 101,
                      name: 'BBC One',
                      streamUrl: 'https://streams.example/live/101.m3u8',
                      catchupSupported: true,
                      catchupDays: 7,
                    ),
                  ],
                  epgService: EpgService(clock: () => now),
                  onChannelSelect: (_) {},
                  futureDays: 0,
                  clock: () => now,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        _dateControlFocusable(
          tester,
          const ValueKey('timeline-previous-day'),
        ).focusNode?.hasFocus,
        isTrue,
      );
      expect(
        _dateControlFocusable(
          tester,
          const ValueKey('timeline-next-day'),
        ).enabled,
        isFalse,
      );

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(
        _dateControlFocusable(
          tester,
          const ValueKey('timeline-now'),
        ).focusNode?.hasFocus,
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
      expect(find.text('Jul 31, 2026'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pump();
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
      final epg = EpgService(clock: () => now)
        ..loadPrograms([shortProgram, longProgram]);

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 300,
              child: TimelineEpgView(
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
                epgService: epg,
                onChannelSelect: (_) {},
                clock: () => now,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (var day = 0; day < 3; day += 1) {
        await tester.tap(find.byKey(const ValueKey('timeline-previous-day')));
        await tester.pump();
      }

      final shortBlock = find.byKey(
        ValueKey(
          'timeline-program-short-${shortProgram.start.toIso8601String()}',
        ),
      );
      final longBlock = find.byKey(
        ValueKey(
          'timeline-program-long-${longProgram.start.toIso8601String()}',
        ),
      );
      expect(
        find.descendant(
          of: shortBlock,
          matching: find.byIcon(Icons.replay_rounded),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: longBlock,
          matching: find.byIcon(Icons.replay_rounded),
        ),
        findsOneWidget,
      );
    });
  });
}

DpadFocusable _dateControlFocusable(WidgetTester tester, ValueKey<String> key) {
  return tester.widget<DpadFocusable>(
    find.descendant(of: find.byKey(key), matching: find.byType(DpadFocusable)),
  );
}

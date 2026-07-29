import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/epg/timeline_epg_view.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/epg_service.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';

void main() {
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
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/epg/epg_recording_state.dart';
import 'package:m3u_tv/features/epg/timeline_epg_view.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/epg_service.dart';

void main() {
  final now = DateTime(2026, 6, 1, 12);

  const channel = Channel(
    id: 101,
    name: 'BBC One',
    streamUrl: 'https://streams.example/live/101.m3u8',
    epgChannelId: 'bbc.one',
  );

  EpgRecordingState noRecordingState(EpgProgram _) => EpgRecordingState.none;

  Widget wrap(Widget child) => MaterialApp(
    theme: ThemeData.dark(useMaterial3: true),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );

  Future<EpgService> seedService(List<EpgProgram> programs) async {
    final service = EpgService()..loadPrograms(programs);
    addTearDown(service.dispose);
    return service;
  }

  Future<void> pump(
    WidgetTester tester, {
    required EpgService epgService,
    required EpgRecordingState Function(EpgProgram) recordingStateFor,
    double width = 800,
    double height = 300,
    Channel? channelOverride,
  }) async {
    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: width,
          height: height,
          child: TimelineEpgView(
            channels: [channelOverride ?? channel],
            epgService: epgService,
            onChannelSelect: (_) {},
            clock: () => now,
            // These cases vary by programme only, so drop the channel the
            // widget now supplies and keep the per-programme resolvers below
            // unchanged.
            recordingStateFor: (_, program) => recordingStateFor(program),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('TimelineEpgView recording indicator', () {
    testWidgets(
      'default resolver renders no indicator (visual parity with pre-#185)',
      (tester) async {
        final program = EpgProgram(
          channelId: 'bbc.one',
          title: 'Test Programme',
          description: '',
          start: now.subtract(const Duration(minutes: 15)),
          end: now.add(const Duration(minutes: 15)),
        );
        final epgService = await seedService([program]);

        await pump(
          tester,
          epgService: epgService,
          recordingStateFor: noRecordingState,
        );

        expect(find.byIcon(Icons.schedule), findsNothing);
        expect(find.byIcon(Icons.fiber_manual_record), findsNothing);
        final l10n = AppLocalizations.of(
          tester.element(find.byType(Scaffold)),
        );
        expect(
          find.bySemanticsLabel(l10n.epgProgramScheduledToRecord),
          findsNothing,
        );
        expect(
          find.bySemanticsLabel(l10n.epgProgramCurrentlyRecording),
          findsNothing,
        );
      },
    );

    testWidgets('resolver returning scheduled renders the scheduled badge', (
      tester,
    ) async {
      final program = EpgProgram(
        channelId: 'bbc.one',
        title: 'Test Programme',
        description: '',
        start: now.subtract(const Duration(minutes: 15)),
        end: now.add(const Duration(minutes: 15)),
      );
      final epgService = await seedService([program]);

      await pump(
        tester,
        epgService: epgService,
        recordingStateFor: (_) => EpgRecordingState.scheduled,
      );

      expect(find.byIcon(Icons.schedule), findsOneWidget);
      expect(find.byIcon(Icons.fiber_manual_record), findsNothing);
    });

    testWidgets('resolver returning recording renders the recording badge', (
      tester,
    ) async {
      final program = EpgProgram(
        channelId: 'bbc.one',
        title: 'Test Programme',
        description: '',
        start: now.subtract(const Duration(minutes: 15)),
        end: now.add(const Duration(minutes: 15)),
      );
      final epgService = await seedService([program]);

      await pump(
        tester,
        epgService: epgService,
        recordingStateFor: (_) => EpgRecordingState.recording,
      );

      expect(find.byIcon(Icons.fiber_manual_record), findsOneWidget);
      expect(find.byIcon(Icons.schedule), findsNothing);
    });

    testWidgets('resolver can vary per programme (mixed states in one row)', (
      tester,
    ) async {
      final past = EpgProgram(
        channelId: 'bbc.one',
        title: 'Past Programme',
        description: '',
        start: now.subtract(const Duration(hours: 1)),
        end: now.subtract(const Duration(minutes: 30)),
      );
      final future = EpgProgram(
        channelId: 'bbc.one',
        title: 'Future Programme',
        description: '',
        start: now.add(const Duration(minutes: 30)),
        end: now.add(const Duration(hours: 1)),
      );
      final epgService = await seedService([past, future]);

      await pump(
        tester,
        epgService: epgService,
        recordingStateFor: (p) => p.start.isAfter(now)
            ? EpgRecordingState.scheduled
            : EpgRecordingState.none,
      );

      expect(find.byIcon(Icons.schedule), findsOneWidget);
      expect(find.byIcon(Icons.fiber_manual_record), findsNothing);
    });

    testWidgets('narrow block with recording indicator does not overflow', (
      tester,
    ) async {
      // Short programme (15 min) inside the default 6-hour window renders a
      // narrow ~67px block at 800px viewport width. The recording indicator
      // overlay must not throw or overflow that block.
      final program = EpgProgram(
        channelId: 'bbc.one',
        title: 'Test Programme',
        description: '',
        start: now.subtract(const Duration(minutes: 15)),
        end: now.add(const Duration(minutes: 15)),
      );
      final epgService = await seedService([program]);

      await pump(
        tester,
        epgService: epgService,
        recordingStateFor: (_) => EpgRecordingState.recording,
      );

      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.fiber_manual_record), findsAtLeast(1));
    });
  });
}

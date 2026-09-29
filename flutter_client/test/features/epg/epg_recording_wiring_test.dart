import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/epg/epg_recording_index.dart';
import 'package:m3u_tv/features/epg/timeline_epg_view.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/epg_service.dart';

/// Guards the seam between the recording matcher and the grid widget.
///
/// The two halves of #185 were built independently and very nearly did not
/// compose: [EpgProgram.channelId] is the EPG (tvg) identifier — a String —
/// whereas a [DvrRecording] references the channel's integer database id.
/// Only the row's [Channel] carries the latter, so the resolver has to be
/// handed both. Nothing in either half's own tests exercises that hand-off,
/// which is why these go through the real [EpgRecordingIndex] against a real
/// [DvrRecording] rather than a stub resolver.
void main() {
  final now = DateTime(2026, 6, 1, 12);

  const channel = Channel(
    id: 101,
    name: 'BBC One',
    streamUrl: 'https://streams.example/live/101.m3u8',
    epgChannelId: 'bbc.one',
  );

  // Airing now, so the block is on screen in the default window.
  final program = EpgProgram(
    channelId: 'bbc.one',
    title: 'Test Programme',
    description: '',
    start: now.subtract(const Duration(minutes: 15)),
    end: now.add(const Duration(minutes: 15)),
  );

  DvrRecording recordingFor(
    int channelId, {
    required DvrRecordingStatus status,
  }) => DvrRecording(
    uuid: 'rec-1',
    title: 'Test Programme',
    status: status,
    channelId: channelId,
    // Programme window plus the server's default 30s padding either side.
    scheduledStart: program.start.subtract(const Duration(seconds: 30)),
    scheduledEnd: program.end.add(const Duration(seconds: 30)),
  );

  Widget wrap(Widget child) => MaterialApp(
    theme: ThemeData.dark(useMaterial3: true),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );

  Future<void> pumpWithRecordings(
    WidgetTester tester,
    List<DvrRecording> recordings,
  ) async {
    final service = EpgService()..loadPrograms(<EpgProgram>[program]);
    addTearDown(service.dispose);
    final index = EpgRecordingIndex.fromRecordings(recordings);

    await tester.pumpWidget(
      wrap(
        SizedBox(
          width: 800,
          height: 400,
          child: TimelineEpgView(
            channels: const <Channel>[channel],
            epgService: service,
            onChannelSelect: (_) {},
            clock: () => now,
            // Exactly the wiring live_tv_screen.dart uses.
            recordingStateFor: (channel, program) => index.stateFor(
              channelId: channel.id,
              programStart: program.start,
              programEnd: program.end,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a scheduled recording on this channel badges the block', (
    tester,
  ) async {
    await pumpWithRecordings(tester, <DvrRecording>[
      recordingFor(channel.id, status: DvrRecordingStatus.scheduled),
    ]);

    expect(find.byIcon(Icons.schedule), findsOneWidget);
    expect(find.byIcon(Icons.fiber_manual_record), findsNothing);
  });

  testWidgets('an in-flight recording badges the block differently', (
    tester,
  ) async {
    await pumpWithRecordings(tester, <DvrRecording>[
      recordingFor(channel.id, status: DvrRecordingStatus.recording),
    ]);

    expect(find.byIcon(Icons.fiber_manual_record), findsOneWidget);
    expect(find.byIcon(Icons.schedule), findsNothing);
  });

  testWidgets(
    'a recording against a DIFFERENT channel id does not badge this block',
    (tester) async {
      // The failure this catches: wiring the resolver to the wrong id (e.g.
      // parsing the tvg string, or passing a neighbouring row's channel)
      // would still compile and would still badge something.
      await pumpWithRecordings(tester, <DvrRecording>[
        recordingFor(channel.id + 1, status: DvrRecordingStatus.scheduled),
      ]);

      expect(find.byIcon(Icons.schedule), findsNothing);
      expect(find.byIcon(Icons.fiber_manual_record), findsNothing);
    },
  );

  testWidgets('no recordings at all leaves the block unbadged', (tester) async {
    await pumpWithRecordings(tester, const <DvrRecording>[]);

    expect(find.byIcon(Icons.schedule), findsNothing);
    expect(find.byIcon(Icons.fiber_manual_record), findsNothing);
  });
}

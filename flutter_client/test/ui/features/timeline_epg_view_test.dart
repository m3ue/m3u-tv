import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/epg/timeline_epg_view.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/epg_service.dart';

void main() {
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

    final programBlock = tester.widget<InkWell>(
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
}

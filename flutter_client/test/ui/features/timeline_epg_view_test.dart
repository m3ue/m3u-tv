import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/epg/timeline_epg_view.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/epg_service.dart';
import 'package:m3u_tv/shared/dpad_ink_well.dart';

void main() {
  group('TimelineEpgView', () {
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
  });
}

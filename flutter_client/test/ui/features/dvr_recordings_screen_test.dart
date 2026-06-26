import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/dvr/dvr_recordings_screen.dart';
import 'package:m3u_tv/navigation/app_router.dart';
import 'package:m3u_tv/services/domain_models.dart';

void main() {
  group('DvrRecordingsScreen', () {
    testWidgets('renders completed and recording rows with status details', (
      tester,
    ) async {
      await tester.pumpWidget(
        _TestApp(recordings: [_completedRecording(), _recordingNow()]),
      );
      await tester.pumpAndSettle();

      expect(find.text('DVR Recordings'), findsOneWidget);
      expect(find.text('Evening Movie'), findsOneWidget);
      expect(find.text('Director Cut'), findsOneWidget);
      expect(find.text('Completed'), findsOneWidget);
      expect(find.text('Live News'), findsOneWidget);
      expect(find.text('Recording'), findsOneWidget);
      expect(find.text('News 24'), findsOneWidget);
    });

    testWidgets('completed recording opens player with stream_url', (
      tester,
    ) async {
      PlayerArgs? opened;
      await tester.pumpWidget(
        _TestApp(
          recordings: [_completedRecording()],
          onPlay: (args) => opened = args,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Evening Movie'));
      await tester.pumpAndSettle();

      expect(opened, isNotNull);
      expect(opened!.streamUrl, 'https://stream.example/recordings/rec-1.mp4');
      expect(opened!.title, 'Evening Movie');
      expect(opened!.type, 'vod');
      expect(opened!.metadata['dvr_uuid'], 'rec-1');
      expect(
        opened!.metadata['edl_url'],
        'https://stream.example/recordings/rec-1.edl',
      );
    });

    testWidgets('in-progress recording opens player with live_url', (
      tester,
    ) async {
      PlayerArgs? opened;
      await tester.pumpWidget(
        _TestApp(
          recordings: [_recordingNow()],
          onPlay: (args) => opened = args,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Live News'));
      await tester.pumpAndSettle();

      expect(opened, isNotNull);
      expect(
        opened!.streamUrl,
        'https://stream.example/recordings/rec-2/live.m3u8',
      );
      expect(opened!.title, 'Live News');
      expect(opened!.type, 'live');
      expect(opened!.metadata['dvr_uuid'], 'rec-2');
    });
  });
}

class _TestApp extends StatelessWidget {
  const _TestApp({required this.recordings, this.onPlay});

  final List<DvrRecording> recordings;
  final void Function(PlayerArgs args)? onPlay;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: DvrRecordingsScreen(
        recordings: recordings,
        isLoading: false,
        isConfigured: true,
        onPlay: onPlay ?? (_) {},
      ),
    );
  }
}

DvrRecording _completedRecording() => DvrRecording(
  uuid: 'rec-1',
  title: 'Evening Movie',
  subtitle: 'Director Cut',
  status: DvrRecordingStatus.completed,
  channelId: 101,
  channelName: 'BBC One',
  scheduledStart: DateTime.utc(2026, 6, 25, 18),
  scheduledEnd: DateTime.utc(2026, 6, 25, 20),
  actualStart: DateTime.utc(2026, 6, 25, 18, 1),
  actualEnd: DateTime.utc(2026, 6, 25, 20, 2),
  durationSeconds: 7200,
  fileSizeBytes: 1234567890,
  seasonNumber: 2,
  episodeNumber: 5,
  streamUrl: 'https://stream.example/recordings/rec-1.mp4',
  edlUrl: 'https://stream.example/recordings/rec-1.edl',
);

DvrRecording _recordingNow() => DvrRecording(
  uuid: 'rec-2',
  title: 'Live News',
  status: DvrRecordingStatus.recording,
  channelId: 102,
  channelName: 'News 24',
  scheduledStart: DateTime.utc(2026, 6, 25, 21),
  scheduledEnd: DateTime.utc(2026, 6, 25, 22),
  actualStart: DateTime.utc(2026, 6, 25, 21, 1),
  durationSeconds: 3600,
  liveUrl: 'https://stream.example/recordings/rec-2/live.m3u8',
);

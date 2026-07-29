import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/dvr/dvr_recordings_screen.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
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

    testWidgets('shows cancel button for in-progress recording', (
      tester,
    ) async {
      await tester.pumpWidget(
        _TestApp(
          recordings: [_recordingNow()],
          onCancelRecording: (_) async {},
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byTooltip('Cancel'),
        findsOneWidget,
        reason: 'scheduled/recording rows show the cancel action',
      );
      expect(find.byTooltip('Delete'), findsNothing);
    });

    testWidgets('shows cancel button for scheduled recording', (tester) async {
      await tester.pumpWidget(
        _TestApp(
          recordings: [_scheduledRecording()],
          onCancelRecording: (_) async {},
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('Cancel'), findsOneWidget);
      expect(find.byTooltip('Delete'), findsNothing);
    });

    testWidgets('shows delete button for completed recording', (tester) async {
      await tester.pumpWidget(
        _TestApp(
          recordings: [_completedRecording()],
          onDeleteRecording: (_) async {},
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('Delete'), findsOneWidget);
      expect(find.byTooltip('Cancel'), findsNothing);
    });

    testWidgets('shows delete button for failed and cancelled recordings', (
      tester,
    ) async {
      await tester.pumpWidget(
        _TestApp(
          recordings: [_failedRecording(), _cancelledRecording()],
          onDeleteRecording: (_) async {},
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('Delete'), findsNWidgets(2));
      expect(find.byTooltip('Cancel'), findsNothing);
    });

    testWidgets('hides action buttons when callbacks are null', (
      tester,
    ) async {
      await tester.pumpWidget(
        _TestApp(recordings: [_completedRecording(), _recordingNow()]),
      );
      await tester.pumpAndSettle();

      expect(find.byTooltip('Cancel'), findsNothing);
      expect(find.byTooltip('Delete'), findsNothing);
    });

    testWidgets('cancel button shows confirmation dialog and runs callback', (
      tester,
    ) async {
      String? cancelledUuid;
      await tester.pumpWidget(
        _TestApp(
          recordings: [_recordingNow()],
          onCancelRecording: (uuid) async {
            cancelledUuid = uuid;
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Cancel recording?'), findsOneWidget);
      await tester.tap(find.text('Cancel recording'));
      await tester.pumpAndSettle();

      expect(cancelledUuid, 'rec-2');
    });

    testWidgets('delete button shows confirmation dialog and runs callback', (
      tester,
    ) async {
      String? deletedUuid;
      await tester.pumpWidget(
        _TestApp(
          recordings: [_completedRecording()],
          onDeleteRecording: (uuid) async {
            deletedUuid = uuid;
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Delete recording?'), findsOneWidget);
      await tester.tap(find.text('Delete recording'));
      await tester.pumpAndSettle();

      expect(deletedUuid, 'rec-1');
    });

    testWidgets('dismissing cancel dialog does not invoke callback', (
      tester,
    ) async {
      var calls = 0;
      await tester.pumpWidget(
        _TestApp(
          recordings: [_recordingNow()],
          onCancelRecording: (_) async {
            calls += 1;
          },
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Cancel'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep'));
      await tester.pumpAndSettle();

      expect(calls, 0);
      expect(find.text('Cancel recording?'), findsNothing);
    });
  });
}

class _TestApp extends StatelessWidget {
  const _TestApp({
    required this.recordings,
    this.onPlay,
    this.onCancelRecording,
    this.onDeleteRecording,
  });

  final List<DvrRecording> recordings;
  final void Function(PlayerArgs args)? onPlay;
  final Future<void> Function(String uuid)? onCancelRecording;
  final Future<void> Function(String uuid)? onDeleteRecording;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: DvrRecordingsScreen(
        recordings: recordings,
        isLoading: false,
        isConfigured: true,
        onPlay: onPlay ?? (_) {},
        onCancelRecording: onCancelRecording,
        onDeleteRecording: onDeleteRecording,
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

DvrRecording _scheduledRecording() => DvrRecording(
  uuid: 'rec-3',
  title: 'Upcoming Show',
  status: DvrRecordingStatus.scheduled,
  channelId: 103,
  channelName: 'CNN',
  scheduledStart: DateTime.utc(2026, 7, 1, 19),
  scheduledEnd: DateTime.utc(2026, 7, 1, 20),
);

DvrRecording _failedRecording() => DvrRecording(
  uuid: 'rec-4',
  title: 'Broken Show',
  status: DvrRecordingStatus.failed,
  channelId: 104,
  channelName: 'HBO',
  scheduledStart: DateTime.utc(2026, 6, 20, 19),
  scheduledEnd: DateTime.utc(2026, 6, 20, 20),
);

DvrRecording _cancelledRecording() => DvrRecording(
  uuid: 'rec-5',
  title: 'Skipped Show',
  status: DvrRecordingStatus.cancelled,
  channelId: 105,
  channelName: 'FX',
  scheduledStart: DateTime.utc(2026, 6, 20, 21),
  scheduledEnd: DateTime.utc(2026, 6, 20, 22),
);

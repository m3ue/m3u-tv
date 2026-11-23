import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/player/playback_controls.dart';
import 'package:m3u_tv/features/player/player_screen.dart';
import 'package:m3u_tv/features/player/resume_modal.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/navigation/app_router.dart';
import 'package:m3u_tv/playback/playback_capabilities.dart';
import 'package:m3u_tv/playback/playback_orchestrator.dart';
import 'package:m3u_tv/playback/player_adapter.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/epg_service.dart';
import 'package:material_ui/material_ui.dart';

import 'fake_player_adapter.dart';
import 'fake_transcode_gateway.dart';

const PlaybackBackend _backend = PlaybackBackend.desktopLibmpv;

DvrRecording _recording(String status, {int? id = 42, int? duration}) =>
    DvrRecording.fromXtream(<String, Object?>{
      'id': id,
      'uuid': 'rec-1',
      'title': 'The Game',
      'status': status,
      'elapsed_seconds': 1800,
      'duration_seconds': duration,
      'live_url': status == 'completed' ? null : 'https://x.test/live.m3u8',
      'stream_url': status == 'completed' ? 'https://x.test/rec.mp4' : null,
    });

void main() {
  test('the recording id and elapsed time are read alongside the uuid', () {
    final recording = _recording('recording');
    expect(recording.uuid, 'rec-1');
    expect(recording.id, 42);
    expect(recording.elapsedSeconds, 1800);
  });

  test('a finalizing recording plays its live playlist, at a fixed length', () {
    final args = PlayerArgs.dvrRecording(_recording('post_processing'));
    expect(args.streamUrl, 'https://x.test/live.m3u8');
    expect(args.dvrWindow!.isGrowing, isFalse);
    expect(args.dvrWindow!.length, const Duration(minutes: 30));
    expect(
      args.dvrWindow!.livePosition,
      const Duration(minutes: 30) - DvrWindow.liveMargin,
    );
  });

  test('an unfinished recording opens at its start, not at the live edge', () {
    final source = PlayerArgs.dvrRecording(
      _recording('recording'),
    ).toPlaybackSource();
    expect(source.isLive, isFalse);
    expect(source.isGrowing, isTrue);
    expect(source.startPosition, const Duration(milliseconds: 1));
  });

  test('a finished recording is a plain file', () {
    final args = PlayerArgs.dvrRecording(_recording('completed'));
    expect(args.dvrWindow, isNull);
    expect(args.streamId, isNull);
    expect(args.toPlaybackSource().isGrowing, isFalse);
    expect(args.toPlaybackSource().startPosition, Duration.zero);
  });

  Future<FakePlayerAdapter> pumpPlayer(
    WidgetTester tester,
    PlayerArgs args, {
    List<Progress>? reports,
    List<PlayerArgs>? replaced,
    Future<DvrRecording> Function(String)? fetch,
    VoidCallback? onClose,
  }) async {
    final adapter = FakePlayerAdapter(
      capabilities: PlaybackCapabilities.desktopLibmpv,
      textureId: 7,
    );
    final orchestrator = PlaybackOrchestrator(
      platform: PlaybackPlatform.desktop,
      adapters: <PlaybackBackend, PlayerAdapter>{_backend: adapter},
      transcodeGateway: FakeTranscodeGateway(),
    );
    addTearDown(orchestrator.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: PlayerScreen(
          args: args,
          orchestrator: orchestrator,
          epgService: EpgService(clock: () => DateTime.utc(2026)),
          progressReporter: reports?.add,
          onReplaceItem: replaced?.add,
          fetchDvrRecording: fetch,
          onClose: onClose,
        ),
      ),
    );
    await tester.pump();
    return adapter;
  }

  void emit(
    FakePlayerAdapter adapter,
    PlaybackStatus status,
    Duration position,
  ) => adapter.emitState(
    PlaybackState(backend: _backend, status: status, position: position),
  );

  testWidgets('progress is kept under the recording id and never completed', (
    tester,
  ) async {
    final reports = <Progress>[];
    final adapter = await pumpPlayer(
      tester,
      PlayerArgs.dvrRecording(_recording('recording')),
      reports: reports,
    );
    emit(adapter, PlaybackStatus.playing, const Duration(minutes: 29));
    await tester.pump(const Duration(seconds: 31));

    expect(reports, isNotEmpty);
    expect(reports.last.contentType, ContentType.dvrRecording);
    expect(reports.last.streamId, 42);
    expect(reports.last.durationSeconds, isNull);
    expect(reports.last.completed, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the length the player reports replaces the estimate', (
    tester,
  ) async {
    final adapter = await pumpPlayer(
      tester,
      PlayerArgs.dvrRecording(_recording('recording')),
    );
    PlaybackControls controls() =>
        tester.widget<PlaybackControls>(find.byType(PlaybackControls));
    void tick() => adapter.emitState(
      const PlaybackState(
        backend: _backend,
        status: PlaybackStatus.playing,
        position: Duration(minutes: 1),
        duration: Duration(minutes: 20),
      ),
    );
    tick();
    await tester.pump();
    // Shorter than the 30 minutes since it started: it was interrupted.
    expect(controls().duration.inMinutes, 20);
    expect(controls().canSeek, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a shorter report later on does not shrink the length', (
    tester,
  ) async {
    final adapter = await pumpPlayer(
      tester,
      PlayerArgs.dvrRecording(_recording('recording')),
    );
    int minutes() => tester
        .widget<PlaybackControls>(find.byType(PlaybackControls))
        .duration
        .inMinutes;
    void tick(Duration duration) => adapter.emitState(
      PlaybackState(
        backend: _backend,
        status: PlaybackStatus.playing,
        position: const Duration(minutes: 1),
        duration: duration,
      ),
    );
    tick(const Duration(minutes: 20));
    await tester.pump();
    tick(const Duration(minutes: 15));
    await tester.pump();
    expect(minutes(), 20);
    tick(const Duration(minutes: 25));
    await tester.pump();
    expect(minutes(), 25);
    await tester.pumpWidget(const SizedBox());
  });

  for (final status in ['post_processing', 'completed']) {
    testWidgets('closes at the end after stalling there ($status)', (
      tester,
    ) async {
      var closed = false;
      final replaced = <PlayerArgs>[];
      final adapter = await pumpPlayer(
        tester,
        PlayerArgs.dvrRecording(_recording('recording')),
        replaced: replaced,
        fetch: (_) async => _recording(status, duration: 1800),
        onClose: () => closed = true,
      );
      emit(adapter, PlaybackStatus.playing, const Duration(minutes: 30));
      await tester.pump();
      emit(adapter, PlaybackStatus.buffering, const Duration(minutes: 30));
      await tester.pump(const Duration(seconds: 10));
      // Reopening a stream that is gone resets the position.
      emit(adapter, PlaybackStatus.loading, Duration.zero);
      await tester.pump(const Duration(seconds: 19));
      await tester.pump(const Duration(seconds: 31));
      emit(adapter, PlaybackStatus.completed, Duration.zero);
      await tester.pump();
      await tester.pump();
      expect(closed, isTrue);
      expect(replaced, isEmpty);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('a failed lookup is retried', (tester) async {
    final replaced = <PlayerArgs>[];
    var calls = 0;
    final adapter = await pumpPlayer(
      tester,
      PlayerArgs.dvrRecording(_recording('recording')),
      replaced: replaced,
      fetch: (_) async {
        if (calls++ == 0) throw TimeoutException('offline');
        return _recording('completed', duration: 1800);
      },
    );
    emit(adapter, PlaybackStatus.playing, const Duration(minutes: 10));
    await tester.pump();
    emit(adapter, PlaybackStatus.completed, const Duration(minutes: 10));
    await tester.pump();
    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(calls, 2);
    expect(replaced.single.startPosition, 600);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('without a recording id nothing is reported', (tester) async {
    final reports = <Progress>[];
    final adapter = await pumpPlayer(
      tester,
      PlayerArgs.dvrRecording(_recording('completed', id: null)),
      reports: reports,
    );
    emit(adapter, PlaybackStatus.playing, const Duration(minutes: 5));
    await tester.pump(const Duration(seconds: 31));
    expect(reports, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('moves to the finished file at the same position', (
    tester,
  ) async {
    final replaced = <PlayerArgs>[];
    final answers = [_recording('post_processing'), _recording('completed')];
    final adapter = await pumpPlayer(
      tester,
      PlayerArgs.dvrRecording(_recording('recording')),
      replaced: replaced,
      fetch: (_) async => answers.removeAt(0),
    );
    emit(adapter, PlaybackStatus.playing, const Duration(minutes: 10));
    await tester.pump();
    emit(adapter, PlaybackStatus.completed, const Duration(minutes: 10));
    await tester.pump();
    expect(replaced, isEmpty);
    expect(find.text('Finishing recording…'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    await tester.pump();
    expect(replaced.single.streamUrl, 'https://x.test/rec.mp4');
    expect(replaced.single.startPosition, 600);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('closes when the recording finished and was watched to the end', (
    tester,
  ) async {
    var closed = false;
    final adapter = await pumpPlayer(
      tester,
      PlayerArgs.dvrRecording(_recording('recording')),
      fetch: (_) async => _recording('post_processing'),
      onClose: () => closed = true,
    );
    emit(adapter, PlaybackStatus.playing, const Duration(minutes: 30));
    await tester.pump();
    emit(adapter, PlaybackStatus.completed, const Duration(minutes: 30));
    await tester.pump();
    expect(closed, isTrue);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a stop while still recording is shown as an error', (
    tester,
  ) async {
    var closed = false;
    final adapter = await pumpPlayer(
      tester,
      PlayerArgs.dvrRecording(_recording('recording')),
      fetch: (_) async => _recording('recording'),
      onClose: () => closed = true,
    );
    emit(adapter, PlaybackStatus.playing, const Duration(minutes: 30));
    await tester.pump();
    emit(adapter, PlaybackStatus.completed, const Duration(minutes: 30));
    await tester.pump();
    await tester.pump();
    expect(closed, isFalse);
    expect(find.text('Playback of this recording stopped.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the start dialog offers live, and resume only when saved', (
    tester,
  ) async {
    ResumeModalResult? result;
    int? saved;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showResumeModal(
              context,
              title: 'The Game',
              positionSeconds: saved,
              showWatchLive: true,
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Recording in Progress'), findsOneWidget);
    expect(find.text('Start from Beginning'), findsOneWidget);
    expect(find.text('Continue'), findsNothing);
    await tester.tap(find.text('Watch Live'));
    await tester.pumpAndSettle();
    expect(result!.action, ResumeAction.watchLive);

    saved = 120;
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Start from Beginning'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(result!.action, ResumeAction.resume);
    expect(result!.startPositionSeconds, 120);
  });
}

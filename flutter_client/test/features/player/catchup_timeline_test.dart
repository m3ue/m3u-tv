import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/player/catchup_timeline.dart';
import 'package:m3u_tv/playback/player_adapter.dart';

void main() {
  final programStart = DateTime.utc(2026, 10, 1, 20);
  final programEnd = DateTime.utc(2026, 10, 1, 21);

  CatchupTimeline timeline({DateTime? start, DateTime? streamStart}) =>
      CatchupTimeline(
        programStart: start ?? programStart,
        programEnd: programEnd,
        streamStart: streamStart,
      );

  Duration min(int minutes, [int seconds = 0]) =>
      Duration(minutes: minutes, seconds: seconds);

  group('fromMetadata', () {
    test('reads the programme window the launcher stores', () {
      final parsed = CatchupTimeline.fromMetadata(<String, Object?>{
        'catchup': true,
        'program_start': programStart.toIso8601String(),
        'program_end': programEnd.toIso8601String(),
      });

      expect(parsed?.duration, const Duration(hours: 1));
      expect(parsed?.streamStart, programStart);
    });

    test('is null without a usable window', () {
      expect(CatchupTimeline.fromMetadata(const <String, Object?>{}), isNull);
      expect(
        CatchupTimeline.fromMetadata(<String, Object?>{
          'program_start': programEnd.toIso8601String(),
          'program_end': programStart.toIso8601String(),
        }),
        isNull,
      );
    });
  });

  test('maps stream positions onto the programme timeline', () {
    final reopened = timeline(streamStart: programStart.add(min(30)));

    expect(reopened.positionOf(Duration.zero), min(30));
    expect(reopened.positionOf(min(5)), min(35));
    expect(reopened.positionOf(const Duration(hours: 2)), min(60));
  });

  test('starts the first stream on the minute a programme starts in', () {
    final offMinute = timeline(start: programStart.add(min(0, 30)));

    expect(offMinute.streamStart, programStart);
    expect(offMinute.positionOf(Duration.zero), Duration.zero);
    expect(offMinute.positionOf(min(0, 45)), min(0, 15));
  });

  group('planSeek', () {
    test('seeks in place for a short seek on a seekable stream', () {
      final reopened = timeline(streamStart: programStart.add(min(30)));

      final seek = reopened.planSeek(
        min(30, 50),
        from: min(30, 20),
        streamSeekable: true,
      );

      expect(seek, isA<CatchupInStreamSeek>());
      expect((seek! as CatchupInStreamSeek).streamPosition, min(0, 50));
    });

    test('reopens at the target minute for a long seek', () {
      final seek = timeline().planSeek(
        min(45, 30),
        from: min(5),
        streamSeekable: true,
      );

      expect(seek, isA<CatchupReopen>());
      final reopen = seek! as CatchupReopen;
      expect(reopen.start, programStart.add(min(45)));
      expect(reopen.duration, min(15));
    });

    test('reopens for a short seek back past the open stream start', () {
      final reopened = timeline(streamStart: programStart.add(min(30)));

      final seek = reopened.planSeek(
        min(29, 50),
        from: min(30, 5),
        streamSeekable: true,
      );

      expect((seek! as CatchupReopen).start, programStart.add(min(29)));
    });

    test('reopens even a short seek when the stream cannot seek', () {
      final back = timeline().planSeek(
        min(10, 10),
        from: min(10, 20),
        streamSeekable: false,
      );
      final forward = timeline().planSeek(
        min(10, 30),
        from: min(10, 20),
        streamSeekable: false,
      );

      expect((back! as CatchupReopen).start, programStart.add(min(10)));
      // Flooring would land back on the current minute, so a forward skip
      // moves on to the next one instead.
      expect((forward! as CatchupReopen).start, programStart.add(min(11)));
    });

    group('with the player reporting its buffer', () {
      // Opened at 30:00, buffered from 30:00 to 33:00 of the programme.
      final reopened = timeline(streamStart: programStart.add(min(30)));
      final buffered = PlaybackSeekWindow([
        (start: Duration.zero, end: min(3)),
      ]);

      test('seeks in place to a buffered target at any distance', () {
        final seek = reopened.planSeek(
          min(32, 30),
          from: min(30, 5),
          streamSeekable: true,
          buffered: buffered,
        );

        expect((seek! as CatchupInStreamSeek).streamPosition, min(2, 30));
      });

      test('waits for a target a short way past the buffer being played', () {
        final seek = reopened.planSeek(
          min(33, 20),
          from: min(33),
          streamSeekable: true,
          buffered: buffered,
        );

        final wait = seek! as CatchupBufferWait;
        expect(wait.streamPosition, min(3, 20));
        expect(wait.bufferEnd, min(3));
        // If the buffer doesn't get there in time, it reopens a minute on,
        // since the target's own minute is where it's already playing.
        expect(wait.reopen?.start, programStart.add(min(34)));
      });

      test('reopens a target more than a minute past the buffer', () {
        final seek = reopened.planSeek(
          min(34, 30),
          from: min(33),
          streamSeekable: true,
          buffered: buffered,
        );

        expect(seek, isA<CatchupReopen>());
      });

      test('reopens rather than waiting on a buffer it is not playing in', () {
        final seek = reopened.planSeek(
          min(31, 45),
          from: min(31, 30),
          streamSeekable: true,
          buffered: PlaybackSeekWindow([
            (start: Duration.zero, end: min(1)),
            (start: min(2), end: min(3)),
          ]),
        );

        expect(seek, isA<CatchupReopen>());
      });

      test('reopens a seek back past what is buffered without waiting', () {
        final seek = reopened.planSeek(
          min(30, 30),
          from: min(32, 30),
          streamSeekable: true,
          buffered: PlaybackSeekWindow([(start: min(2), end: min(3))]),
        );

        expect(seek, isA<CatchupReopen>());
      });

      test('waits on a stream that has only just opened', () {
        final seek = reopened.planSeek(
          min(30, 10),
          from: min(30),
          streamSeekable: false,
          buffered: const PlaybackSeekWindow([]),
        );

        final wait = seek! as CatchupBufferWait;
        expect(wait.streamPosition, const Duration(seconds: 10));
        expect(wait.bufferEnd, Duration.zero);
      });

      test('seeks in place inside the buffer even when the stream cannot '
          'seek', () {
        final seek = reopened.planSeek(
          min(31),
          from: min(31, 30),
          streamSeekable: false,
          buffered: buffered,
        );

        expect((seek! as CatchupInStreamSeek).streamPosition, min(1));
      });
    });

    test('has nothing to do at the programme edges', () {
      expect(
        timeline().planSeek(min(60), from: min(60), streamSeekable: false),
        isNull,
      );
      expect(
        timeline().planSeek(
          min(60),
          from: min(59, 30),
          streamSeekable: false,
        ),
        isNull,
      );
    });
  });
}

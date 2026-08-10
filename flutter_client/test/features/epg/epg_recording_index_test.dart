import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/epg/epg_recording_index.dart';
import 'package:m3u_tv/features/epg/epg_recording_state.dart';
import 'package:m3u_tv/services/domain_models.dart';

void main() {
  DateTime t(int h, [int m = 0, int s = 0]) =>
      DateTime.utc(2026, 8, 10, h, m, s);

  DvrRecording rec({
    required String uuid,
    required DvrRecordingStatus status,
    required int channelId,
    required DateTime start,
    required DateTime end,
  }) => DvrRecording(
    uuid: uuid,
    title: 'Test $uuid',
    status: status,
    channelId: channelId,
    scheduledStart: start,
    scheduledEnd: end,
  );

  group('EpgRecordingIndex', () {
    test('empty constant returns none for any programme', () {
      const index = EpgRecordingIndex.empty;
      expect(
        index.stateFor(channelId: 1, programStart: t(10), programEnd: t(11)),
        EpgRecordingState.none,
      );
    });

    test('empty recordings list returns empty (and none)', () {
      final index = EpgRecordingIndex.fromRecordings(const <DvrRecording>[]);
      expect(identical(index, EpgRecordingIndex.empty), isTrue);
      expect(
        index.stateFor(channelId: 1, programStart: t(10), programEnd: t(11)),
        EpgRecordingState.none,
      );
    });

    test(
      'exact-match window: scheduled recording matches programme exactly',
      () {
        final r = rec(
          uuid: '1',
          status: DvrRecordingStatus.scheduled,
          channelId: 1,
          start: t(10),
          end: t(11),
        );
        final index = EpgRecordingIndex.fromRecordings(<DvrRecording>[r]);
        expect(
          index.stateFor(channelId: 1, programStart: t(10), programEnd: t(11)),
          EpgRecordingState.scheduled,
        );
      },
    );

    test('padded window (recording wider than programme both sides) still '
        'matches', () {
      final r = rec(
        uuid: '1',
        status: DvrRecordingStatus.scheduled,
        channelId: 1,
        start: t(9, 59, 30),
        end: t(11, 0, 30),
      );
      final index = EpgRecordingIndex.fromRecordings(<DvrRecording>[r]);
      expect(
        index.stateFor(channelId: 1, programStart: t(10), programEnd: t(11)),
        EpgRecordingState.scheduled,
      );
    });

    test('CRITICAL: adjacent NEXT programme does NOT match (no false '
        'positive)', () {
      final r = rec(
        uuid: '1',
        status: DvrRecordingStatus.scheduled,
        channelId: 1,
        start: t(9, 59, 30),
        end: t(11, 0, 30),
      );
      final index = EpgRecordingIndex.fromRecordings(<DvrRecording>[r]);
      expect(
        index.stateFor(channelId: 1, programStart: t(11), programEnd: t(12)),
        EpgRecordingState.none,
      );
    });

    test('CRITICAL: adjacent PREVIOUS programme does NOT match either '
        'direction', () {
      final r = rec(
        uuid: '1',
        status: DvrRecordingStatus.scheduled,
        channelId: 1,
        start: t(10, 59, 30),
        end: t(12, 0, 30),
      );
      final index = EpgRecordingIndex.fromRecordings(<DvrRecording>[r]);
      expect(
        index.stateFor(channelId: 1, programStart: t(10), programEnd: t(11)),
        EpgRecordingState.none,
      );
    });

    test('heavily-padded recording (10 min each side) still rejects '
        'adjacent programme', () {
      final r = rec(
        uuid: '1',
        status: DvrRecordingStatus.scheduled,
        channelId: 1,
        start: t(9, 50),
        end: t(11, 10),
      );
      final index = EpgRecordingIndex.fromRecordings(<DvrRecording>[r]);
      expect(
        index.stateFor(channelId: 1, programStart: t(11), programEnd: t(12)),
        EpgRecordingState.none,
      );
    });

    test('heavily-padded recording still matches its own programme', () {
      final r = rec(
        uuid: '1',
        status: DvrRecordingStatus.scheduled,
        channelId: 1,
        start: t(9, 50),
        end: t(11, 10),
      );
      final index = EpgRecordingIndex.fromRecordings(<DvrRecording>[r]);
      expect(
        index.stateFor(channelId: 1, programStart: t(10), programEnd: t(11)),
        EpgRecordingState.scheduled,
      );
    });

    test('wrong channel does not match', () {
      final r = rec(
        uuid: '1',
        status: DvrRecordingStatus.scheduled,
        channelId: 7,
        start: t(10),
        end: t(11),
      );
      final index = EpgRecordingIndex.fromRecordings(<DvrRecording>[r]);
      expect(
        index.stateFor(channelId: 99, programStart: t(10), programEnd: t(11)),
        EpgRecordingState.none,
      );
    });

    test('status scheduled maps to scheduled', () {
      final r = rec(
        uuid: '1',
        status: DvrRecordingStatus.scheduled,
        channelId: 1,
        start: t(10),
        end: t(11),
      );
      final index = EpgRecordingIndex.fromRecordings(<DvrRecording>[r]);
      expect(
        index.stateFor(channelId: 1, programStart: t(10), programEnd: t(11)),
        EpgRecordingState.scheduled,
      );
    });

    test('status recording maps to recording', () {
      final r = rec(
        uuid: '1',
        status: DvrRecordingStatus.recording,
        channelId: 1,
        start: t(10),
        end: t(11),
      );
      final index = EpgRecordingIndex.fromRecordings(<DvrRecording>[r]);
      expect(
        index.stateFor(channelId: 1, programStart: t(10), programEnd: t(11)),
        EpgRecordingState.recording,
      );
    });

    test('status postProcessing maps to recording (still in-flight)', () {
      final r = rec(
        uuid: '1',
        status: DvrRecordingStatus.postProcessing,
        channelId: 1,
        start: t(10),
        end: t(11),
      );
      final index = EpgRecordingIndex.fromRecordings(<DvrRecording>[r]);
      expect(
        index.stateFor(channelId: 1, programStart: t(10), programEnd: t(11)),
        EpgRecordingState.recording,
      );
    });

    test('terminal statuses (completed/failed/cancelled/deleted/unknown) '
        'skipped at build time', () {
      const terminals = <DvrRecordingStatus>[
        DvrRecordingStatus.completed,
        DvrRecordingStatus.failed,
        DvrRecordingStatus.cancelled,
        DvrRecordingStatus.deleted,
        DvrRecordingStatus.unknown,
      ];
      for (final status in terminals) {
        final r = rec(
          uuid: '1',
          status: status,
          channelId: 1,
          start: t(10),
          end: t(11),
        );
        final index = EpgRecordingIndex.fromRecordings(<DvrRecording>[r]);
        expect(
          index.stateFor(channelId: 1, programStart: t(10), programEnd: t(11)),
          EpgRecordingState.none,
          reason: 'status $status should not produce an indicator',
        );
        expect(
          identical(index, EpgRecordingIndex.empty),
          isTrue,
          reason: 'all-skipped index should be the empty sentinel',
        );
      }
    });

    test('recording wins over scheduled when both match same programme', () {
      final scheduled = rec(
        uuid: 'sched',
        status: DvrRecordingStatus.scheduled,
        channelId: 1,
        start: t(10),
        end: t(11),
      );
      final recording = rec(
        uuid: 'live',
        status: DvrRecordingStatus.recording,
        channelId: 1,
        start: t(10),
        end: t(11),
      );
      final index = EpgRecordingIndex.fromRecordings(<DvrRecording>[
        scheduled,
        recording,
      ]);
      expect(
        index.stateFor(channelId: 1, programStart: t(10), programEnd: t(11)),
        EpgRecordingState.recording,
      );
    });

    test(
      'postProcessing wins over scheduled when both match same programme',
      () {
        final scheduled = rec(
          uuid: 'sched',
          status: DvrRecordingStatus.scheduled,
          channelId: 1,
          start: t(10),
          end: t(11),
        );
        final postProc = rec(
          uuid: 'post',
          status: DvrRecordingStatus.postProcessing,
          channelId: 1,
          start: t(10),
          end: t(11),
        );
        final index = EpgRecordingIndex.fromRecordings(<DvrRecording>[
          scheduled,
          postProc,
        ]);
        expect(
          index.stateFor(channelId: 1, programStart: t(10), programEnd: t(11)),
          EpgRecordingState.recording,
        );
      },
    );

    test('null channelId skipped safely', () {
      final r = DvrRecording(
        uuid: '1',
        title: 'No channel',
        status: DvrRecordingStatus.scheduled,
        scheduledStart: t(10),
        scheduledEnd: t(11),
      );
      final index = EpgRecordingIndex.fromRecordings(<DvrRecording>[r]);
      expect(
        index.stateFor(channelId: 1, programStart: t(10), programEnd: t(11)),
        EpgRecordingState.none,
      );
    });

    test('null scheduledStart skipped safely', () {
      final r = DvrRecording(
        uuid: '1',
        title: 'No start',
        status: DvrRecordingStatus.scheduled,
        channelId: 1,
        scheduledEnd: t(11),
      );
      final index = EpgRecordingIndex.fromRecordings(<DvrRecording>[r]);
      expect(
        index.stateFor(channelId: 1, programStart: t(10), programEnd: t(11)),
        EpgRecordingState.none,
      );
    });

    test('null scheduledEnd skipped safely', () {
      final r = DvrRecording(
        uuid: '1',
        title: 'No end',
        status: DvrRecordingStatus.scheduled,
        channelId: 1,
        scheduledStart: t(10),
      );
      final index = EpgRecordingIndex.fromRecordings(<DvrRecording>[r]);
      expect(
        index.stateFor(channelId: 1, programStart: t(10), programEnd: t(11)),
        EpgRecordingState.none,
      );
    });

    test('null times on all three fields still safe', () {
      const r = DvrRecording(
        uuid: '1',
        title: 'Nothing known',
        status: DvrRecordingStatus.scheduled,
      );
      final index = EpgRecordingIndex.fromRecordings(<DvrRecording>[r]);
      expect(
        index.stateFor(channelId: 1, programStart: t(10), programEnd: t(11)),
        EpgRecordingState.none,
      );
    });

    test('invalid recording window (start >= end) skipped safely', () {
      final r = rec(
        uuid: '1',
        status: DvrRecordingStatus.scheduled,
        channelId: 1,
        start: t(11),
        end: t(10),
      );
      final index = EpgRecordingIndex.fromRecordings(<DvrRecording>[r]);
      expect(
        index.stateFor(channelId: 1, programStart: t(10), programEnd: t(11)),
        EpgRecordingState.none,
      );
    });

    test('invalid programme window (end <= start) returns none without '
        'scanning', () {
      final r = rec(
        uuid: '1',
        status: DvrRecordingStatus.scheduled,
        channelId: 1,
        start: t(10),
        end: t(11),
      );
      final index = EpgRecordingIndex.fromRecordings(<DvrRecording>[r]);
      expect(
        index.stateFor(channelId: 1, programStart: t(11), programEnd: t(10)),
        EpgRecordingState.none,
      );
    });

    test('mixed channels and statuses resolve correctly across a realistic '
        'grid snapshot', () {
      final ch1Morning = rec(
        uuid: '1',
        status: DvrRecordingStatus.scheduled,
        channelId: 1,
        start: t(10),
        end: t(11),
      );
      final ch1Afternoon = rec(
        uuid: '2',
        status: DvrRecordingStatus.recording,
        channelId: 1,
        start: t(14),
        end: t(15),
      );
      final ch2Scheduled = rec(
        uuid: '3',
        status: DvrRecordingStatus.scheduled,
        channelId: 2,
        start: t(10),
        end: t(11),
      );
      final ch3Completed = rec(
        uuid: '4',
        status: DvrRecordingStatus.completed,
        channelId: 3,
        start: t(10),
        end: t(11),
      );
      final index = EpgRecordingIndex.fromRecordings(<DvrRecording>[
        ch1Morning,
        ch1Afternoon,
        ch2Scheduled,
        ch3Completed,
      ]);

      expect(
        index.stateFor(channelId: 1, programStart: t(10), programEnd: t(11)),
        EpgRecordingState.scheduled,
      );
      expect(
        index.stateFor(channelId: 1, programStart: t(14), programEnd: t(15)),
        EpgRecordingState.recording,
      );
      expect(
        index.stateFor(channelId: 2, programStart: t(10), programEnd: t(11)),
        EpgRecordingState.scheduled,
      );
      expect(
        index.stateFor(channelId: 3, programStart: t(10), programEnd: t(11)),
        EpgRecordingState.none,
      );
      expect(
        index.stateFor(channelId: 1, programStart: t(12), programEnd: t(13)),
        EpgRecordingState.none,
      );
    });

    test('regression: 45s adjacent programme under default 30s padding does '
        'NOT match', () {
      final r = rec(
        uuid: '1',
        status: DvrRecordingStatus.scheduled,
        channelId: 1,
        start: t(9, 59, 30),
        end: t(11, 0, 30),
      );
      final index = EpgRecordingIndex.fromRecordings(<DvrRecording>[r]);
      expect(
        index.stateFor(
          channelId: 1,
          programStart: t(11),
          programEnd: t(11, 0, 45),
        ),
        EpgRecordingState.none,
        reason:
            'coverage = 30s/45s = 0.667 < 0.8 threshold; midpoint would '
            'false-match because programme midpoint 11:00:22.5 falls inside '
            'recording window [9:59:30, 11:00:30]',
      );
    });

    test('regression: 15-min adjacent programme under heavy 10-min padding '
        'does NOT match', () {
      final r = rec(
        uuid: '1',
        status: DvrRecordingStatus.scheduled,
        channelId: 1,
        start: t(9, 50),
        end: t(11, 10),
      );
      final index = EpgRecordingIndex.fromRecordings(<DvrRecording>[r]);
      expect(
        index.stateFor(
          channelId: 1,
          programStart: t(11),
          programEnd: t(11, 15),
        ),
        EpgRecordingState.none,
        reason:
            'coverage = 10min/15min = 0.667 < 0.8 threshold; midpoint '
            'would false-match because programme midpoint 11:07:30 falls '
            'inside recording window [9:50, 11:10]',
      );
    });
  });
}

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/xtream_service.dart';

DvrRecording _recording(int n) => DvrRecording(
  uuid: 'rec-$n',
  title: 'Recording $n',
  status: DvrRecordingStatus.completed,
);

List<DvrRecording> _range(int from, int count) => [
  for (var i = from; i < from + count; i++) _recording(i),
];

void main() {
  const pageSize = XtreamService.dvrRecordingsPageSize;

  group('collectDvrRecordingPages', () {
    test('requests pages until a short one and returns them all', () async {
      final offsets = <int>[];
      final fetch = await XtreamService.collectDvrRecordingPages((
        offset,
      ) async {
        offsets.add(offset);
        return offset == 0 ? _range(0, pageSize) : _range(pageSize, 50);
      });

      expect(offsets, [0, pageSize]);
      expect(fetch.state, DvrRecordingsLoadState.loaded);
      expect(fetch.recordings, hasLength(pageSize + 50));
      expect(fetch.recordings.last.uuid, 'rec-${pageSize + 49}');
    });

    test(
      'keeps loaded pages and reports partial when a later page fails',
      () async {
        final fetch = await XtreamService.collectDvrRecordingPages((
          offset,
        ) async {
          if (offset == 0) return _range(0, pageSize);
          throw TimeoutException('slow');
        });

        expect(fetch.state, DvrRecordingsLoadState.partial);
        expect(fetch.recordings, hasLength(pageSize));
      },
    );

    test(
      'reports offline when the first page cannot reach the server',
      () async {
        final fetch = await XtreamService.collectDvrRecordingPages(
          (_) async => throw TimeoutException('unreachable'),
        );

        expect(fetch.state, DvrRecordingsLoadState.offline);
        expect(fetch.failed, isTrue);
        expect(fetch.recordings, isEmpty);
      },
    );

    test('reports an error when the server answers with one', () async {
      final fetch = await XtreamService.collectDvrRecordingPages(
        (_) async => throw XtreamHttpException(
          statusCode: 500,
          method: 'GET',
          uri: Uri.parse('https://xtream.example/player_api.php'),
        ),
      );

      expect(fetch.state, DvrRecordingsLoadState.error);
    });

    test(
      'stops when a page adds nothing new (server ignores offset)',
      () async {
        var calls = 0;
        final fetch = await XtreamService.collectDvrRecordingPages((_) async {
          calls++;
          return _range(0, pageSize);
        });

        expect(calls, 2);
        expect(fetch.state, DvrRecordingsLoadState.loaded);
        expect(fetch.recordings, hasLength(pageSize));
      },
    );
  });

  test('dvrRecordingStatusToWire matches the editor enum values', () {
    expect(
      dvrRecordingStatusToWire(DvrRecordingStatus.postProcessing),
      'post_processing',
    );
    expect(dvrRecordingStatusToWire(DvrRecordingStatus.unknown), isNull);
  });
}

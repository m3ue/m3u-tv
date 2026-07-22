import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/domain_models.dart';

/// Regression coverage for the `deleted` pseudo-status carried by a
/// `dvr.status` push when a recording is removed server-side. It isn't a
/// real DvrRecordingStatus value the REST endpoints ever return — only
/// AppStateController._onDvrStatusPush acts on it, by dropping the
/// recording locally instead of refreshing its (now 404) detail.
void main() {
  test(
    'dvrRecordingStatusFromWire maps "deleted" to DvrRecordingStatus.deleted',
    () {
      expect(dvrRecordingStatusFromWire('deleted'), DvrRecordingStatus.deleted);
      expect(dvrRecordingStatusFromWire('Deleted'), DvrRecordingStatus.deleted);
    },
  );

  test('DvrRecording.fromXtream parses a deletion push payload', () {
    final recording = DvrRecording.fromXtream({
      'uuid': 'rec-1',
      'title': 'Evening News',
      'status': 'deleted',
      'channel_id': 101,
      'channel_name': 'News 24',
    });

    expect(recording.uuid, 'rec-1');
    expect(recording.status, DvrRecordingStatus.deleted);
    expect(recording.channelId, 101);
    expect(recording.isInProgress, isFalse);
  });
}

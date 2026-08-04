import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/domain_models.dart';

void main() {
  // The `_asNullableString` helper is private, so these tests exercise it
  // indirectly through `DvrRecording.fromXtream`, which is its primary user.
  // The behavior we care about: URL-like fields must end up null rather than
  // a stringified "[]" / "{}" / "true" when the backend returns a non-string
  // JSON value.
  group('DvrRecording.fromXtream non-string hardening', () {
    Map<String, Object?> jsonWith(Object? edlUrl) => <String, Object?>{
      'uuid': 'rec-1',
      'title': 'Hardening fixture',
      'status': 'completed',
      'stream_url': 'https://example.com/stream.mp4',
      'edl_url': edlUrl,
      'channel_icon': edlUrl,
    };

    test('empty list maps to null (was previously the literal "[]")', () {
      final recording = DvrRecording.fromXtream(jsonWith(<Object?>[]));
      expect(recording.edlUrl, isNull);
      expect(recording.channelIconUrl, isNull);
    });

    test('non-empty list maps to null (was previously "[a, b]")', () {
      final recording = DvrRecording.fromXtream(
        jsonWith(<Object?>['https://example.com/edl']),
      );
      expect(recording.edlUrl, isNull);
      expect(recording.channelIconUrl, isNull);
    });

    test('Map maps to null (was previously the literal "{...}")', () {
      final recording = DvrRecording.fromXtream(
        jsonWith(<String, Object?>{'host': 'evil'}),
      );
      expect(recording.edlUrl, isNull);
      expect(recording.channelIconUrl, isNull);
    });

    test('bool maps to null', () {
      final recording = DvrRecording.fromXtream(jsonWith(true));
      expect(recording.edlUrl, isNull);
      expect(recording.channelIconUrl, isNull);
    });

    test('null maps to null', () {
      final recording = DvrRecording.fromXtream(jsonWith(null));
      expect(recording.edlUrl, isNull);
      expect(recording.channelIconUrl, isNull);
    });

    test('String round-trips unchanged', () {
      const url = 'https://m3u.bearald.com/dvr/abc/edl';
      final recording = DvrRecording.fromXtream(jsonWith(url));
      expect(recording.edlUrl, url);
      expect(recording.channelIconUrl, url);
    });

    test('empty String maps to null', () {
      final recording = DvrRecording.fromXtream(jsonWith(''));
      expect(recording.edlUrl, isNull);
    });

    test('int stringifies (numeric IDs still come through as raw numbers)', () {
      final recording = DvrRecording.fromXtream(jsonWith(42));
      expect(recording.edlUrl, '42');
      expect(recording.channelIconUrl, '42');
    });

    test('double stringifies', () {
      final recording = DvrRecording.fromXtream(jsonWith(3.14));
      expect(recording.edlUrl, '3.14');
      expect(recording.channelIconUrl, '3.14');
    });
  });
}

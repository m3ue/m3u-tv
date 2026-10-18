import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/introdb_service.dart';

void main() {
  group('IntroDbSegments.fromJson (v4 bodies)', () {
    test('reads the first intro and credits segments of a MediaResponse', () {
      final segments = IntroDbSegments.fromJson({
        'tvdb_id': 81189,
        'type': 'tv',
        'season': 1,
        'episode': 1,
        'intro': [
          {'start_ms': 228664, 'end_ms': 246143},
          {'start_ms': 300000, 'end_ms': 310000},
        ],
        'recap': [
          {'start_ms': 0, 'end_ms': 20000},
        ],
        'credits': [
          {'start_ms': 3431000, 'end_ms': null},
        ],
      });

      expect(segments.isEmpty, isFalse);
      expect(segments.intro?.startMs, 228664);
      expect(segments.intro?.endMs, 246143);
      expect(segments.credits?.startMs, 3431000);
      expect(segments.credits?.endMs, isNull);
    });

    test('keeps a null intro start (start of media)', () {
      final segments = IntroDbSegments.fromJson({
        'tvdb_id': 169,
        'type': 'movie',
        'intro': [
          {'start_ms': null, 'end_ms': 23000},
        ],
      });

      expect(segments.intro?.startMs, isNull);
      expect(segments.intro?.endMs, 23000);
      expect(segments.credits, isNull);
    });

    test('treats the episode-list fallback as no data', () {
      final segments = IntroDbSegments.fromJson({
        'tvdb_id': 71663,
        'type': 'tv',
        'episodes': [
          {'season': 1, 'episode': 1, 'total_submission_count': 4},
        ],
      });

      expect(segments.isEmpty, isTrue);
    });
  });
}

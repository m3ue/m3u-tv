import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/catalog_db/catalog_codec.dart';
import 'package:m3u_tv/services/domain_models.dart';

void main() {
  group('series codec', () {
    test('round-trips the fields the Home spotlight shows', () {
      final series = Series.fromXtream(const {
        'series_id': 3,
        'name': 'Severance',
        'cover': 'http://img/cover.jpg',
        'backdrop_path': ['http://img/sev.jpg'],
        'clearlogo': 'http://img/sev-logo.png',
        'plot': 'Work-life balance.',
        'rating': '8.7',
        'mpaa_rating': 'TV-MA',
        'releaseDate': '2022-02-18',
        'genre': 'Drama, Mystery',
        'episode_run_time': '55',
      });

      final decoded = decodeSeries(encodeSeries(series));

      expect(decoded.clearLogoUrl, 'http://img/sev-logo.png');
      expect(decoded.contentRating, 'TV-MA');
      expect(decoded.year, '2022');
      expect(decoded.genre, 'Drama, Mystery');
      expect(decoded.episodeRunTime, 55);
      expect(decoded.rating, 8.7);
      expect(decoded.backdropUrl, 'http://img/sev.jpg');
    });

    test('treats blank genre and a zero runtime as absent', () {
      final series = Series.fromXtream(const {
        'series_id': 4,
        'name': 'Unenriched',
        'genre': '',
        'episode_run_time': '0',
      });

      expect(series.genre, isNull);
      expect(series.episodeRunTime, isNull);
      expect(encodeSeries(series).containsKey('episode_run_time'), isFalse);
    });
  });
}

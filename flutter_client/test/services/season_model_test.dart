import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/domain_models.dart';

void main() {
  group('Season.fromXtream', () {
    test('parses cover and cover_big when present', () {
      final season = Season.fromXtream(<String, Object?>{
        'season_number': 3,
        'name': 'Season 3',
        'episode_count': 12,
        'cover': 'https://image.tmdb.org/t/p/w500/abc.jpg',
        'cover_big': 'https://image.tmdb.org/t/p/original/abc.jpg',
      });
      expect(season.number, 3);
      expect(season.name, 'Season 3');
      expect(season.episodeCount, 12);
      expect(season.coverUrl, 'https://image.tmdb.org/t/p/w500/abc.jpg');
      expect(season.coverBigUrl, 'https://image.tmdb.org/t/p/original/abc.jpg');
    });

    test('cover fields are null when missing from JSON', () {
      final season = Season.fromXtream(<String, Object?>{
        'season_number': 1,
        'episode_count': 8,
      });
      expect(season.coverUrl, isNull);
      expect(season.coverBigUrl, isNull);
    });

    test('cover fields are null when JSON values are empty strings', () {
      final season = Season.fromXtream(<String, Object?>{
        'season_number': 2,
        'episode_count': 10,
        'cover': '',
        'cover_big': '',
      });
      expect(season.coverUrl, isNull);
      expect(season.coverBigUrl, isNull);
    });

    test('falls back to "Season N" name when name missing', () {
      final season = Season.fromXtream(<String, Object?>{
        'season_number': 5,
        'episode_count': 6,
      });
      expect(season.name, 'Season 5');
    });

    test('const constructor accepts nullable cover fields', () {
      const season = Season(number: 1, name: 'Season 1');
      expect(season.coverUrl, isNull);
      expect(season.coverBigUrl, isNull);
      expect(season.episodeCount, 0);
    });
  });
}

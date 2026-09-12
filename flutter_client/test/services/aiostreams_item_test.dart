import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/aiostreams_api_service.dart';

void main() {
  group('AIOStreamsItem.fromJson - TMDB-enriched meta', () {
    Map<String, dynamic> movieMeta() => <String, dynamic>{
      'id': 'tmdb:603',
      'type': 'movie',
      'name': 'The Matrix',
      'poster': 'https://img/poster.jpg',
      'background': 'https://img/bg.jpg',
      'description': 'A hacker learns the truth.',
      'year': 1999,
      'imdbRating': '8.7',
      'genres': ['Action', 'Sci-Fi'],
      'runtime': '136 min',
      // Stremio credit fields (list-of-strings / list-of-maps / single string).
      'cast': ['Keanu Reeves', 'Laurence Fishburne'],
      'director': ['Lana Wachowski', 'Lilly Wachowski'],
      'writer': 'The Wachowskis',
      // Editor TMDB enrichment.
      'clearlogo': 'https://img/logo.png',
      'cast_list': [
        {
          'id': 6384,
          'name': 'Keanu Reeves',
          'character': 'Neo',
          'photo': 'https://img/keanu.jpg',
        },
      ],
    };

    test('parses clearlogo, rich cast, joined credits and runtime', () {
      final item = AIOStreamsItem.fromJson(movieMeta());

      expect(item.clearLogoUrl, 'https://img/logo.png');
      expect(item.richCast, isNotNull);
      expect(item.richCast!.single.name, 'Keanu Reeves');
      expect(item.richCast!.single.character, 'Neo');
      expect(item.cast, 'Keanu Reeves, Laurence Fishburne');
      expect(item.director, 'Lana Wachowski, Lilly Wachowski');
      expect(item.writer, 'The Wachowskis');
      expect(item.runtime, '136 min');
    });

    test('falls back to the Stremio `logo` when no `clearlogo` is present', () {
      final json = movieMeta()..remove('clearlogo');
      json['logo'] = 'https://img/stremio-logo.png';

      final item = AIOStreamsItem.fromJson(json);
      expect(item.clearLogoUrl, 'https://img/stremio-logo.png');
    });

    test('leaves richCast null and cast set when only Stremio names exist', () {
      final json = movieMeta()..remove('cast_list');
      final item = AIOStreamsItem.fromJson(json);

      expect(item.richCast, isNull);
      expect(item.cast, 'Keanu Reeves, Laurence Fishburne');
    });

    test('parses the enriched seasons array onto Season records', () {
      final item = AIOStreamsItem.fromJson(<String, dynamic>{
        'id': 'tt0944947',
        'type': 'series',
        'name': 'Game of Thrones',
        'videos': [
          {
            'id': 'tt0944947:1:1',
            'title': 'Winter Is Coming',
            'season': 1,
            'episode': 1,
            'rating': 8.9,
          },
        ],
        'seasons': [
          {
            'season_number': 1,
            'name': 'Season 1',
            'overview': 'The first season.',
            'episode_count': 10,
            'air_date': '2011-04-17',
            'cover_big': 'https://img/s1.jpg',
          },
        ],
      });

      expect(item.seasons, hasLength(1));
      expect(item.seasons.single.number, 1);
      expect(item.seasons.single.overview, 'The first season.');
      expect(item.seasons.single.coverUrl, 'https://img/s1.jpg');
      expect(item.videos.single.rating, 8.9);
    });

    test('seasons defaults to empty on a plain (unenriched) Stremio meta', () {
      final item = AIOStreamsItem.fromJson(<String, dynamic>{
        'id': 'tt1',
        'type': 'series',
        'name': 'Plain',
      });
      expect(item.seasons, isEmpty);
      expect(item.clearLogoUrl, isNull);
      expect(item.richCast, isNull);
    });

    test('parses the related array (tmdb: id form)', () {
      final json = movieMeta()
        ..['related'] = [
          {
            'id': 'tmdb:680',
            'type': 'movie',
            'name': 'Pulp Fiction',
            'poster': 'https://img/pulp.jpg',
          },
        ];
      final item = AIOStreamsItem.fromJson(json);

      expect(item.related, hasLength(1));
      expect(item.related!.single.id, 'tmdb:680');
      expect(item.related!.single.title, 'Pulp Fiction');
      expect(item.related!.single.posterUrl, 'https://img/pulp.jpg');
    });

    test('related is null when absent (no TMDB recommendations)', () {
      final item = AIOStreamsItem.fromJson(movieMeta());
      expect(item.related, isNull);
    });
  });
}

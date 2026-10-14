import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/catalog_db/catalog_codec.dart';
import 'package:m3u_tv/services/domain_models.dart';

void main() {
  group('channel codec', () {
    test('round-trips the channel number', () {
      final channel = Channel.fromXtream(const {
        'stream_id': 12,
        'name': 'BBC One',
        'num': 101,
      }, 'http://host/live/12.ts');

      final decoded = decodeChannel(encodeChannel(channel));

      expect(decoded.channelNumber, 101);
    });

    test('leaves an absent channel number absent', () {
      final channel = Channel.fromXtream(const {
        'stream_id': 13,
        'name': 'Unnumbered',
      }, 'http://host/live/13.ts');

      expect(encodeChannel(channel).containsKey('num'), isFalse);
      expect(decodeChannel(encodeChannel(channel)).channelNumber, isNull);
    });
  });

  group('vod codec', () {
    test('round-trips the release year', () {
      final item = VodItem.fromXtream(const {
        'stream_id': 7,
        'name': 'Dune',
        'year': 2021,
      }, 'http://host/movie/7.mkv');

      final decoded = decodeVod(encodeVod(item));

      expect(decoded.year, '2021');
    });

    test('round-trips the added timestamp', () {
      final item = VodItem.fromXtream(const {
        'stream_id': 9,
        'name': 'Dune',
        'added': '1700000000',
      }, 'http://host/movie/9.mkv');

      expect(item.addedAt, 1700000000);
      expect(decodeVod(encodeVod(item)).addedAt, 1700000000);
    });

    test('leaves an absent year absent', () {
      final item = VodItem.fromXtream(const {
        'stream_id': 8,
        'name': 'Undated',
      }, 'http://host/movie/8.mkv');

      expect(encodeVod(item).containsKey('year'), isFalse);
      expect(decodeVod(encodeVod(item)).year, isNull);
    });
  });

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

    test('round-trips last_modified and treats blank/zero as absent', () {
      final series = Series.fromXtream(const {
        'series_id': 5,
        'name': 'Andor',
        'last_modified': '1700000000',
      });
      final blank = Series.fromXtream(const {
        'series_id': 6,
        'name': 'Unknown',
        'last_modified': '',
      });
      final zero = Series.fromXtream(const {
        'series_id': 7,
        'name': 'Zero',
        'last_modified': '0',
      });

      expect(decodeSeries(encodeSeries(series)).lastModifiedAt, 1700000000);
      expect(blank.lastModifiedAt, isNull);
      expect(zero.lastModifiedAt, isNull);
      expect(encodeSeries(zero).containsKey('last_modified'), isFalse);
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

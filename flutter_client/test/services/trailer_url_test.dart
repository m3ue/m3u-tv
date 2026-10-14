import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/catalog_db/catalog_codec.dart';
import 'package:m3u_tv/services/domain_models.dart';

void main() {
  group('youtubeVideoId', () {
    test('accepts every YouTube link shape the editor or a provider sends', () {
      for (final value in [
        'dQw4w9WgXcQ',
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        'https://youtube.com/watch?v=dQw4w9WgXcQ&t=10',
        'https://m.youtube.com/watch?v=dQw4w9WgXcQ',
        'https://youtu.be/dQw4w9WgXcQ',
        'https://www.youtube.com/embed/dQw4w9WgXcQ',
        'https://www.youtube-nocookie.com/embed/dQw4w9WgXcQ',
        ' dQw4w9WgXcQ ',
      ]) {
        expect(youtubeVideoId(value), 'dQw4w9WgXcQ', reason: value);
      }
    });

    test('rejects blanks and non-YouTube links', () {
      for (final value in [
        null,
        '',
        '0',
        'not a trailer',
        'https://vimeo.com/123456789',
        'https://notyoutube.com/watch?v=dQw4w9WgXcQ',
        'https://www.youtube.com/watch?v=short',
      ]) {
        expect(youtubeVideoId(value), isNull, reason: '$value');
      }
    });
  });

  test('VodInfo.trailerUrl normalises a bare provider id', () {
    final vod = VodInfo.fromXtream(<String, Object?>{
      'info': <String, Object?>{
        'name': 'Inception',
        'youtube_trailer': 'YoHD9XEInc0',
      },
      'movie_data': <String, Object?>{'stream_id': 101},
    });

    expect(vod.trailerUrl, 'https://www.youtube.com/watch?v=YoHD9XEInc0');
  });

  test('VodInfo.trailerUrl is null when the editor sends null', () {
    final vod = VodInfo.fromXtream(<String, Object?>{
      'info': <String, Object?>{'name': 'Inception', 'youtube_trailer': null},
      'movie_data': <String, Object?>{'stream_id': 101},
    });

    expect(vod.trailerUrl, isNull);
  });

  test('Series and Season parse youtube_trailer, blank meaning none', () {
    final series = Series.fromXtream(const {
      'series_id': 7,
      'name': 'Andor',
      'youtube_trailer': 'https://www.youtube.com/watch?v=cKOegEuCcfw',
    });
    final season = Season.fromXtream(const {
      'season_number': 2,
      'youtube_trailer': 'https://youtu.be/dQw4w9WgXcQ',
    });
    final bareSeason = Season.fromXtream(const {
      'season_number': 3,
      'youtube_trailer': '',
    });

    expect(series.trailerUrl, 'https://www.youtube.com/watch?v=cKOegEuCcfw');
    expect(season.trailerUrl, 'https://www.youtube.com/watch?v=dQw4w9WgXcQ');
    expect(bareSeason.trailerUrl, isNull);
  });

  test('Series.trailerUrl survives the catalog cache round-trip', () {
    final series = Series.fromXtream(const {
      'series_id': 7,
      'name': 'Andor',
      'youtube_trailer': 'cKOegEuCcfw',
    });

    expect(
      decodeSeries(encodeSeries(series)).trailerUrl,
      'https://www.youtube.com/watch?v=cKOegEuCcfw',
    );
  });
}

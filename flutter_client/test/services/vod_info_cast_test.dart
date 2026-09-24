import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/domain_models.dart';

void main() {
  Map<String, Object?> vodPayload(Object? castList) => <String, Object?>{
    'info': <String, Object?>{
      'tmdb_id': 27205,
      'name': 'Inception',
    },
    'movie_data': <String, Object?>{
      'stream_id': 101,
      'name': 'Inception',
      if (castList != const _Omitted()) 'cast_list': castList,
    },
  };

  test('VodInfo.richCast is parsed when cast_list is a list of maps', () {
    final vod = VodInfo.fromXtream(
      vodPayload(<Object?>[
        <String, Object?>{
          'id': 1,
          'name': 'Leonardo DiCaprio',
          'character': 'Cobb',
        },
        <String, Object?>{
          'id': 2,
          'name': 'Joseph Gordon-Levitt',
          'character': 'Arthur',
        },
      ]),
    );

    expect(vod.richCast, isNotNull);
    expect(vod.richCast!.length, 2);
    expect(vod.richCast![0].name, 'Leonardo DiCaprio');
    expect(vod.richCast![0].character, 'Cobb');
    expect(vod.richCast![1].name, 'Joseph Gordon-Levitt');
  });

  test('VodInfo.richCast is null when cast_list is missing entirely', () {
    final vod = VodInfo.fromXtream(vodPayload(const _Omitted()));
    expect(vod.richCast, isNull);
  });

  test('VodInfo.richCast is null when cast_list is an empty list', () {
    final vod = VodInfo.fromXtream(vodPayload(<Object?>[]));
    expect(vod.richCast, isNull);
  });

  test(
    'VodInfo.richCast is null when cast_list is the legacy comma-joined string',
    () {
      final vod = VodInfo.fromXtream(
        vodPayload('Leonardo DiCaprio, Joseph Gordon-Levitt'),
      );
      expect(vod.richCast, isNull);
    },
  );

  test(
    'VodInfo.richCast hydrates from the comma-separated `cast` field '
    'when cast_list is absent (chip row now renders)',
    () {
      final payload = <String, Object?>{
        'info': <String, Object?>{'name': 'Inception'},
        'movie_data': <String, Object?>{
          'stream_id': 101,
          'name': 'Inception',
          'cast': 'Leonardo DiCaprio, Joseph Gordon-Levitt',
        },
      };
      final vod = VodInfo.fromXtream(payload);
      // Legacy text field is still preserved for the credit-line fallback.
      expect(vod.cast, 'Leonardo DiCaprio, Joseph Gordon-Levitt');
      // The chip row now hydrates from the legacy string so older m3u-editor
      // builds (which emit only `cast`) display cast chips instead of hiding
      // the row.
      expect(vod.richCast, isNotNull);
      expect(vod.richCast!.length, 2);
      expect(vod.richCast![0].name, 'Leonardo DiCaprio');
      expect(vod.richCast![1].name, 'Joseph Gordon-Levitt');
    },
  );

  test(
    'VodInfo.richCast is null when cast_list contains only malformed entries',
    () {
      final vod = VodInfo.fromXtream(
        vodPayload(<Object?>[
          <String, Object?>{'name': ''},
          <String, Object?>{'name': '   '},
          <String, Object?>{},
        ]),
      );
      expect(vod.richCast, isNull);
    },
  );

  test(
    'VodInfo.richCast falls back to the comma-separated `cast` string '
    'when cast_list is absent (older m3u-editor shape)',
    () {
      // Mirrors the wire shape returned by m3u-editor v0.12.58-exp and other
      // Xtream-shaped providers that emit only the legacy `cast` string and
      // no TMDB-enriched `cast_list`.
      final payload = <String, Object?>{
        'info': <String, Object?>{
          'tmdb_id': 1191876,
          'name': 'From the Ashes',
          'cast': 'Jeanne Neilson, Paul du Toit, Syreeta Banks',
        },
        'movie_data': <String, Object?>{
          'stream_id': 4297782,
          'name': 'From the Ashes (2027)',
        },
      };
      final vod = VodInfo.fromXtream(payload);
      expect(vod.richCast, isNotNull);
      expect(vod.richCast!.length, 3);
      expect(vod.richCast![0].name, 'Jeanne Neilson');
      expect(vod.richCast![0].character, isNull);
      expect(vod.richCast![0].photo, isNull);
      expect(vod.richCast![1].name, 'Paul du Toit');
      expect(vod.richCast![2].name, 'Syreeta Banks');
    },
  );

  test(
    'VodInfo.richCast falls back to `actors` when `cast` is absent',
    () {
      final payload = <String, Object?>{
        'info': <String, Object?>{'name': 'Movie', 'actors': 'A, B, C'},
        'movie_data': <String, Object?>{'stream_id': 1, 'name': 'Movie'},
      };
      final vod = VodInfo.fromXtream(payload);
      expect(vod.richCast, isNotNull);
      expect(vod.richCast!.map((m) => m.name).toList(),
          <String>['A', 'B', 'C']);
    },
  );

  test(
    'VodInfo.richCast ignores the comma-separated string when cast_list '
    'is present-but-malformed (preserves legacy null behaviour)',
    () {
      // If the server mis-shapes cast_list (string instead of list), we do
      // NOT silently substitute the comma-separated `cast` string. We treat
      // it as no rich cast.
      final payload = <String, Object?>{
        'info': <String, Object?>{
          'cast': 'Leonardo DiCaprio, Joseph Gordon-Levitt',
        },
        'movie_data': <String, Object?>{
          'stream_id': 101,
          'name': 'Inception',
          'cast_list': 'Leonardo DiCaprio, Joseph Gordon-Levitt',
        },
      };
      final vod = VodInfo.fromXtream(payload);
      expect(vod.richCast, isNull);
    },
  );

  test(
    'VodInfo.richCast prefers cast_list over the comma-separated fallback',
    () {
      final payload = <String, Object?>{
        'info': <String, Object?>{
          'name': 'Inception',
          'cast': 'Anonymous A, Anonymous B',
        },
        'movie_data': <String, Object?>{
          'stream_id': 101,
          'name': 'Inception',
          'cast_list': <Object?>[
            <String, Object?>{'id': 1, 'name': 'Leonardo DiCaprio'},
          ],
        },
      };
      final vod = VodInfo.fromXtream(payload);
      expect(vod.richCast, isNotNull);
      expect(vod.richCast!.length, 1);
      expect(vod.richCast![0].name, 'Leonardo DiCaprio');
      expect(vod.richCast![0].id, 1);
    },
  );
}

class _Omitted {
  const _Omitted();
}

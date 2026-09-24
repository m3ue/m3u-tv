import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/domain_models.dart';

void main() {
  Map<String, Object?> seriesJson({
    Object? castList,
    bool includeCastList = true,
  }) => <String, Object?>{
    'series_id': 99,
    'name': 'Breaking Bad',
    if (includeCastList) 'cast_list': castList,
  };

  test('Series.richCast is parsed when cast_list is a list of maps', () {
    final series = Series.fromXtream(
      seriesJson(
        castList: <Object?>[
          <String, Object?>{
            'id': 17419,
            'name': 'Bryan Cranston',
            'character': 'Walter White',
          },
          <String, Object?>{
            'id': 17420,
            'name': 'Aaron Paul',
            'character': 'Jesse Pinkman',
          },
        ],
      ),
    );

    expect(series.richCast, isNotNull);
    expect(series.richCast!.length, 2);
    expect(series.richCast![0].name, 'Bryan Cranston');
    expect(series.richCast![1].name, 'Aaron Paul');
  });

  test('Series.richCast is null when cast_list is missing entirely', () {
    final series = Series.fromXtream(seriesJson(includeCastList: false));
    expect(series.richCast, isNull);
  });

  test('Series.richCast is null when cast_list is an empty list', () {
    final series = Series.fromXtream(seriesJson(castList: <Object?>[]));
    expect(series.richCast, isNull);
  });

  test('Series.richCast is null when cast_list is a comma-joined string', () {
    final series = Series.fromXtream(
      seriesJson(castList: 'Bryan Cranston, Aaron Paul'),
    );
    expect(series.richCast, isNull);
  });

  test(
    'Series.richCast falls back to the comma-separated `cast` string '
    'when cast_list is absent',
    () {
      final series = Series.fromXtream(<String, Object?>{
        'series_id': 99,
        'name': 'Breaking Bad',
        'cast': 'Bryan Cranston, Aaron Paul, Anna Gunn',
      });
      expect(series.richCast, isNotNull);
      expect(series.richCast!.length, 3);
      expect(series.richCast![0].name, 'Bryan Cranston');
      expect(series.richCast![0].character, isNull);
      expect(series.richCast![0].photo, isNull);
    },
  );
}

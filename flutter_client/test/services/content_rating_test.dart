import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/shared/item_meta_info.dart';

VodInfo _vod(Map<String, Object?> info) => VodInfo.fromXtream(<String, Object?>{
  'info': <String, Object?>{'name': 'Inception', ...info},
  'movie_data': <String, Object?>{'stream_id': 101},
});

void main() {
  test('VodInfo.contentRating is parsed from info.mpaa_rating', () {
    expect(_vod({'mpaa_rating': 'PG-13', 'age': '12+'}).contentRating, 'PG-13');
  });

  test('VodInfo.contentRating falls back to age when mpaa_rating is blank', () {
    expect(_vod({'mpaa_rating': '', 'age': '16+'}).contentRating, '16+');
  });

  test('VodInfo.contentRating treats blank and 0 as missing', () {
    expect(_vod({'mpaa_rating': ' ', 'age': '0'}).contentRating, isNull);
    expect(_vod({}).contentRating, isNull);
  });

  test('Series.contentRating is parsed from the get_series_info payload', () {
    final series = Series.fromXtream(<String, Object?>{
      'series_id': 7,
      'name': 'Andor',
      'mpaa_rating': 'TV-14',
    });

    expect(series.contentRating, 'TV-14');
  });

  testWidgets('ItemMetaInfo renders the rating chip right after the year', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ItemMetaInfo(
            name: 'Inception',
            year: '2010',
            contentRating: 'PG-13',
            chips: ['Sci-Fi'],
            hidePrimaryAction: true,
            buttonLabel: '',
            onPlay: null,
          ),
        ),
      ),
    );

    final yearX = tester.getTopLeft(find.text('2010')).dx;
    final ratingX = tester.getTopLeft(find.text('PG-13')).dx;
    final genreX = tester.getTopLeft(find.text('Sci-Fi')).dx;
    expect(yearX, lessThan(ratingX));
    expect(ratingX, lessThan(genreX));
  });
}

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/home/home_spotlight.dart';
import 'package:m3u_tv/features/home/home_spotlight_carousel.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/shared/meta_chip_data.dart';

void main() {
  VodItem movie(int id) => VodItem(
    id: id,
    name: 'Movie $id',
    streamUrl: 'http://example/$id.mkv',
    containerExtension: 'mkv',
  );

  Series series(int id) => Series(id: id, name: 'Series $id');

  Progress progress(int streamId) => Progress(
    viewerId: 'v',
    contentType: ContentType.vod,
    streamId: streamId,
    positionSeconds: 60,
    durationSeconds: 600,
  );

  List<String> keys(List<HomeSpotlightTarget> targets) =>
      targets.map((target) => target.key).toList();

  test('leads with Continue Watching, then interleaves movies and series', () {
    final targets = HomeSpotlightCarousel.buildTargets(
      progress: [progress(1)],
      movies: [movie(10), movie(11)],
      series: [series(20)],
    );

    expect(keys(targets), [
      ProgressSpotlightTarget(progress(1)).key,
      'vod:10',
      'series:20',
      'vod:11',
    ]);
  });

  test('caps Continue Watching at three and the whole carousel at eight', () {
    final targets = HomeSpotlightCarousel.buildTargets(
      progress: [for (var i = 1; i <= 5; i++) progress(i)],
      movies: [for (var i = 10; i < 14; i++) movie(i)],
      series: [for (var i = 20; i < 24; i++) series(i)],
    );

    expect(targets, hasLength(8));
    expect(targets.whereType<ProgressSpotlightTarget>(), hasLength(3));
    expect(keys(targets).sublist(3), [
      'vod:10',
      'series:20',
      'vod:11',
      'series:21',
      'vod:12',
    ]);
  });

  test('is empty with nothing to feature', () {
    expect(
      HomeSpotlightCarousel.buildTargets(
        progress: const [],
        movies: const [],
        series: const [],
      ),
      isEmpty,
    );
  });

  testWidgets('chips that do not fit whole are left out, not cut off', (
    tester,
  ) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 100),
            child: const OneLineChips(
              gap: 10,
              children: [
                SizedBox(key: Key('a'), width: 40, height: 20),
                SizedBox(key: Key('wide'), width: 60, height: 20),
                SizedBox(key: Key('b'), width: 40, height: 20),
              ],
            ),
          ),
        ),
      ),
    );

    expect(tester.getTopLeft(find.byKey(const Key('a'))).dx, 0);
    // 40 + 10 + 60 overflows 100, so the wide chip is skipped and the next
    // one that fits takes its place.
    expect(tester.getTopLeft(find.byKey(const Key('b'))).dx, 50);
    expect(tester.getSize(find.byType(OneLineChips)), const Size(90, 20));
    expect(tester.takeException(), isNull);
  });

  test('a long genre list keeps its first two genres', () {
    expect(
      shortSpotlightGenre(
        const MetaChipData.genre('Animation, Short, Action, Sci-Fi'),
      ).label,
      'Animation, Short',
    );
    expect(
      shortSpotlightGenre(const MetaChipData.genre('Drama')).label,
      'Drama',
    );
    expect(shortSpotlightGenre(const MetaChipData.year('2022')).label, '2022');
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/series/episode_player_args.dart';
import 'package:m3u_tv/services/domain_models.dart';

Episode _ep(int season, int number, {String? url = 'http://x/e.mp4'}) =>
    Episode(
      id: '${season}0$number',
      episodeNumber: number,
      title: 'S${season}E$number',
      containerExtension: 'mp4',
      seasonNumber: season,
      streamUrl: url,
    );

SeriesInfo _info(Map<int, List<Episode>> bySeason) => SeriesInfo(
  series: const Series(id: 7, name: 'Show', tmdbId: 42, plot: 'Series plot'),
  seasons: bySeason.keys
      .map((n) => Season(number: n, name: 'Season $n'))
      .toList(),
  episodesBySeason: bySeason,
);

void main() {
  group('nextEpisodeInSeries', () {
    test('returns the next episode in the same season', () {
      final info = _info({
        1: [_ep(1, 1), _ep(1, 2), _ep(1, 3)],
      });
      final next = nextEpisodeInSeries(info, seasonNumber: 1, episodeNumber: 1);
      expect(next?.episodeNumber, 2);
    });

    test('rolls over to the first episode of the next season', () {
      final info = _info({
        1: [_ep(1, 1), _ep(1, 2)],
        2: [_ep(2, 1), _ep(2, 2)],
      });
      final next = nextEpisodeInSeries(info, seasonNumber: 1, episodeNumber: 2);
      expect(next?.seasonNumber, 2);
      expect(next?.episodeNumber, 1);
    });

    test('skips an empty intermediate season', () {
      final info = _info({
        1: [_ep(1, 1)],
        2: <Episode>[],
        3: [_ep(3, 1)],
      });
      final next = nextEpisodeInSeries(info, seasonNumber: 1, episodeNumber: 1);
      expect(next?.seasonNumber, 3);
    });

    test('returns null past the last episode', () {
      final info = _info({
        1: [_ep(1, 1), _ep(1, 2)],
      });
      final next = nextEpisodeInSeries(info, seasonNumber: 1, episodeNumber: 2);
      expect(next, isNull);
    });

    test('returns null when the current season/episode is unknown', () {
      final info = _info({
        1: [_ep(1, 1)],
      });
      expect(
        nextEpisodeInSeries(info, seasonNumber: null, episodeNumber: 1),
        isNull,
      );
    });
  });

  group('episodePlayerArgs', () {
    test('returns null when the episode has no stream URL', () {
      expect(
        episodePlayerArgs(
          episode: _ep(1, 1, url: ''),
          seriesId: 7,
          seriesName: 'Show',
        ),
        isNull,
      );
    });

    test('builds series PlayerArgs with episode + series metadata', () {
      final args = episodePlayerArgs(
        episode: _ep(2, 5),
        seriesId: 7,
        seriesName: 'Show',
        series: const Series(id: 7, name: 'Show', tmdbId: 42, plot: 'p'),
      );
      expect(args, isNotNull);
      expect(args!.type, 'series');
      expect(args.seriesId, 7);
      expect(args.metadata['season_number'], 2);
      expect(args.metadata['episode_number'], 5);
      expect(args.metadata['series_name'], 'Show');
      expect(args.metadata['tmdb_id'], 42);
    });
  });
}

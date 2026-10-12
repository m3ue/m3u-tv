import 'package:fake_async/fake_async.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/home/home_spotlight.dart';
import 'package:m3u_tv/l10n/app_localizations.dart';
import 'package:m3u_tv/services/domain_models.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));
  final format = HomeSpotlightFormat(
    l10n: l10n,
    timeOfDay: (time) =>
        '${time.hour}:${time.minute.toString().padLeft(2, '0')}',
    duration: (duration) => '${duration.inMinutes} min',
  );
  final now = DateTime.utc(2026, 10, 12, 20, 15);

  HomeSpotlight resolve(
    HomeSpotlightTarget target, {
    HomeSpotlightEnricher? enricher,
    EpgCurrentNext? epg,
  }) => resolveHomeSpotlight(
    target,
    format: format,
    enricher: enricher ?? HomeSpotlightEnricher(),
    epgLookup: (_) => epg,
    now: now,
  );

  const movie = VodItem(
    id: 7,
    name: 'Heat',
    streamUrl: 'http://example/7.mkv',
    containerExtension: 'mkv',
    logoUrl: 'http://img/poster.jpg',
    rating: 8.3,
    year: '1995',
  );

  const channel = Channel(
    id: 101,
    name: 'BBC One',
    streamUrl: 'http://example/live/101.ts',
    logoUrl: 'http://img/bbc.png',
    epgChannelId: 'bbc.one',
  );

  group('resolveHomeSpotlight', () {
    test('movie without fetched info uses list data and tints from poster', () {
      final spotlight = resolve(const VodSpotlightTarget(movie));

      expect(spotlight.title, 'Heat');
      expect(spotlight.backdropUrl, isNull);
      expect(spotlight.toneUrl, 'http://img/poster.jpg');
      expect(spotlight.chips, ['1995', '★ 8.3']);
      expect(spotlight.plot, isNull);
    });

    test(
      'movie picks up backdrop, clearlogo and runtime once fetched',
      () async {
        final enricher = HomeSpotlightEnricher(
          fetchVodInfo: (id) async => const VodInfo(
            id: 7,
            name: 'Heat',
            plot: 'A crew of thieves.',
            genre: 'Crime',
            duration: '2h 50m',
            contentRating: 'R',
            backdropUrl: 'http://img/backdrop.jpg',
            clearLogoUrl: 'http://img/logo.png',
          ),
        );
        const target = VodSpotlightTarget(movie);
        expect(enricher.needsFetch(target), isTrue);
        await enricher.fetch(target);
        expect(enricher.needsFetch(target), isFalse);

        final spotlight = resolve(target, enricher: enricher);

        expect(spotlight.backdropUrl, 'http://img/backdrop.jpg');
        expect(spotlight.toneUrl, 'http://img/backdrop.jpg');
        expect(spotlight.clearLogoUrl, 'http://img/logo.png');
        expect(spotlight.chips, ['1995', 'R', 'Crime', '2h 50m', '★ 8.3']);
        expect(spotlight.plot, 'A crew of thieves.');
        expect(spotlight.playLength, const Duration(hours: 2, minutes: 50));
        expect(spotlight.endsAt, isNull);
      },
    );

    test('series uses the list payload directly', () {
      const series = Series(
        id: 3,
        name: 'Severance',
        coverUrl: 'http://img/cover.jpg',
        backdropUrl: 'http://img/sev.jpg',
        clearLogoUrl: 'http://img/sev-logo.png',
        plot: 'Work-life balance.',
        rating: 8.7,
        contentRating: 'TV-MA',
        year: '2022',
      );

      final spotlight = resolve(const SeriesSpotlightTarget(series));

      expect(spotlight.backdropUrl, 'http://img/sev.jpg');
      expect(spotlight.clearLogoUrl, 'http://img/sev-logo.png');
      expect(spotlight.chips, ['2022', 'TV-MA', '★ 8.7']);
      expect(spotlight.plot, 'Work-life balance.');
    });

    test('live channel shows the airing programme from EPG', () {
      final current = EpgProgram(
        channelId: 'bbc.one',
        title: 'Doctor Who',
        subtitle: 'The Giggle',
        description: 'The Doctor returns.',
        start: DateTime.utc(2026, 10, 12, 20),
        end: DateTime.utc(2026, 10, 12, 21),
        iconUrl: 'http://img/icon.jpg',
        backdropUrl: 'http://img/dw-backdrop.jpg',
        category: 'Drama',
        season: 14,
        episode: 3,
        isNew: true,
      );
      final next = EpgProgram(
        channelId: 'bbc.one',
        title: 'News',
        description: '',
        start: DateTime.utc(2026, 10, 12, 21),
        end: DateTime.utc(2026, 10, 12, 21, 30),
      );

      final spotlight = resolve(
        const ChannelSpotlightTarget(channel),
        epg: EpgCurrentNext(current: current, next: next, progress: 0.25),
      );

      expect(spotlight.title, 'Doctor Who');
      expect(spotlight.badge, 'LIVE');
      expect(spotlight.kicker, 'BBC One');
      expect(spotlight.kickerLogoUrl, 'http://img/bbc.png');
      expect(spotlight.secondaryTitle, 'S14 E3 - The Giggle');
      expect(spotlight.backdropUrl, 'http://img/dw-backdrop.jpg');
      expect(spotlight.chips, ['NEW', 'Drama']);
      expect(spotlight.progress, 0.25);
      expect(spotlight.progressLabel, contains('45 min left'));
      expect(spotlight.plot, 'The Doctor returns.');
      expect(spotlight.footnote, contains('News'));
      expect(spotlight.endsAt, DateTime.utc(2026, 10, 12, 21));
    });

    test('live programme without a backdrop falls back to its icon', () {
      final current = EpgProgram(
        channelId: 'bbc.one',
        title: 'Doctor Who',
        description: '',
        start: DateTime.utc(2026, 10, 12, 20),
        end: DateTime.utc(2026, 10, 12, 21),
        iconUrl: 'http://img/icon.jpg',
      );

      final spotlight = resolve(
        const ChannelSpotlightTarget(channel),
        epg: EpgCurrentNext(current: current, progress: 0.25),
      );

      expect(spotlight.backdropUrl, 'http://img/icon.jpg');
      expect(spotlight.footnote, isNull);
    });

    test('live channel with no EPG shows the channel and no-data line', () {
      final spotlight = resolve(const ChannelSpotlightTarget(channel));

      expect(spotlight.title, 'BBC One');
      expect(spotlight.badge, 'LIVE');
      expect(spotlight.backdropUrl, isNull);
      expect(spotlight.toneUrl, 'http://img/bbc.png');
      expect(spotlight.plot, l10n.epgNoData);
    });

    test('placeholder programme is treated as no EPG', () {
      final filler = EpgProgram(
        channelId: 'bbc.one',
        title: 'BBC One',
        description: 'No information available',
        start: DateTime.utc(2026, 10, 12, 20),
        end: DateTime.utc(2026, 10, 12, 21),
        isPlaceholder: true,
      );

      final spotlight = resolve(
        const ChannelSpotlightTarget(channel),
        epg: EpgCurrentNext(current: filler, progress: 0.25),
      );

      expect(spotlight.plot, l10n.epgNoData);
      expect(spotlight.progress, isNull);
      expect(spotlight.endsAt, isNull);
    });

    test(
      'episode progress shows numbering, time left and series art',
      () async {
        const progress = Progress(
          viewerId: 'v',
          contentType: ContentType.episode,
          streamId: 55,
          positionSeconds: 600,
          durationSeconds: 3000,
          seriesId: 3,
          seasonNumber: 1,
          episodeNumber: 4,
          episodeTitle: 'The You You Are',
          seriesName: 'Severance',
          runtime: '50m',
        );
        final enricher = HomeSpotlightEnricher(
          lookupSeries: (id) async => const Series(
            id: 3,
            name: 'Severance',
            backdropUrl: 'http://img/sev.jpg',
            clearLogoUrl: 'http://img/sev-logo.png',
            contentRating: 'TV-MA',
            year: '2022',
          ),
        );
        const target = ProgressSpotlightTarget(progress);
        await enricher.fetch(target);

        final spotlight = resolve(target, enricher: enricher);

        expect(spotlight.title, 'Severance');
        expect(spotlight.secondaryTitle, 'S1 E4 - The You You Are');
        expect(spotlight.clearLogoUrl, 'http://img/sev-logo.png');
        expect(spotlight.backdropUrl, 'http://img/sev.jpg');
        expect(spotlight.chips, ['2022', 'TV-MA', '50m']);
        expect(spotlight.progress, closeTo(0.2, 1e-9));
        expect(spotlight.progressLabel, '40 min left');
        expect(spotlight.badge, isNull);
        expect(spotlight.playLength, const Duration(minutes: 40));
      },
    );

    test('up next entries get the badge and no progress', () {
      const progress = Progress(
        viewerId: 'v',
        contentType: ContentType.episode,
        streamId: 56,
        positionSeconds: 0,
        durationSeconds: 3000,
        seriesId: 3,
        seasonNumber: 1,
        episodeNumber: 5,
        seriesName: 'Severance',
        upNext: true,
      );

      final spotlight = resolve(const ProgressSpotlightTarget(progress));

      expect(spotlight.badge, l10n.homeUpNext);
      expect(spotlight.progress, isNull);
      expect(spotlight.progressLabel, isNull);
      expect(spotlight.playLength, const Duration(minutes: 50));
    });
  });

  group('parseRuntimeText', () {
    test('reads the runtime formats the payloads carry', () {
      expect(
        parseRuntimeText('01:40:09'),
        const Duration(hours: 1, minutes: 40, seconds: 9),
      );
      expect(parseRuntimeText('1:45'), const Duration(hours: 1, minutes: 45));
      expect(parseRuntimeText('2h 50m'), const Duration(hours: 2, minutes: 50));
      expect(parseRuntimeText('2h'), const Duration(hours: 2));
      expect(parseRuntimeText('50m'), const Duration(minutes: 50));
      expect(parseRuntimeText('95 min'), const Duration(minutes: 95));
      expect(parseRuntimeText('120'), const Duration(minutes: 120));
    });

    test('returns null for empty or unreadable text', () {
      expect(parseRuntimeText(null), isNull);
      expect(parseRuntimeText(''), isNull);
      expect(parseRuntimeText('0'), isNull);
      expect(parseRuntimeText('00:00:00'), isNull);
      expect(parseRuntimeText('unknown'), isNull);
    });
  });

  group('HomeSpotlightController', () {
    test('applies the first selection at once and debounces the rest', () {
      fakeAsync((async) {
        final controller = HomeSpotlightController()
          ..select(const VodSpotlightTarget(movie));
        expect(controller.value?.key, 'vod:7');

        controller
          ..select(const ChannelSpotlightTarget(channel))
          ..select(
            const StaticSpotlightTarget(id: 'dvr', title: 'DVR Recordings'),
          );
        async.elapse(const Duration(milliseconds: 100));
        expect(controller.value?.key, 'vod:7');

        async.elapse(const Duration(milliseconds: 100));
        expect(controller.value?.key, 'static:dvr');
        controller.dispose();
      });
    });
  });

  group('HomeSpotlightEnricher', () {
    test('dedupes in-flight fetches and caches failures', () async {
      var calls = 0;
      final enricher = HomeSpotlightEnricher(
        fetchVodInfo: (id) async {
          calls++;
          throw StateError('offline');
        },
      );
      const target = VodSpotlightTarget(movie);

      await Future.wait([enricher.fetch(target), enricher.fetch(target)]);
      await enricher.fetch(target);

      expect(calls, 1);
      expect(enricher.needsFetch(target), isFalse);
      expect(enricher.vodInfo(7), isNull);
    });
  });
}

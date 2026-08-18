import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/domain_models.dart';

void main() {
  group('UserCredentials.normalized scheme handling', () {
    UserCredentials creds(String server) => const UserCredentials(
      server: '',
      username: 'u',
      password: 'p',
    ).normalized();

    test('bare host:port gets http:// prefixed', () {
      final result = const UserCredentials(
        server: '192.168.1.10:8080',
        username: 'u',
        password: 'p',
      ).normalized();
      expect(result.server, 'http://192.168.1.10:8080');
    });

    test('an explicit https:// scheme is left untouched', () {
      final result = const UserCredentials(
        server: 'https://example.com:8443',
        username: 'u',
        password: 'p',
      ).normalized();
      expect(result.server, 'https://example.com:8443');
    });

    test('an explicit http:// scheme is left untouched', () {
      final result = const UserCredentials(
        server: 'http://example.com',
        username: 'u',
        password: 'p',
      ).normalized();
      expect(result.server, 'http://example.com');
    });

    test('trailing slashes are stripped before prefixing', () {
      final result = const UserCredentials(
        server: '192.168.1.10:8080/',
        username: 'u',
        password: 'p',
      ).normalized();
      expect(result.server, 'http://192.168.1.10:8080');
    });

    test('a bare hostname with no port is also prefixed', () {
      final result = const UserCredentials(
        server: 'example.com',
        username: 'u',
        password: 'p',
      ).normalized();
      expect(result.server, 'http://example.com');
    });

    test('empty server stays empty', () {
      expect(creds('').server, '');
    });
  });

  // The `_asNullableString` helper is private, so these tests exercise it
  // indirectly through `DvrRecording.fromXtream`, which is its primary user.
  // The behavior we care about: URL-like fields must end up null rather than
  // a stringified "[]" / "{}" / "true" when the backend returns a non-string
  // JSON value.
  group('DvrRecording.fromXtream non-string hardening', () {
    Map<String, Object?> jsonWith(Object? edlUrl) => <String, Object?>{
      'uuid': 'rec-1',
      'title': 'Hardening fixture',
      'status': 'completed',
      'stream_url': 'https://example.com/stream.mp4',
      'edl_url': edlUrl,
      'channel_icon': edlUrl,
    };

    test('empty list maps to null (was previously the literal "[]")', () {
      final recording = DvrRecording.fromXtream(jsonWith(<Object?>[]));
      expect(recording.edlUrl, isNull);
      expect(recording.channelIconUrl, isNull);
    });

    test('non-empty list maps to null (was previously "[a, b]")', () {
      final recording = DvrRecording.fromXtream(
        jsonWith(<Object?>['https://example.com/edl']),
      );
      expect(recording.edlUrl, isNull);
      expect(recording.channelIconUrl, isNull);
    });

    test('Map maps to null (was previously the literal "{...}")', () {
      final recording = DvrRecording.fromXtream(
        jsonWith(<String, Object?>{'host': 'evil'}),
      );
      expect(recording.edlUrl, isNull);
      expect(recording.channelIconUrl, isNull);
    });

    test('bool maps to null', () {
      final recording = DvrRecording.fromXtream(jsonWith(true));
      expect(recording.edlUrl, isNull);
      expect(recording.channelIconUrl, isNull);
    });

    test('null maps to null', () {
      final recording = DvrRecording.fromXtream(jsonWith(null));
      expect(recording.edlUrl, isNull);
      expect(recording.channelIconUrl, isNull);
    });

    test('String round-trips unchanged', () {
      const url = 'https://m3u.bearald.com/dvr/abc/edl';
      final recording = DvrRecording.fromXtream(jsonWith(url));
      expect(recording.edlUrl, url);
      expect(recording.channelIconUrl, url);
    });

    test('empty String maps to null', () {
      final recording = DvrRecording.fromXtream(jsonWith(''));
      expect(recording.edlUrl, isNull);
    });

    test('int stringifies (numeric IDs still come through as raw numbers)', () {
      final recording = DvrRecording.fromXtream(jsonWith(42));
      expect(recording.edlUrl, '42');
      expect(recording.channelIconUrl, '42');
    });

    test('double stringifies', () {
      final recording = DvrRecording.fromXtream(jsonWith(3.14));
      expect(recording.edlUrl, '3.14');
      expect(recording.channelIconUrl, '3.14');
    });
  });

  group('VodInfo.edlUrl from get_vod_info', () {
    test('reads edl_url nested under info (DVR-backed movie)', () {
      final info = VodInfo.fromXtream(<String, Object?>{
        'info': {
          'edl_url': 'https://xtream.example/dvr/movie/edl',
        },
        'movie_data': {
          'stream_id': 201,
          'name': 'Recorded Movie',
          'container_extension': 'mp4',
        },
      });
      expect(info.edlUrl, 'https://xtream.example/dvr/movie/edl');
    });

    test('null when no edl_url is present anywhere', () {
      final info = VodInfo.fromXtream(<String, Object?>{
        'info': {'plot': 'A regular movie'},
        'movie_data': {
          'stream_id': 202,
          'name': 'Regular Movie',
          'container_extension': 'mp4',
        },
      });
      expect(info.edlUrl, isNull);
    });
  });

  group('Episode.edlUrl from get_series_info', () {
    test('reads top-level edl_url (DVR-backed episode)', () {
      final episode = Episode.fromXtream(<String, Object?>{
        'id': '123',
        'episode_num': 2,
        'title': 'Target Episode',
        'container_extension': 'mp4',
        'season': 1,
        'edl_url': 'https://xtream.example/dvr/series/ep-edl',
      });
      expect(episode.edlUrl, 'https://xtream.example/dvr/series/ep-edl');
    });

    test('null when edl_url is absent', () {
      final episode = Episode.fromXtream(<String, Object?>{
        'id': '124',
        'episode_num': 1,
        'title': 'Non-DVR Episode',
        'container_extension': 'mp4',
        'season': 1,
      });
      expect(episode.edlUrl, isNull);
    });
  });

  group('DvrStorageInfo.fromXtream', () {
    test('parses a quota-scoped response', () {
      final info = DvrStorageInfo.fromXtream(<String, Object?>{
        'used_bytes': 5368709120,
        'quota_bytes': 10737418240,
        'percent_used': 50.0,
        'recording_count': 12,
        'scope': 'guest',
      });

      expect(info.usedBytes, 5368709120);
      expect(info.quotaBytes, 10737418240);
      expect(info.percentUsed, 50.0);
      expect(info.recordingCount, 12);
      expect(info.scope, 'guest');
    });

    test('quota_bytes and percent_used are null for unlimited storage', () {
      final info = DvrStorageInfo.fromXtream(<String, Object?>{
        'used_bytes': 1073741824,
        'quota_bytes': null,
        'percent_used': null,
        'recording_count': 3,
        'scope': 'account',
      });

      expect(info.quotaBytes, isNull);
      expect(info.percentUsed, isNull);
    });

    test('missing numeric fields default to zero rather than throwing', () {
      final info = DvrStorageInfo.fromXtream(const <String, Object?>{});

      expect(info.usedBytes, 0);
      expect(info.recordingCount, 0);
      expect(info.quotaBytes, isNull);
      expect(info.percentUsed, isNull);
    });

    test('missing scope defaults to "account"', () {
      final info = DvrStorageInfo.fromXtream(<String, Object?>{
        'used_bytes': 0,
        'recording_count': 0,
      });

      expect(info.scope, 'account');
    });

    test('percent_used tolerates an integer JSON value', () {
      final info = DvrStorageInfo.fromXtream(<String, Object?>{
        'used_bytes': 0,
        'quota_bytes': 100,
        'percent_used': 90,
        'recording_count': 0,
      });

      expect(info.percentUsed, 90.0);
    });
  });

  // `search_epg_shows.recent_episodes[].subtitle` is plain text (not base64).
  // The client treats `null` and blank/whitespace-only as "absent" so the
  // display site can safely fall back to `title` via `subtitle ?? title`.
  group('EpgShowEpisode.fromXtream subtitle handling', () {
    Map<String, Object?> baseJson({Object? subtitle, bool includeKey = true}) {
      final json = <String, Object?>{
        'channel_id': 1,
        'title': 'Show Title',
        'start_time': '2026-01-01T00:00:00Z',
        'end_time': '2026-01-01T01:00:00Z',
      };
      if (includeKey) json['subtitle'] = subtitle;
      return json;
    }

    test('subtitle present is parsed verbatim', () {
      final ep = EpgShowEpisode.fromXtream(baseJson(subtitle: 'Episode Name'));
      expect(ep.subtitle, 'Episode Name');
    });

    test('subtitle null maps to null', () {
      final ep = EpgShowEpisode.fromXtream(baseJson());
      expect(ep.subtitle, isNull);
    });

    test('subtitle absent key maps to null', () {
      final ep = EpgShowEpisode.fromXtream(baseJson(includeKey: false));
      expect(ep.subtitle, isNull);
    });

    test(
      'subtitle empty string maps to null (server "absent" placeholder)',
      () {
        final ep = EpgShowEpisode.fromXtream(baseJson(subtitle: ''));
        expect(ep.subtitle, isNull);
      },
    );

    test('subtitle whitespace-only string maps to null', () {
      final ep = EpgShowEpisode.fromXtream(baseJson(subtitle: '   '));
      expect(ep.subtitle, isNull);
    });

    test(
      'subtitle with an unexpected non-string JSON type is coerced instead '
      'of throwing',
      () {
        final ep = EpgShowEpisode.fromXtream(baseJson(subtitle: 42));
        expect(ep.subtitle, '42');
      },
    );
  });
}

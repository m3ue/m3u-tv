import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:m3u_tv/services/release_notes_service.dart';

void main() {
  late Directory cacheDir;

  setUp(() async {
    cacheDir = await Directory.systemTemp.createTemp('release_notes_test');
  });

  tearDown(() async {
    if (cacheDir.existsSync()) {
      await cacheDir.delete(recursive: true);
    }
  });

  String releasesJson() => jsonEncode([
    {
      'tag_name': 'v1.4.0',
      'name': 'v1.4.0 - Big update',
      'body': "## What's Changed\n- A thing",
      'html_url': 'https://github.com/m3ue/m3u-tv/releases/tag/v1.4.0',
      'published_at': '2026-09-01T12:00:00Z',
      'prerelease': false,
      'draft': false,
    },
    {
      'tag_name': 'v1.3.0',
      'name': '',
      'body': '',
      'html_url': 'https://github.com/m3ue/m3u-tv/releases/tag/v1.3.0',
      'published_at': '2026-08-01T12:00:00Z',
      'prerelease': false,
      'draft': false,
    },
    {'tag_name': 'v1.5.0-draft', 'draft': true},
  ]);

  test('parses releases newest-first and skips drafts', () async {
    final service = ReleaseNotesService(
      httpClient: MockClient((_) async => http.Response(releasesJson(), 200)),
      cacheDirectory: cacheDir,
    );

    final releases = await service.fetch();

    expect(releases, hasLength(2));
    expect(releases.first.tag, 'v1.4.0');
    expect(releases.first.normalizedVersion, '1.4.0');
    expect(releases.first.name, 'v1.4.0 - Big update');
    expect(releases.first.publishedAt, DateTime.utc(2026, 9, 1, 12));
    expect(releases[1].name, 'v1.3.0'); // falls back to the tag when empty
  });

  test('returns an empty list on a non-200 with no cache', () async {
    final service = ReleaseNotesService(
      httpClient: MockClient((_) async => http.Response('nope', 503)),
      cacheDirectory: cacheDir,
    );

    expect(await service.fetch(), isEmpty);
  });

  test('serves the disk cache when a later fetch fails offline', () async {
    final primed = ReleaseNotesService(
      httpClient: MockClient((_) async => http.Response(releasesJson(), 200)),
      cacheDirectory: cacheDir,
      cacheTtl: Duration.zero,
    );
    expect(await primed.fetch(), hasLength(2));

    // Fresh instance so the in-memory cache can't short-circuit; same dir,
    // network now unavailable.
    final offline = ReleaseNotesService(
      httpClient: MockClient(
        (_) async => throw const SocketException('offline'),
      ),
      cacheDirectory: cacheDir,
      cacheTtl: Duration.zero,
    );
    final cached = await offline.fetch();

    expect(cached, hasLength(2));
    expect(cached.first.tag, 'v1.4.0');
  });

  test('a fresh disk cache short-circuits the network', () async {
    var calls = 0;
    http.Client countingClient() => MockClient((_) async {
      calls++;
      return http.Response(releasesJson(), 200);
    });

    await ReleaseNotesService(
      httpClient: countingClient(),
      cacheDirectory: cacheDir,
    ).fetch();
    expect(calls, 1);

    await ReleaseNotesService(
      httpClient: countingClient(),
      cacheDirectory: cacheDir,
    ).fetch();
    expect(calls, 1); // still fresh on disk, no second request
  });

  test('forceRefresh bypasses a fresh cache', () async {
    var calls = 0;
    http.Client countingClient() => MockClient((_) async {
      calls++;
      return http.Response(releasesJson(), 200);
    });

    await ReleaseNotesService(
      httpClient: countingClient(),
      cacheDirectory: cacheDir,
    ).fetch();
    await ReleaseNotesService(
      httpClient: countingClient(),
      cacheDirectory: cacheDir,
    ).fetch(forceRefresh: true);

    expect(calls, 2);
  });
}

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:m3u_tv/services/api_client.dart';
import 'package:m3u_tv/services/online_subtitle_service.dart';
import 'package:m3u_tv/services/online_subtitle_settings.dart';

void main() {
  const addon = 'https://addon.example';
  late Directory temp;

  setUp(() {
    temp = Directory.systemTemp.createTempSync('online_subtitles_test');
  });

  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  OnlineSubtitleService service(
    Future<http.Response> Function(http.Request request) handler,
  ) => OnlineSubtitleService(
    apiClient: ApiClient(client: MockClient(handler)),
    cacheDirectory: () async => temp,
  );

  http.Response subtitles(List<Object?> entries) =>
      http.Response(jsonEncode({'subtitles': entries}), 200);

  const subtitle = OnlineSubtitle(
    id: '123',
    url: 'https://subs.example/file/123',
    language: 'eng',
    release: 'Some.Release',
  );

  group('search', () {
    test('asks for a movie by IMDb id', () async {
      Uri? requested;
      await service((request) async {
        requested = request.url;
        return subtitles([]);
      }).search(addonUrl: addon, imdbId: 'tt1375666');

      expect('$requested', '$addon/subtitles/movie/tt1375666.json');
    });

    test('asks for an episode by series id, season and number', () async {
      Uri? requested;
      await service((request) async {
        requested = request.url;
        return subtitles([]);
      }).search(addonUrl: addon, imdbId: 'tt0903747', season: 1, episode: 2);

      expect('$requested', '$addon/subtitles/series/tt0903747:1:2.json');
    });

    test('parses the real add-on response shape', () async {
      final results = await service(
        (_) async => subtitles([
          {
            'id': '3728010',
            'url': 'https://subs5.strem.io/en/download/file/1952382875',
            'SubEncoding': 'UTF-8',
            'lang': 'eng',
            'subtitleFileName': 'Inception.2010.CAM.Xvid-LKRG.srt',
            'movieReleaseName': 'Inception.2010.CAM.Xvid-LKRG',
          },
        ]),
      ).search(addonUrl: addon, imdbId: 'tt1375666');

      expect(results.single.id, '3728010');
      expect(results.single.language, 'eng');
      expect(results.single.release, 'Inception.2010.CAM.Xvid-LKRG');
      expect(results.single.fileExtension, 'srt');
    });

    test('a plain add-on with only id, url and lang still works', () async {
      final results = await service(
        (_) async => subtitles([
          {'id': 'x', 'url': 'https://subs.example/a', 'lang': 'fre'},
        ]),
      ).search(addonUrl: addon, imdbId: 'tt1');

      expect(results.single.release, 'x');
      expect(results.single.fileExtension, 'srt');
    });

    test('drops duplicates, bad entries, and non-web links', () async {
      final results = await service(
        (_) async => subtitles([
          {'id': '1', 'url': 'https://subs.example/a', 'lang': 'eng'},
          {'id': '2', 'url': 'https://subs.example/a', 'lang': 'eng'},
          {'id': '3', 'url': 'file:///etc/passwd', 'lang': 'eng'},
          {'id': '4', 'lang': 'eng'},
          {'id': '5', 'url': 'https://subs.example/b'},
          'not a map',
        ]),
      ).search(addonUrl: addon, imdbId: 'tt1');

      expect(results.map((result) => result.id), ['1']);
    });

    test('no subtitles key is an empty result', () async {
      final results = await service(
        (_) async => http.Response('{}', 200),
      ).search(addonUrl: addon, imdbId: 'tt1');

      expect(results, isEmpty);
    });

    test('a server error throws', () async {
      expect(
        service(
          (_) async => http.Response('', 500),
        ).search(addonUrl: addon, imdbId: 'tt1'),
        throwsA(isA<OnlineSubtitleException>()),
      );
    });

    test('a network failure throws', () async {
      expect(
        service(
          (_) async => throw const SocketException('offline'),
        ).search(addonUrl: addon, imdbId: 'tt1'),
        throwsA(isA<OnlineSubtitleException>()),
      );
    });

    test('rejects an id that is not from IMDb without a request', () async {
      var requests = 0;
      await expectLater(
        service((_) async {
          requests++;
          return subtitles([]);
        }).search(addonUrl: addon, imdbId: '../../evil'),
        throwsA(isA<OnlineSubtitleException>()),
      );
      expect(requests, 0);
    });
  });

  group('download', () {
    test('saves the file and returns its local path', () async {
      final path = await service(
        (_) async => http.Response('1\n00:00:01,000 --> 00:00:02,000\nHi', 200),
      ).download(subtitle);

      expect(path, startsWith(temp.path));
      expect(path, endsWith('123.srt'));
      expect(File(path).readAsStringSync(), contains('Hi'));
    });

    test('an id cannot escape the cache folder', () async {
      final path = await service((_) async => http.Response('x', 200)).download(
        const OnlineSubtitle(
          id: '../../evil',
          url: 'https://subs.example/a',
          language: 'eng',
          release: 'r',
        ),
      );

      expect(File(path).parent.path, temp.path);
    });

    test('an empty or failed download throws', () async {
      expect(
        service((_) async => http.Response('', 200)).download(subtitle),
        throwsA(isA<OnlineSubtitleException>()),
      );
      expect(
        service((_) async => http.Response('nope', 404)).download(subtitle),
        throwsA(isA<OnlineSubtitleException>()),
      );
    });

    test('an oversized file throws', () async {
      expect(
        service(
          (_) async =>
              http.Response.bytes(List.filled(6 * 1024 * 1024, 0), 200),
        ).download(subtitle),
        throwsA(isA<OnlineSubtitleException>()),
      );
    });

    test('clears out old downloads', () async {
      final old = File('${temp.path}/old.srt')
        ..writeAsStringSync('old')
        ..setLastModifiedSync(
          DateTime.now().subtract(const Duration(days: 2)),
        );
      final recent = File('${temp.path}/recent.srt')
        ..writeAsStringSync('recent');

      await service((_) async => http.Response('x', 200)).download(subtitle);

      expect(old.existsSync(), isFalse);
      expect(recent.existsSync(), isTrue);
    });
  });

  group('language names', () {
    test('shows a known code in its own language', () {
      expect(onlineSubtitleLanguageName('eng'), 'English');
      expect(onlineSubtitleLanguageName('GER'), 'Deutsch');
      expect(onlineSubtitleLanguageName('pob'), 'Português (Brasil)');
    });

    test('falls back to the code', () {
      expect(onlineSubtitleLanguageName('xyz'), 'XYZ');
    });

    test('maps a device language', () {
      expect(onlineSubtitleCodeForLocale('de'), 'ger');
      expect(onlineSubtitleCodeForLocale('xx'), isNull);
    });
  });

  group('settings', () {
    test('defaults to on with the OpenSubtitles add-on', () {
      final settings = OnlineSubtitleSettings();

      expect(settings.enabled, isTrue);
      expect(settings.usesDefaultAddon, isTrue);
      expect(settings.addonUrl, OnlineSubtitleSettings.defaultAddonUrl);
    });

    test('accepts the forms people copy an add-on link in', () {
      for (final (input, expected) in [
        ('https://addon.example', 'https://addon.example'),
        ('https://addon.example/', 'https://addon.example'),
        ('https://addon.example/manifest.json', 'https://addon.example'),
        ('stremio://addon.example/x/manifest.json', 'https://addon.example/x'),
        ('  http://10.0.0.5:7000/  ', 'http://10.0.0.5:7000'),
      ]) {
        expect(OnlineSubtitleSettings.normalizeAddonUrl(input), expected);
      }
    });

    test('rejects anything else', () {
      for (final input in [
        '',
        'addon.example',
        'ftp://addon.example',
        'https://',
      ]) {
        expect(OnlineSubtitleSettings.normalizeAddonUrl(input), isNull);
      }
    });

    test('an invalid address changes nothing', () async {
      final settings = OnlineSubtitleSettings();

      expect(await settings.setAddonUrl('nope'), isFalse);
      expect(settings.usesDefaultAddon, isTrue);
    });

    test('a custom address can be reset', () async {
      final settings = OnlineSubtitleSettings();

      expect(await settings.setAddonUrl('https://addon.example/'), isTrue);
      expect(settings.addonUrl, 'https://addon.example');
      expect(settings.usesDefaultAddon, isFalse);

      await settings.setAddonUrl(null);
      expect(settings.usesDefaultAddon, isTrue);
    });
  });
}

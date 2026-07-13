import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/persistent_store.dart';
import 'package:m3u_tv/services/proxy_playback_settings.dart';
import 'package:m3u_tv/services/xtream_service.dart';

void main() {
  group('ProxyCapability parsing', () {
    test('parses forced flag and profiles', () {
      final capability = ProxyCapability.fromJson(<String, dynamic>{
        'forced': true,
        'profiles': [
          {'id': 3, 'name': '1080p H264', 'description': null, 'format': 'ts'},
          {'id': 5, 'name': '720p', 'description': 'Lower bitrate'},
        ],
      });

      expect(capability.forced, isTrue);
      expect(capability.profiles, hasLength(2));
      expect(capability.profiles.first.id, 3);
      expect(capability.profiles.first.name, '1080p H264');
      expect(capability.profiles.first.format, 'ts');
      expect(capability.profiles.last.description, 'Lower bitrate');
    });

    test('tolerates missing fields', () {
      final capability = ProxyCapability.fromJson(<String, dynamic>{});

      expect(capability.forced, isFalse);
      expect(capability.profiles, isEmpty);
    });

    test('hasProxy requires both the feature flag and payload', () {
      const withBoth = XtreamAuthResponse(
        isAuthenticated: true,
        features: ['proxy'],
        proxy: ProxyCapability(forced: false),
      );
      const featureOnly = XtreamAuthResponse(
        isAuthenticated: true,
        features: ['proxy'],
      );

      expect(withBoth.hasProxy, isTrue);
      expect(featureOnly.hasProxy, isFalse);
    });
  });

  group('ProxyPlaybackSettings.apply', () {
    const server = 'https://editor.example';
    const liveUrl = '$server/live/user/pass/42.m3u8';
    const vodUrl = '$server/movie/user/pass/7.mkv';

    ProxyPlaybackSettings settings() => ProxyPlaybackSettings();

    test('returns the URL unchanged when disabled and not forced', () {
      final result = settings().apply(
        liveUrl,
        type: 'live',
        forced: false,
        serverBase: server,
      );

      expect(result, liveUrl);
    });

    test('appends proxy=true when enabled', () async {
      final s = settings();
      await s.setEnabled(enabled: true);

      final result = s.apply(
        liveUrl,
        type: 'live',
        forced: false,
        serverBase: server,
      );

      expect(result, '$liveUrl?proxy=true');
    });

    test('uses the live profile for live and catchup types', () async {
      final s = settings();
      await s.setEnabled(enabled: true);
      await s.setLiveProfileId(3);

      for (final type in ['live', 'catchup']) {
        expect(
          s.apply(liveUrl, type: type, forced: false, serverBase: server),
          '$liveUrl?proxy=true&profile=3',
        );
      }
    });

    test('uses the vod profile for vod and series types', () async {
      final s = settings();
      await s.setEnabled(enabled: true);
      await s.setLiveProfileId(3);
      await s.setVodProfileId(5);

      for (final type in ['vod', 'series']) {
        expect(
          s.apply(vodUrl, type: type, forced: false, serverBase: server),
          '$vodUrl?proxy=true&profile=5',
        );
      }
    });

    test('maps the direct sentinel to profile=none', () async {
      final s = settings();
      await s.setEnabled(enabled: true);
      await s.setLiveProfileId(ProxyPlaybackSettings.directProfileId);

      expect(
        s.apply(liveUrl, type: 'live', forced: false, serverBase: server),
        '$liveUrl?proxy=true&profile=none',
      );
    });

    test('forced proxy applies the profile without the local toggle', () async {
      final s = settings();
      await s.setVodProfileId(9);

      expect(
        s.apply(vodUrl, type: 'vod', forced: true, serverBase: server),
        '$vodUrl?profile=9',
      );
    });

    test('forced proxy with default profile leaves the URL unchanged', () {
      expect(
        settings().apply(vodUrl, type: 'vod', forced: true, serverBase: server),
        vodUrl,
      );
    });

    test('leaves external URLs untouched', () async {
      final s = settings();
      await s.setEnabled(enabled: true);
      await s.setLiveProfileId(3);

      const external = 'https://aiostreams.example/stream/movie/123.mp4';
      expect(
        s.apply(external, type: 'vod', forced: false, serverBase: server),
        external,
      );
    });

    test('appends with & when the URL already has a query string', () async {
      final s = settings();
      await s.setEnabled(enabled: true);

      const url = '$server/timeshift/user/pass/60/2026-01-01:00-00/42.ts?utc=1';
      expect(
        s.apply(url, type: 'catchup', forced: false, serverBase: server),
        '$url&proxy=true',
      );
    });
  });

  group('ProxyPlaybackSettings persistence', () {
    test('round-trips through the persistent store', () async {
      final dir = await Directory.systemTemp.createTemp('proxy_settings');
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/store.json');

      final store = PersistentJsonStore(file: file);
      final s = ProxyPlaybackSettings(store: store);
      await s.setEnabled(enabled: true);
      await s.setLiveProfileId(3);
      await s.setVodProfileId(ProxyPlaybackSettings.directProfileId);

      final restored = ProxyPlaybackSettings(
        store: PersistentJsonStore(file: file),
      );
      await restored.load();

      expect(restored.enabled, isTrue);
      expect(restored.liveProfileId, 3);
      expect(restored.vodProfileId, ProxyPlaybackSettings.directProfileId);
    });
  });
}

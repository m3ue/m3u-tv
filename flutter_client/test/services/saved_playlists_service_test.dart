import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/saved_playlists_service.dart';
import 'package:m3u_tv/services/secure_storage.dart';

const _sports = UserCredentials(
  server: 'https://editor.example',
  username: 'owner',
  password: 'sports-playlist-uuid',
);
const _movies = UserCredentials(
  server: 'https://editor.example',
  username: 'owner',
  password: 'movies-playlist-uuid',
);
const _other = UserCredentials(
  server: 'https://other.example:8443',
  username: 'guest',
  password: 'guest-password',
);

void main() {
  group('SavedPlaylistsService', () {
    test(
      'the first playlist keeps the unscoped keys, later ones get their own',
      () async {
        final service = SavedPlaylistsService(storage: InMemorySecureStorage());

        final first = await service.remember(_sports);
        final second = await service.remember(_movies);

        expect(first.usesBaseKeys, isTrue);
        expect(first.scope, isNull);
        expect(second.usesBaseKeys, isFalse);
        expect(second.scope, second.id);
        expect(
          playlistScopedKey('m3ue_favorites', first.scope),
          'm3ue_favorites',
        );
        expect(
          playlistScopedKey('m3ue_favorites', second.scope),
          'm3ue_favorites_playlist_${second.id}',
        );
      },
    );

    test('remembering a saved login returns the existing entry', () async {
      final service = SavedPlaylistsService(storage: InMemorySecureStorage());

      final first = await service.remember(_sports);
      final again = await service.remember(_sports);

      expect(again.id, first.id);
      expect(service.playlists, hasLength(1));
    });

    test(
      'a login mid-connect is scoped to the id it is later saved with',
      () async {
        final service = SavedPlaylistsService(storage: InMemorySecureStorage());
        expect(service.scopeFor(_sports), isNull);
        await service.remember(_sports);

        final pending = service.scopeFor(_movies);
        expect(pending, isNotNull);
        expect(service.scopeFor(_movies), pending);

        final saved = await service.remember(_movies);
        expect(saved.scope, pending);
        expect(service.scopeFor(_movies), pending);
      },
    );

    test('the saved list survives a restart', () async {
      final storage = InMemorySecureStorage();
      final service = SavedPlaylistsService(storage: storage);
      await service.remember(_sports);
      final movies = await service.remember(_movies);
      await service.rename(movies.id, 'Movies');

      final restarted = SavedPlaylistsService(storage: storage);
      await restarted.load();

      expect(restarted.playlists, hasLength(2));
      expect(restarted.find(_sports)?.usesBaseKeys, isTrue);
      expect(restarted.find(_movies)?.id, movies.id);
      expect(restarted.find(_movies)?.name, 'Movies');
    });

    test('rename trims, and a blank name restores the default', () async {
      final service = SavedPlaylistsService(storage: InMemorySecureStorage());
      final playlist = await service.remember(_sports);

      await service.rename(playlist.id, '  Sports  ');
      expect(service.byId(playlist.id)?.name, 'Sports');

      await service.rename(playlist.id, '   ');
      expect(service.byId(playlist.id)?.name, isNull);
    });

    test('remove and clear update the stored list', () async {
      final storage = InMemorySecureStorage();
      final service = SavedPlaylistsService(storage: storage);
      final sports = await service.remember(_sports);
      await service.remember(_movies);

      expect((await service.remove(sports.id))?.id, sports.id);
      expect(await service.remove(sports.id), isNull);
      expect(service.find(_sports), isNull);
      final stored = jsonDecode(
        (await storage.read(SavedPlaylistsService.storageKey))!,
      );
      expect(stored, hasLength(1));

      await service.clear();
      expect(service.playlists, isEmpty);
      expect(await storage.read(SavedPlaylistsService.storageKey), isNull);
    });

    test('a corrupt stored list loads as empty instead of throwing', () async {
      final storage = InMemorySecureStorage();
      await storage.write(SavedPlaylistsService.storageKey, '{not json');
      final service = SavedPlaylistsService(storage: storage);

      await service.load();

      expect(service.playlists, isEmpty);
    });

    test(
      'a failed read never overwrites the stored list, and is retried',
      () async {
        final storage = _FlakySecureStorage();
        await SavedPlaylistsService(storage: storage).remember(_sports);
        final stored = await storage.read(SavedPlaylistsService.storageKey);

        storage.failReads = true;
        final service = SavedPlaylistsService(storage: storage);
        await service.remember(_movies);
        expect(
          await storage.inner.read(SavedPlaylistsService.storageKey),
          stored,
        );

        storage.failReads = false;
        await service.remember(_other);
        expect(service.find(_sports), isNotNull);
        expect(service.find(_other), isNotNull);
      },
    );
  });

  group('playlist labels', () {
    test('use the server host, numbered when hosts repeat', () async {
      final service = SavedPlaylistsService(storage: InMemorySecureStorage());
      final sports = await service.remember(_sports);
      final movies = await service.remember(_movies);
      final other = await service.remember(_other);
      final all = service.playlists;

      expect(playlistDefaultName(sports, all), 'editor.example (1)');
      expect(playlistDefaultName(movies, all), 'editor.example (2)');
      expect(playlistDefaultName(other, all), 'other.example');
    });

    test('never show the username or password', () async {
      final service = SavedPlaylistsService(storage: InMemorySecureStorage());
      await service.remember(_sports);
      await service.remember(_other);

      for (final playlist in service.playlists) {
        final label = playlistDisplayName(playlist, service.playlists);
        expect(label, isNot(contains(playlist.credentials.username)));
        expect(label, isNot(contains(playlist.credentials.password)));
      }
    });

    test('prefer a custom name', () async {
      final service = SavedPlaylistsService(storage: InMemorySecureStorage());
      final sports = await service.remember(_sports);
      await service.rename(sports.id, 'Sports');

      expect(
        playlistDisplayName(service.byId(sports.id)!, service.playlists),
        'Sports',
      );
    });
  });
}

class _FlakySecureStorage implements SecureStorage {
  final InMemorySecureStorage inner = InMemorySecureStorage();
  bool failReads = false;

  @override
  Future<String?> read(String key) {
    if (failReads) throw StateError('keyring locked');
    return inner.read(key);
  }

  @override
  Future<void> write(String key, String value) => inner.write(key, value);

  @override
  Future<void> delete(String key) => inner.delete(key);
}

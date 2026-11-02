// ignore_for_file: prefer_initializing_formals

import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:m3u_tv/services/async_lifecycle.dart';
import 'package:m3u_tv/services/domain_models.dart';
import 'package:m3u_tv/services/notification_coordinator.dart'
    show sameCredentials;
import 'package:m3u_tv/services/secure_storage.dart';

/// Resolves the scope of the active playlist (see [playlistScopedKey]).
typedef PlaylistScope = String? Function();

/// The store key per-playlist local state (favorites, proxy profiles, the
/// active viewer) lives under: [base] itself for a null [scope], else [base]
/// suffixed with the playlist's id.
String playlistScopedKey(String base, String? scope) =>
    scope == null ? base : '${base}_playlist_$scope';

/// The label shown for [playlist] among [playlists]: its custom name, else
/// [playlistDefaultName].
String playlistDisplayName(
  SavedPlaylist playlist,
  List<SavedPlaylist> playlists,
) => playlist.name ?? playlistDefaultName(playlist, playlists);

/// The server's host, numbered when several of [playlists] share it. Never
/// the username or password: settings must not put credentials on screen,
/// and the editor's handshake carries no playlist name to use instead.
String playlistDefaultName(
  SavedPlaylist playlist,
  List<SavedPlaylist> playlists,
) {
  final host = playlist.host;
  final sameHost = playlists.where((other) => other.host == host).toList();
  final position = sameHost.indexWhere((other) => other.id == playlist.id);
  if (sameHost.length < 2 || position < 0) return host;
  return '$host (${position + 1})';
}

/// One editor login saved on this device. The editor resolves every Xtream
/// login to exactly one playlist, so a saved login is a saved playlist.
@immutable
class SavedPlaylist {
  const SavedPlaylist({
    required this.id,
    required this.credentials,
    this.name,
    this.usesBaseKeys = false,
  });

  static SavedPlaylist? tryFromJson(Object? json) {
    if (json is! Map) return null;
    final id = json['id'];
    final server = json['server'];
    final username = json['username'];
    final password = json['password'];
    if (id is! String || id.isEmpty) return null;
    if (server is! String || username is! String || password is! String) {
      return null;
    }
    final name = json['name'];
    return SavedPlaylist(
      id: id,
      credentials: UserCredentials(
        server: server,
        username: username,
        password: password,
      ),
      name: name is String && name.trim().isNotEmpty ? name.trim() : null,
      usesBaseKeys: json['base_keys'] == true,
    );
  }

  final String id;
  final UserCredentials credentials;

  /// User-chosen label. Null shows [playlistDefaultName].
  final String? name;

  /// True for the first playlist saved on a device. Its local state stays
  /// under the keys used before multiple playlists existed, so an upgrade
  /// never moves or drops it.
  final bool usesBaseKeys;

  /// The scope passed to [playlistScopedKey] for this playlist's state.
  String? get scope => usesBaseKeys ? null : id;

  String get host {
    final host = Uri.tryParse(credentials.server)?.host ?? '';
    return host.isEmpty ? credentials.server : host;
  }

  SavedPlaylist withName(String? name) => SavedPlaylist(
    id: id,
    credentials: credentials,
    name: name,
    usesBaseKeys: usesBaseKeys,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'server': credentials.server,
    'username': credentials.username,
    'password': credentials.password,
    if (name != null) 'name': name,
    if (usesBaseKeys) 'base_keys': true,
  };
}

/// The playlists (editor logins) saved on this device, persisted in secure
/// storage alongside the active session's credentials. The active playlist is
/// whichever entry matches `AuthNotifier.credentials`; this service holds no
/// separate "active" pointer that could drift from the live session.
class SavedPlaylistsService extends ChangeNotifier {
  SavedPlaylistsService({required SecureStorage storage, Random? random})
    : _storage = storage,
      _random = random ?? Random.secure();

  static const storageKey = 'm3ue_tv_saved_playlists';

  final SecureStorage _storage;
  final Random _random;
  final SerialQueue _writes = SerialQueue();

  /// Ids handed out by [scopeFor] to logins that are mid-connect and not
  /// saved yet, keyed by [_identity]. [remember] adopts them, so state written
  /// while connecting lands under the id the playlist is then saved with.
  final Map<String, String> _pendingIds = <String, String>{};
  Future<void>? _loading;
  bool _loaded = false;
  List<SavedPlaylist> _playlists = const <SavedPlaylist>[];

  List<SavedPlaylist> get playlists => _playlists;

  /// Reads the saved list once. A failed read is retried by the next call,
  /// and nothing is written back until a read succeeds, so a transient
  /// storage error can't overwrite the stored list with a partial one.
  Future<void> load() async {
    if (_loaded) return;
    await (_loading ??= _load());
    if (!_loaded) _loading = null;
  }

  Future<void> _load() async {
    try {
      final raw = await _storage.read(storageKey);
      _loaded = true;
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      _playlists = List<SavedPlaylist>.unmodifiable(
        decoded.map(SavedPlaylist.tryFromJson).whereType<SavedPlaylist>(),
      );
      notifyListeners();
    } on Object catch (error) {
      debugPrint('Saved playlists: load failed: $error');
    }
  }

  SavedPlaylist? find(UserCredentials? credentials) {
    if (credentials == null) return null;
    for (final playlist in _playlists) {
      if (sameCredentials(playlist.credentials, credentials)) return playlist;
    }
    return null;
  }

  SavedPlaylist? byId(String id) {
    for (final playlist in _playlists) {
      if (playlist.id == id) return playlist;
    }
    return null;
  }

  /// The scope per-playlist state is stored under while [credentials] is the
  /// active login: the saved entry's scope, else the scope [remember] will
  /// save it with.
  String? scopeFor(UserCredentials? credentials) {
    if (credentials == null) return null;
    final saved = find(credentials);
    if (saved != null) return saved.scope;
    if (_playlists.isEmpty) return null;
    return _pendingIds.putIfAbsent(_identity(credentials), _newId);
  }

  /// Saves [credentials] (no-op when already saved) and returns its entry.
  Future<SavedPlaylist> remember(UserCredentials credentials) async {
    await load();
    final existing = find(credentials);
    if (existing != null) return existing;
    final pendingId = _pendingIds.remove(_identity(credentials));
    final playlist = SavedPlaylist(
      id: pendingId ?? _newId(),
      credentials: credentials,
      usesBaseKeys: pendingId == null && _playlists.isEmpty,
    );
    _playlists = List<SavedPlaylist>.unmodifiable(<SavedPlaylist>[
      ..._playlists,
      playlist,
    ]);
    notifyListeners();
    await _persist();
    return playlist;
  }

  /// Sets the label for [id]; null or blank restores the default name.
  Future<void> rename(String id, String? name) async {
    await load();
    final trimmed = name?.trim();
    final label = trimmed == null || trimmed.isEmpty ? null : trimmed;
    final current = byId(id);
    if (current == null || current.name == label) return;
    _playlists = List<SavedPlaylist>.unmodifiable(<SavedPlaylist>[
      for (final playlist in _playlists)
        if (playlist.id == id) playlist.withName(label) else playlist,
    ]);
    notifyListeners();
    await _persist();
  }

  /// Removes [id] and returns the removed entry, or null if it wasn't saved.
  Future<SavedPlaylist?> remove(String id) async {
    await load();
    final removed = byId(id);
    if (removed == null) return null;
    _playlists = List<SavedPlaylist>.unmodifiable(
      _playlists.where((playlist) => playlist.id != id),
    );
    notifyListeners();
    await _persist();
    return removed;
  }

  Future<void> clear() async {
    await load();
    _pendingIds.clear();
    if (_playlists.isEmpty) return;
    _playlists = const <SavedPlaylist>[];
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() => _writes.run(() async {
    if (!_loaded) return;
    final playlists = _playlists;
    if (playlists.isEmpty) {
      await _storage.delete(storageKey);
      return;
    }
    await _storage.write(
      storageKey,
      jsonEncode(<Map<String, Object?>>[
        for (final playlist in playlists) playlist.toJson(),
      ]),
    );
  });

  static String _identity(UserCredentials credentials) => jsonEncode(<String>[
    credentials.server,
    credentials.username,
    credentials.password,
  ]);

  String _newId() => <String>[
    for (var i = 0; i < 12; i++)
      _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();
}

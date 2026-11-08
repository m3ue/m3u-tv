// ignore_for_file: prefer_initializing_formals

import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:m3u_tv/services/async_lifecycle.dart';
import 'package:m3u_tv/services/device_pairing_service.dart'
    show PairedPlaylist;
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

/// Whether two server URLs reach the same editor: same host, port and path,
/// whatever the scheme was typed as or a trailing slash.
bool sameServer(String first, String second) {
  final a = Uri.tryParse(normalizeServerUrl(first));
  final b = Uri.tryParse(normalizeServerUrl(second));
  if (a == null || b == null) return first == second;
  return a.host == b.host && a.port == b.port && a.path == b.path;
}

/// The label shown for [playlist] among [playlists]: its custom name, else
/// [playlistDefaultName].
String playlistDisplayName(
  SavedPlaylist playlist,
  List<SavedPlaylist> playlists,
) => playlist.name ?? playlistDefaultName(playlist, playlists);

/// The login's username: a Playlist Auth or alias has its own, which tells
/// playlists on one editor apart better than the host they share. The host
/// is added when the same username is saved for another editor, and the
/// owner's login (the same username on every playlist it opens) is numbered.
/// Never the password.
String playlistDefaultName(
  SavedPlaylist playlist,
  List<SavedPlaylist> playlists,
) {
  final username = playlist.credentials.username;
  final sameUsername = playlists
      .where((other) => other.credentials.username == username)
      .toList();
  final label = sameUsername.any((other) => other.host != playlist.host)
      ? '$username@${playlist.host}'
      : username;
  final sameLabel = sameUsername
      .where((other) => other.host == playlist.host)
      .toList();
  final position = sameLabel.indexWhere((other) => other.id == playlist.id);
  if (sameLabel.length < 2 || position < 0) return label;
  return '$label (${position + 1})';
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
    this.lastUsed,
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
    final lastUsedMs = json['last_used'];
    return SavedPlaylist(
      id: id,
      credentials: UserCredentials(
        server: server,
        username: username,
        password: password,
      ),
      name: name is String && name.trim().isNotEmpty ? name.trim() : null,
      usesBaseKeys: json['base_keys'] == true,
      lastUsed: lastUsedMs is int
          ? DateTime.fromMillisecondsSinceEpoch(lastUsedMs)
          : null,
    );
  }

  final String id;
  final UserCredentials credentials;

  /// User-chosen label. Null shows [playlistDefaultName].
  final String? name;

  /// True for a login saved from before multiple playlists existed, until
  /// its local state is moved from the unscoped keys to its own (at boot).
  final bool usesBaseKeys;

  /// When it was last connected to. Decides which playlists' catalogs stay
  /// on the device.
  final DateTime? lastUsed;

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
    lastUsed: lastUsed,
  );

  SavedPlaylist _with({bool? usesBaseKeys, DateTime? lastUsed}) =>
      SavedPlaylist(
        id: id,
        credentials: credentials,
        name: name,
        usesBaseKeys: usesBaseKeys ?? this.usesBaseKeys,
        lastUsed: lastUsed ?? this.lastUsed,
      );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'server': credentials.server,
    'username': credentials.username,
    'password': credentials.password,
    if (name != null) 'name': name,
    if (usesBaseKeys) 'base_keys': true,
    if (lastUsed != null) 'last_used': lastUsed!.millisecondsSinceEpoch,
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

  /// [playlists], most recently used first.
  List<SavedPlaylist> get recentFirst {
    final order = {
      for (var i = 0; i < _playlists.length; i++) _playlists[i]: i,
    };
    int usedMs(SavedPlaylist playlist) =>
        playlist.lastUsed?.millisecondsSinceEpoch ?? 0;
    return [..._playlists]..sort((a, b) {
      final byUse = usedMs(b).compareTo(usedMs(a));
      return byUse != 0 ? byUse : order[a]!.compareTo(order[b]!);
    });
  }

  /// The scopes of logins still connecting (see [scopeFor]).
  Set<String> get pendingScopes => _pendingIds.values.toSet();

  /// Reads the saved list once. A failed read is retried by the next call,
  /// and nothing is written back until a read succeeds, so a transient
  /// storage error can't overwrite the stored list with a partial one. A
  /// stored value that can't be parsed never will be: it loads as empty and
  /// the next save replaces it.
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
  /// save it with. Null until the list is loaded, so nothing is written
  /// under an id the saved list might not agree with.
  String? scopeFor(UserCredentials? credentials) {
    if (credentials == null || !_loaded) return null;
    final saved = find(credentials);
    if (saved != null) return saved.scope;
    return _pendingIds.putIfAbsent(_identity(credentials), _newId);
  }

  /// Drops the id [scopeFor] handed to [credentials] while it connected and
  /// returns it; null when it had none or has been saved since.
  String? takePendingScope(UserCredentials credentials) {
    if (find(credentials) != null) return null;
    return _pendingIds.remove(_identity(credentials));
  }

  /// Saves [credentials] (or marks it used, when already saved) and returns
  /// its entry. A login that never connected through [scopeFor] (one saved
  /// from before multiple playlists existed) keeps its state on the unscoped
  /// keys until [markScoped].
  Future<SavedPlaylist> remember(UserCredentials credentials) async {
    await load();
    final now = DateTime.now();
    final existing = find(credentials);
    if (existing != null) {
      final used = existing._with(lastUsed: now);
      _replace(used);
      await _persist();
      return used;
    }
    final pendingId = _pendingIds.remove(_identity(credentials));
    final playlist = SavedPlaylist(
      id: pendingId ?? _newId(),
      credentials: credentials,
      usesBaseKeys: pendingId == null && _playlists.isEmpty,
      lastUsed: now,
    );
    _playlists = List<SavedPlaylist>.unmodifiable(<SavedPlaylist>[
      ..._playlists,
      playlist,
    ]);
    notifyListeners();
    await _persist();
    return playlist;
  }

  /// Saves the playlists an admin granted in one pairing, in their order, at
  /// the top of the list; other saved playlists keep their order below. One
  /// already saved keeps its id and state, and its name unless it has none,
  /// in which case it takes the editor's. Nothing is marked used: connecting
  /// to the primary does that through [remember].
  Future<void> adoptPaired(List<PairedPlaylist> paired) async {
    await load();
    final adopted = <SavedPlaylist>[];
    for (final entry in paired) {
      if (adopted.any(
        (playlist) => sameCredentials(playlist.credentials, entry.credentials),
      )) {
        continue;
      }
      final existing = find(entry.credentials);
      if (existing != null) {
        adopted.add(
          existing.name == null && entry.name != null
              ? existing.withName(entry.name)
              : existing,
        );
        continue;
      }
      final pendingId = _pendingIds.remove(_identity(entry.credentials));
      adopted.add(
        SavedPlaylist(
          id: pendingId ?? _newId(),
          credentials: entry.credentials,
          name: entry.name,
          // Same rule as [remember]: the first playlist on a device keeps
          // the unscoped keys.
          usesBaseKeys:
              pendingId == null && _playlists.isEmpty && adopted.isEmpty,
        ),
      );
    }
    if (adopted.isEmpty) return;
    final adoptedIds = {for (final playlist in adopted) playlist.id};
    _playlists = List<SavedPlaylist>.unmodifiable(<SavedPlaylist>[
      ...adopted,
      for (final playlist in _playlists)
        if (!adoptedIds.contains(playlist.id)) playlist,
    ]);
    notifyListeners();
    await _persist();
  }

  /// Records that [id]'s state has moved off the unscoped keys.
  Future<void> markScoped(String id) async {
    final current = byId(id);
    if (current == null || !current.usesBaseKeys) return;
    _replace(current._with(usesBaseKeys: false));
    notifyListeners();
    await _persist();
  }

  void _replace(SavedPlaylist updated) {
    _playlists = List<SavedPlaylist>.unmodifiable(<SavedPlaylist>[
      for (final playlist in _playlists)
        if (playlist.id == updated.id) updated else playlist,
    ]);
  }

  /// Sets the label for [id]; null or blank restores the default name.
  Future<void> rename(String id, String? name) async {
    await load();
    final trimmed = name?.trim();
    final label = trimmed == null || trimmed.isEmpty ? null : trimmed;
    final current = byId(id);
    if (current == null || current.name == label) return;
    _replace(current.withName(label));
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

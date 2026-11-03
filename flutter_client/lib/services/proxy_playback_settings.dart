// ignore_for_file: prefer_initializing_formals

import 'package:flutter/foundation.dart';
import 'package:m3u_tv/services/persistent_store.dart';
import 'package:m3u_tv/services/saved_playlists_service.dart';

/// One playlist's stored proxy playback preferences (see
/// [ProxyPlaybackSettings.readFor]).
typedef ProxyPlaybackValues = ({
  bool enabled,
  int? liveProfileId,
  int? vodProfileId,
});

/// Per-device proxy playback preferences.
///
/// Mirrors the m3u-editor "In-App Player Transcoding" preferences: the user can
/// enable proxied playback and pick separate transcoding profiles for Live and
/// VOD/Series content. Profile selection values:
///  - `null` — server default (playlist-level profile, if any)
///  - [directProfileId] — explicit direct proxy (no transcoding)
///  - any other id — a profile advertised by the backend
class ProxyPlaybackSettings extends ChangeNotifier {
  ProxyPlaybackSettings({PersistentJsonStore? store}) : _store = store;

  static const _storeKey = 'm3ue_tv_proxy_playback';
  static const int directProfileId = 0;

  final PersistentJsonStore? _store;

  bool _enabled = false;
  int? _liveProfileId;
  int? _vodProfileId;

  /// Keeps each saved playlist's preferences apart: profile ids are defined
  /// per editor, so one playlist's choice means nothing on another. Unset, or
  /// resolving to null, uses the unscoped key.
  PlaylistScope? playlistScope;
  bool _loaded = false;
  String? _loadedScope;

  bool get enabled => _enabled;
  int? get liveProfileId => _liveProfileId;
  int? get vodProfileId => _vodProfileId;

  /// Whether the current values were loaded for the playlist with [scope].
  bool isLoadedFor(String? scope) => _loaded && _loadedScope == scope;

  /// Loads the active playlist's preferences, falling back to defaults when it
  /// has none stored. Without a store the in-memory values are kept.
  Future<void> load() async {
    final scope = playlistScope?.call();
    if (_store == null) {
      _loaded = true;
      _loadedScope = scope;
      return;
    }
    final values = await readFor(scope);
    // A newer load for the playlist that has since become active owns the
    // values now.
    if (playlistScope?.call() != scope) return;
    useFor(scope, values!);
  }

  /// The preferences stored for the playlist with [scope], read ahead of
  /// showing it so they go in place with it ([useFor]). Null without a store.
  Future<ProxyPlaybackValues?> readFor(String? scope) async {
    final store = _store;
    if (store == null) return null;
    final raw = await store.read(playlistScopedKey(_storeKey, scope));
    final values = raw is Map ? raw : const <Object?, Object?>{};
    return (
      enabled: values['enabled'] == true,
      liveProfileId: _asProfileId(values['live_profile_id']),
      vodProfileId: _asProfileId(values['vod_profile_id']),
    );
  }

  /// Makes [values] (from [readFor]) the current preferences, as the
  /// playlist with [scope]'s.
  void useFor(String? scope, ProxyPlaybackValues values) {
    _loaded = true;
    _loadedScope = scope;
    _enabled = values.enabled;
    _liveProfileId = values.liveProfileId;
    _vodProfileId = values.vodProfileId;
    notifyListeners();
  }

  /// Moves the preferences kept on the unscoped key (a login from before
  /// multiple playlists) to [scope]'s, unless it already has its own.
  Future<void> adoptUnscoped(String scope) async {
    final store = _store;
    if (store == null) return;
    final value = await store.read(_storeKey);
    final key = playlistScopedKey(_storeKey, scope);
    if (value != null && await store.read(key) == null) {
      await store.write(key, value);
    }
    await store.delete(_storeKey);
    // Values loaded from the unscoped key are this playlist's: read them
    // again from where they live now.
    if (_loadedScope == null) _loaded = false;
  }

  /// Drops the preferences stored for a removed playlist's [scope].
  Future<void> clearPlaylistState(String? scope) async {
    await _store?.delete(playlistScopedKey(_storeKey, scope));
    if (scope != _loadedScope) return;
    _enabled = false;
    _liveProfileId = null;
    _vodProfileId = null;
    notifyListeners();
  }

  Future<void> setEnabled({required bool enabled}) async {
    _enabled = enabled;
    await _persist();
    notifyListeners();
  }

  Future<void> setLiveProfileId(int? id) async {
    _liveProfileId = id;
    await _persist();
    notifyListeners();
  }

  Future<void> setVodProfileId(int? id) async {
    _vodProfileId = id;
    await _persist();
    notifyListeners();
  }

  /// Applies the proxy playback preferences to a backend stream URL.
  ///
  /// [type] is the player content type ('live' | 'vod' | 'series' | 'catchup').
  /// [forced] means the playlist already routes everything through the proxy,
  /// so `proxy=true` is unnecessary but profile selection still applies.
  /// URLs not pointing at [serverBase] (e.g. external AIOStreams sources) are
  /// returned unchanged.
  String apply(
    String streamUrl, {
    required String type,
    required bool forced,
    required String serverBase,
  }) {
    if (!_appliesTo(streamUrl, forced: forced, serverBase: serverBase)) {
      return streamUrl;
    }

    final profileId = _profileIdFor(type);
    final params = <String>[
      if (!forced) 'proxy=true',
      if (profileId != null)
        'profile=${profileId == directProfileId ? 'none' : profileId}',
    ];
    if (params.isEmpty) return streamUrl;
    final separator = streamUrl.contains('?') ? '&' : '?';
    return '$streamUrl$separator${params.join('&')}';
  }

  /// Whether [apply] routes [streamUrl] through an explicit transcoding
  /// profile, as opposed to direct proxy, no proxy, or the server default
  /// (which the client can't see into).
  bool isTranscoding(
    String streamUrl, {
    required String type,
    required bool forced,
    required String serverBase,
  }) {
    if (!_appliesTo(streamUrl, forced: forced, serverBase: serverBase)) {
      return false;
    }
    final profileId = _profileIdFor(type);
    return profileId != null && profileId != directProfileId;
  }

  bool _appliesTo(
    String streamUrl, {
    required bool forced,
    required String serverBase,
  }) => streamUrl.startsWith(serverBase) && (_enabled || forced);

  int? _profileIdFor(String type) =>
      type == 'live' || type == 'catchup' ? _liveProfileId : _vodProfileId;

  Future<void> _persist() async {
    await _store?.write(
      playlistScopedKey(_storeKey, _loadedScope),
      <String, Object?>{
        'enabled': _enabled,
        'live_profile_id': _liveProfileId,
        'vod_profile_id': _vodProfileId,
      },
    );
  }

  int? _asProfileId(Object? value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }
}

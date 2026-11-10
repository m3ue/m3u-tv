// ignore_for_file: prefer_initializing_formals

import 'package:flutter/foundation.dart';
import 'package:m3u_tv/services/home_screen_config.dart';
import 'package:m3u_tv/services/persistent_store.dart';
import 'package:m3u_tv/services/saved_playlists_service.dart';

/// The editor's `m3u_editor.client_config` handshake block: settings an
/// admin manages for this login from an M3U TV Profile.
@immutable
class ClientConfigCapability {
  const ClientConfigCapability({
    required this.revision,
    this.apiVersion = 1,
    this.action = 'get_client_config',
  });

  /// Null when the block is malformed or from an API version this app
  /// doesn't speak.
  static ClientConfigCapability? tryFromJson(Map<String, dynamic> json) {
    final apiVersion = json['api_version'];
    final revision = json['revision'];
    final action = json['action'];
    if (apiVersion is! int || apiVersion > supportedApiVersion) return null;
    if (revision is! String || revision.isEmpty) return null;
    return ClientConfigCapability(
      apiVersion: apiVersion,
      revision: revision,
      action: action is String && action.isNotEmpty
          ? action
          : 'get_client_config',
    );
  }

  static const supportedApiVersion = 1;

  final int apiVersion;

  /// Changes whenever the resolved settings change.
  final String revision;
  final String action;
}

/// One setting the server manages: [enforced] ones always apply and are
/// locked; the others only replace the app's built-in default.
@immutable
class ManagedSetting {
  const ManagedSetting({required this.value, required this.enforced});

  final Object value;
  final bool enforced;

  @override
  bool operator ==(Object other) =>
      other is ManagedSetting &&
      other.value == value &&
      other.enforced == enforced;

  @override
  int get hashCode => Object.hash(value, enforced);
}

/// The settings an M3U TV Profile manages, keyed by the editor's setting
/// key (see `TvClientSettings` in m3u-editor).
@immutable
class ClientConfig {
  const ClientConfig({
    required this.revision,
    this.profileName,
    this.settings = const {},
    this.homeScreen,
  });

  factory ClientConfig.fromJson(Map<String, dynamic> json) {
    final rawSettings = json['settings'];
    final profile = json['profile'];
    return ClientConfig(
      revision: '${json['revision'] ?? ''}',
      profileName: profile is String && profile.isNotEmpty ? profile : null,
      settings: Map.unmodifiable(<String, ManagedSetting>{
        if (rawSettings is Map)
          for (final MapEntry(:key, :value) in rawSettings.entries)
            if (key is String && value is Map && value['value'] != null)
              if (value['mode'] case 'default' || 'enforced')
                key: ManagedSetting(
                  value: value['value'] as Object,
                  enforced: value['mode'] == 'enforced',
                ),
      }),
      homeScreen: HomeScreenConfig.tryFromJson(json['home_screen']),
    );
  }

  final String revision;
  final String? profileName;
  final Map<String, ManagedSetting> settings;

  /// This login's Home screen, when the editor has one for it.
  final HomeScreenConfig? homeScreen;

  Map<String, Object?> toJson() => {
    'revision': revision,
    'profile': profileName,
    'settings': {
      for (final MapEntry(:key, :value) in settings.entries)
        key: {
          'mode': value.enforced ? 'enforced' : 'default',
          'value': value.value,
        },
    },
    if (homeScreen != null) 'home_screen': homeScreen!.toJson(),
  };
}

/// Each saved playlist's last fetched [ClientConfig], so a launch or a
/// playlist switch applies it before the server answers, and an unchanged
/// revision skips the fetch.
class ClientConfigStore {
  ClientConfigStore({PersistentJsonStore? store}) : _store = store;

  static const _storeKey = 'm3ue_tv_client_config';

  final PersistentJsonStore? _store;
  final Map<String?, ClientConfig> _memory = {};

  Future<ClientConfig?> readFor(String? scope) async {
    final store = _store;
    if (store == null) return _memory[scope];
    final raw = await store.read(playlistScopedKey(_storeKey, scope));
    return raw is Map
        ? ClientConfig.fromJson(Map<String, dynamic>.from(raw))
        : null;
  }

  Future<void> writeFor(String? scope, ClientConfig config) async {
    _memory[scope] = config;
    await _store?.write(playlistScopedKey(_storeKey, scope), config.toJson());
  }

  /// Drops the config stored for a removed playlist's [scope].
  Future<void> clearPlaylistState(String? scope) async {
    _memory.remove(scope);
    await _store?.delete(playlistScopedKey(_storeKey, scope));
  }
}

// ignore_for_file: prefer_initializing_formals

import 'package:flutter/foundation.dart';
import 'package:m3u_tv/services/persistent_store.dart';

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

  bool get enabled => _enabled;
  int? get liveProfileId => _liveProfileId;
  int? get vodProfileId => _vodProfileId;

  Future<void> load() async {
    final raw = await _store?.read(_storeKey);
    if (raw is! Map) return;
    _enabled = raw['enabled'] == true;
    _liveProfileId = _asProfileId(raw['live_profile_id']);
    _vodProfileId = _asProfileId(raw['vod_profile_id']);
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
    if (!streamUrl.startsWith(serverBase)) return streamUrl;
    if (!_enabled && !forced) return streamUrl;

    final profileId = type == 'live' || type == 'catchup'
        ? _liveProfileId
        : _vodProfileId;
    final params = <String>[
      if (!forced) 'proxy=true',
      if (profileId != null)
        'profile=${profileId == directProfileId ? 'none' : profileId}',
    ];
    if (params.isEmpty) return streamUrl;
    final separator = streamUrl.contains('?') ? '&' : '?';
    return '$streamUrl$separator${params.join('&')}';
  }

  Future<void> _persist() async {
    await _store?.write(_storeKey, <String, Object?>{
      'enabled': _enabled,
      'live_profile_id': _liveProfileId,
      'vod_profile_id': _vodProfileId,
    });
  }

  int? _asProfileId(Object? value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }
}

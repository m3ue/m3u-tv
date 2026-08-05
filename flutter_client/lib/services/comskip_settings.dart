// ignore_for_file: prefer_initializing_formals

import 'package:flutter/foundation.dart';
import 'package:m3u_tv/services/persistent_store.dart';

/// Per-device commercial-skip (comskip/EDL) playback preference.
///
/// Controls how the player reacts when a DVR recording's EDL segments show
/// the play-head inside a detected commercial break: auto-skip straight to
/// the segment's end, or show a confirm-to-skip prompt instead.
class ComskipSettings extends ChangeNotifier {
  ComskipSettings({PersistentJsonStore? store}) : _store = store;

  static const _storeKey = 'm3ue_tv_comskip';

  final PersistentJsonStore? _store;

  bool _autoSkipEnabled = true;

  bool get autoSkipEnabled => _autoSkipEnabled;

  Future<void> load() async {
    final raw = await _store?.read(_storeKey);
    if (raw is! Map) return;
    _autoSkipEnabled = raw['auto_skip_enabled'] != false;
    notifyListeners();
  }

  Future<void> setAutoSkipEnabled({required bool enabled}) async {
    _autoSkipEnabled = enabled;
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    await _store?.write(_storeKey, <String, Object?>{
      'auto_skip_enabled': _autoSkipEnabled,
    });
  }
}

// ignore_for_file: prefer_initializing_formals

import 'package:flutter/foundation.dart';
import 'package:m3u_tv/services/persistent_store.dart';

/// Per-device TheIntroDB (skip intro/credits) preference.
///
/// When disabled, the player never queries TheIntroDB, so VOD and series
/// playback shows no Skip Intro/Skip Credits prompts and Up Next falls back
/// to its no-credits-data timing. Enabled by default; there's no API key to
/// configure.
class IntroDbSettings extends ChangeNotifier {
  IntroDbSettings({PersistentJsonStore? store}) : _store = store;

  static const _storeKey = 'm3ue_tv_introdb';

  final PersistentJsonStore? _store;

  bool _enabled = true;

  bool get enabled => _enabled;

  Future<void> load() async {
    final raw = await _store?.read(_storeKey);
    if (raw is! Map) return;
    _enabled = raw['enabled'] != false;
    notifyListeners();
  }

  Future<void> setEnabled({required bool enabled}) async {
    _enabled = enabled;
    await _persist();
    notifyListeners();
  }

  Future<void> _persist() async {
    await _store?.write(_storeKey, <String, Object?>{'enabled': _enabled});
  }
}

// ignore_for_file: prefer_initializing_formals

import 'package:flutter/foundation.dart';
import 'package:m3u_tv/services/persistent_store.dart';

/// Per-device preferences for the player's online subtitle search.
///
/// Nothing is sent anywhere until someone uses the search, so it's on by
/// default.
class OnlineSubtitleSettings extends ChangeNotifier {
  OnlineSubtitleSettings({PersistentJsonStore? store}) : _store = store;

  static const defaultAddonUrl = 'https://opensubtitles-v3.strem.io';
  static const _storeKey = 'm3ue_tv_online_subtitles';

  final PersistentJsonStore? _store;

  bool _enabled = true;
  String? _customAddonUrl;
  String? _lastLanguage;

  bool get enabled => _enabled;
  String get addonUrl => _customAddonUrl ?? defaultAddonUrl;
  bool get usesDefaultAddon => _customAddonUrl == null;

  /// The language last picked in the search, listed first next time.
  String? get lastLanguage => _lastLanguage;

  Future<void> load() async {
    final raw = await _store?.read(_storeKey);
    if (raw is! Map) return;
    _enabled = raw['enabled'] != false;
    final addonUrl = raw['addonUrl'];
    _customAddonUrl = addonUrl is String ? normalizeAddonUrl(addonUrl) : null;
    final lastLanguage = raw['lastLanguage'];
    _lastLanguage = lastLanguage is String ? lastLanguage : null;
    notifyListeners();
  }

  Future<void> setEnabled({required bool enabled}) async {
    _enabled = enabled;
    await _persist();
    notifyListeners();
  }

  /// Sets the add-on address, or restores the default for null. Returns false
  /// without changing anything when [value] isn't a usable address.
  Future<bool> setAddonUrl(String? value) async {
    if (value == null) {
      _customAddonUrl = null;
    } else {
      final normalized = normalizeAddonUrl(value);
      if (normalized == null) return false;
      _customAddonUrl = normalized == defaultAddonUrl ? null : normalized;
    }
    await _persist();
    notifyListeners();
    return true;
  }

  Future<void> setLastLanguage(String language) async {
    if (_lastLanguage == language) return;
    _lastLanguage = language;
    await _persist();
  }

  /// The add-on's base address from what people copy, which is usually its
  /// `.../manifest.json` link, often with a `stremio://` scheme. Null when it
  /// isn't an http(s) address.
  @visibleForTesting
  static String? normalizeAddonUrl(String value) {
    var url = value.trim();
    if (url.startsWith('stremio://')) {
      url = 'https://${url.substring('stremio://'.length)}';
    }
    url = url.replaceFirst(RegExp(r'/manifest\.json$'), '');
    url = url.replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !(uri.isScheme('https') || uri.isScheme('http')) ||
        uri.host.isEmpty) {
      return null;
    }
    return url;
  }

  Future<void> _persist() async {
    await _store?.write(_storeKey, <String, Object?>{
      'enabled': _enabled,
      'addonUrl': _customAddonUrl,
      'lastLanguage': _lastLanguage,
    });
  }
}

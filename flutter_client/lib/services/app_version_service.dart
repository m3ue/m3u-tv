import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;

/// Result of comparing the installed app version against the latest
/// version published in `pubspec.yaml` on the repo's master branch.
class AppVersionCheck {
  const AppVersionCheck({
    required this.currentVersion,
    this.latestVersion,
    this.updateAvailable = false,
  });

  final String currentVersion;
  final String? latestVersion;
  final bool updateAvailable;
}

/// Fetches the app's own version and checks it against the version
/// declared in `pubspec.yaml` on the `m3u-tv` GitHub repo's master branch —
/// mirrors the update-check m3u-editor already performs for itself.
///
/// Reads the local version from the bundled `pubspec.yaml` asset rather
/// than a native plugin (e.g. package_info_plus): this app's tvOS target
/// only registers plugins that explicitly declare tvos platform support
/// (see flutter_secure_storage_tvos / path_provider_tvos), so a plain
/// plugin would silently no-op there. Asset loading works identically on
/// every platform.
class AppVersionService {
  AppVersionService({HttpClient? httpClient})
    : _httpClient = httpClient ?? HttpClient();

  static const _pubspecUrl =
      'https://raw.githubusercontent.com/m3ue/m3u-tv/master/flutter_client/pubspec.yaml';
  static final _versionPattern = RegExp(
    r'^version:\s*([0-9.]+)',
    multiLine: true,
  );

  final HttpClient _httpClient;

  Future<String?> currentVersion() async {
    final pubspec = await rootBundle.loadString('pubspec.yaml');
    return _versionPattern.firstMatch(pubspec)?.group(1);
  }

  Future<AppVersionCheck> check() async {
    final current = await currentVersion();
    if (current == null) {
      return const AppVersionCheck(currentVersion: '');
    }
    final latest = await _fetchLatestVersion();
    if (latest == null) {
      return AppVersionCheck(currentVersion: current);
    }
    return AppVersionCheck(
      currentVersion: current,
      latestVersion: latest,
      updateAvailable: _isNewer(latest, current),
    );
  }

  Future<String?> _fetchLatestVersion() async {
    try {
      final request = await _httpClient.getUrl(Uri.parse(_pubspecUrl));
      final response = await request.close().timeout(
        const Duration(seconds: 8),
      );
      if (response.statusCode != HttpStatus.ok) return null;
      final body = await utf8.decodeStream(response);
      final match = _versionPattern.firstMatch(body);
      return match?.group(1);
    } on Exception catch (_) {
      return null;
    }
  }

  /// Compares dot-separated numeric version strings. Returns true if
  /// [remote] is greater than [local].
  bool _isNewer(String remote, String local) {
    final remoteParts = remote.split('.').map(_toInt).toList();
    final localParts = local.split('.').map(_toInt).toList();
    final length = remoteParts.length > localParts.length
        ? remoteParts.length
        : localParts.length;
    for (var i = 0; i < length; i++) {
      final r = i < remoteParts.length ? remoteParts[i] : 0;
      final l = i < localParts.length ? localParts[i] : 0;
      if (r != l) return r > l;
    }
    return false;
  }

  int _toInt(String value) => int.tryParse(value) ?? 0;
}

import 'package:flutter/services.dart' show rootBundle;
import 'package:m3u_tv/services/api_client.dart';
import 'package:m3u_tv/services/apk_update_service.dart';
import 'package:m3u_tv/services/secure_storage.dart';

/// Result of comparing the installed app version against the latest
/// version published in `pubspec.yaml` on the repo's master branch.
class AppVersionCheck {
  const AppVersionCheck({
    required this.currentVersion,
    this.latestVersion,
    this.updateAvailable = false,
    this.installableRelease,
  });

  final String currentVersion;
  final String? latestVersion;
  final bool updateAvailable;

  /// Set when the newer release can be installed in-app (sideloaded APK).
  final ApkRelease? installableRelease;
}

/// A newer release surfaced in Notifications (see
/// [AppVersionService.updateNotice]).
class AppUpdateNotice {
  const AppUpdateNotice({
    required this.version,
    required this.isRead,
    this.isNew = false,
    this.release,
  });

  final String version;
  final bool isRead;

  /// First time this version was seen on this install.
  final bool isNew;

  /// Set when the update can be installed in-app (sideloaded APK).
  final ApkRelease? release;

  AppUpdateNotice markedRead() =>
      AppUpdateNotice(version: version, isRead: true, release: release);
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
  AppVersionService({ApiClient? apiClient, ApkUpdateService? apkUpdates})
    : _injectedApi = apiClient,
      _injectedApkUpdates = apkUpdates;

  static const _pubspecUrl =
      'https://raw.githubusercontent.com/m3ue/m3u-tv/master/flutter_client/pubspec.yaml';
  static final _versionPattern = RegExp(
    r'^version:\s*([0-9.]+)',
    multiLine: true,
  );

  final ApiClient? _injectedApi;
  // Lazy: most instances only ever read the bundled version.
  late final ApiClient _api = _injectedApi ?? ApiClient();
  final ApkUpdateService? _injectedApkUpdates;
  late final ApkUpdateService _apkUpdates =
      _injectedApkUpdates ?? ApkUpdateService(apiClient: _injectedApi);

  Future<String?> currentVersion() async {
    final pubspec = await rootBundle.loadString('pubspec.yaml');
    return _versionPattern.firstMatch(pubspec)?.group(1);
  }

  Future<AppVersionCheck> check() async {
    final current = await currentVersion();
    if (current == null) {
      return const AppVersionCheck(currentVersion: '');
    }
    // A sideloaded APK compares against the published release rather than
    // master's pubspec (bumped before the release exists), so the APK it
    // offers to install is always there.
    if (await _apkUpdates.canSelfUpdate()) {
      final release = await _apkUpdates.latestRelease();
      if (release != null) {
        final newer = _isNewer(release.version, current);
        return AppVersionCheck(
          currentVersion: current,
          latestVersion: release.version,
          updateAvailable: newer,
          installableRelease: newer ? release : null,
        );
      }
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

  static const _announcedVersionKey = 'm3ue_tv_announced_update_version';
  static const _readVersionKey = 'm3ue_tv_read_update_version';

  /// The in-app notice for a release newer than the installed one, or null
  /// when up to date (or the check failed). Records the version as announced,
  /// so [AppUpdateNotice.isNew] (the toast) is true once per release while
  /// [AppUpdateNotice.isRead] (the bell badge) stays false until
  /// [markNoticeRead].
  Future<AppUpdateNotice?> updateNotice(SecureStorage storage) async {
    // Startup is the one point no update download is in flight; this drops
    // the APK left behind by the last in-app update.
    await _apkUpdates.clearDownloads();
    final check = await this.check();
    final latest = check.latestVersion;
    if (!check.updateAvailable || latest == null) return null;
    final isNew = await storage.read(_announcedVersionKey) != latest;
    if (isNew) await storage.write(_announcedVersionKey, latest);
    return AppUpdateNotice(
      version: latest,
      isRead: await storage.read(_readVersionKey) == latest,
      isNew: isNew,
      release: check.installableRelease,
    );
  }

  Future<void> markNoticeRead(SecureStorage storage, String version) =>
      storage.write(_readVersionKey, version);

  Future<String?> _fetchLatestVersion() async {
    try {
      final response = await _api.send(
        'GET',
        Uri.parse(_pubspecUrl),
        timeout: const Duration(seconds: 8),
      );
      if (response.statusCode != 200) return null;
      final match = _versionPattern.firstMatch(response.text);
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

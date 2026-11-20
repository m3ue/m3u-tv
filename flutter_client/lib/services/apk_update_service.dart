import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:m3u_tv/services/api_client.dart';
import 'package:m3u_tv/shared/host_platform.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// A GitHub release whose Android APK can be installed in place.
class ApkRelease {
  const ApkRelease({
    required this.version,
    required this.apkName,
    required this.apkUrl,
    required this.checksumUrl,
    this.sizeBytes,
  });

  final String version;
  final String apkName;
  final Uri apkUrl;

  /// The release's `<apk>.sha256` file (`sha256sum` output).
  final Uri checksumUrl;
  final int? sizeBytes;
}

enum ApkInstallEventKind { pendingUserAction, success, failure }

/// A status report from the native install session.
class ApkInstallEvent {
  const ApkInstallEvent(this.kind, {this.code, this.message});

  final ApkInstallEventKind kind;

  /// `PackageInstaller.STATUS_*`.
  final int? code;
  final String? message;

  bool get isCancelled => code == statusFailureAborted;
  bool get isSignatureConflict => code == statusFailureConflict;
  bool get isStorageFailure => code == statusFailureStorage;

  static const statusFailureAborted = 3;
  static const statusFailureConflict = 5;
  static const statusFailureStorage = 6;
}

class ApkChecksumMismatch implements Exception {
  const ApkChecksumMismatch();
}

class ApkDownloadCancelled implements Exception {
  const ApkDownloadCancelled();
}

/// In-app updates for sideloaded Android installs: finds the latest GitHub
/// release, downloads and checksums its APK, and hands it to the native
/// installer (`ApkUpdateInstaller.kt`).
///
/// Only the GitHub release APK is built with
/// `--dart-define=M3UTV_SIDELOAD_UPDATER=true`; that same flag is what adds
/// REQUEST_INSTALL_PACKAGES to its manifest. Play policy forbids
/// self-updating, so the Play bundle has neither, and even a sideload build
/// stays quiet when a store installed it.
class ApkUpdateService {
  ApkUpdateService({
    ApiClient? apiClient,
    this._httpClient,
    Future<Directory> Function()? cacheDirectory,
    bool? enabled,
  }) : _injectedApi = apiClient,
       _cacheDirectory = cacheDirectory ?? getTemporaryDirectory,
       _enabled = enabled ?? (sideloadBuild && HostPlatform.isAndroid);

  static const sideloadBuild = bool.fromEnvironment('M3UTV_SIDELOAD_UPDATER');

  /// Overridable for testing against a local feed (see
  /// `scripts/serve-test-update.sh`) instead of a published release.
  static const releaseFeedUrl = String.fromEnvironment(
    'M3UTV_UPDATE_FEED_URL',
    defaultValue: 'https://api.github.com/repos/m3ue/m3u-tv/releases/latest',
  );

  static const _channel = MethodChannel('m3u_tv/apk_update');
  static const _storeInstallers = {'com.android.vending', 'com.amazon.venezia'};
  static const _downloadDirName = 'apk_update';
  static final _assetPattern = RegExp(r'^m3u-tv-v(.+)-android\.apk$');

  static final StreamController<ApkInstallEvent> _events =
      StreamController<ApkInstallEvent>.broadcast();
  static bool _handlerSet = false;

  final ApiClient? _injectedApi;
  late final ApiClient _api = _injectedApi ?? ApiClient();
  final http.Client? _httpClient;
  final Future<Directory> Function() _cacheDirectory;
  final bool _enabled;

  /// Status reports for the install started by [install].
  Stream<ApkInstallEvent> get installEvents {
    _ensureHandler();
    return _events.stream;
  }

  /// True on a sideload build that no app store installed.
  Future<bool> canSelfUpdate() async {
    if (!_enabled) return false;
    try {
      final installer = await _channel.invokeMethod<String>('installerPackage');
      return !_storeInstallers.contains(installer);
    } on Object {
      return false;
    }
  }

  Future<ApkRelease?> latestRelease() async {
    try {
      final json = await _api.getJson(
        Uri.parse(releaseFeedUrl),
        headers: const {'accept': 'application/vnd.github+json'},
        timeout: const Duration(seconds: 10),
      );
      return parseRelease(json);
    } on Object {
      return null;
    }
  }

  /// Reads a GitHub "get release" response. Null when it has no versioned
  /// APK with a matching `.sha256` next to it.
  static ApkRelease? parseRelease(Object? json) {
    if (json is! Map) return null;
    final assets = json['assets'];
    if (assets is! List) return null;
    final byName = <String, Map<Object?, Object?>>{
      for (final asset in assets.whereType<Map<Object?, Object?>>())
        if (asset['name'] case final String name) name: asset,
    };
    for (final MapEntry(key: name, value: asset) in byName.entries) {
      final match = _assetPattern.firstMatch(name);
      if (match == null) continue;
      final apkUrl = _uri(asset['browser_download_url']);
      final checksumUrl = _uri(byName['$name.sha256']?['browser_download_url']);
      if (apkUrl == null || checksumUrl == null) continue;
      final size = asset['size'];
      return ApkRelease(
        version: match.group(1)!,
        apkName: name,
        apkUrl: apkUrl,
        checksumUrl: checksumUrl,
        sizeBytes: size is int ? size : null,
      );
    }
    return null;
  }

  static Uri? _uri(Object? value) =>
      value is String ? Uri.tryParse(value) : null;

  /// Downloads [release]'s APK into the cache dir and verifies it against
  /// the published SHA-256. Throws [ApkChecksumMismatch] (the file is
  /// deleted), [ApkDownloadCancelled] once [isCancelled] turns true, or an
  /// I/O / HTTP error.
  Future<File> download(
    ApkRelease release, {
    void Function(int received, int? total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final checksumResponse = await _api.send(
      'GET',
      release.checksumUrl,
      timeout: const Duration(seconds: 15),
    );
    checksumResponse.throwIfError();
    final expected = checksumResponse.text.trim().split(RegExp(r'\s+')).first;

    await clearDownloads();
    final dir = Directory(
      p.join((await _cacheDirectory()).path, _downloadDirName),
    );
    await dir.create(recursive: true);
    final file = File(p.join(dir.path, release.apkName));

    final client = _httpClient ?? http.Client();
    final sink = file.openWrite();
    final digest = _DigestSink();
    final hasher = sha256.startChunkedConversion(digest);
    var completed = false;
    try {
      final response = await client
          .send(http.Request('GET', release.apkUrl))
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw HttpException(
          'HTTP ${response.statusCode}',
          uri: release.apkUrl,
        );
      }
      final total = response.contentLength ?? release.sizeBytes;
      var received = 0;
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 30),
      )) {
        if (isCancelled?.call() ?? false) throw const ApkDownloadCancelled();
        sink.add(chunk);
        hasher.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      hasher.close();
      await sink.flush();
      if (digest.value.toString() != expected.toLowerCase()) {
        throw const ApkChecksumMismatch();
      }
      completed = true;
      return file;
    } finally {
      await sink.close();
      if (_httpClient == null) client.close();
      if (!completed && file.existsSync()) await file.delete();
    }
  }

  /// Removes downloaded APKs. Called at startup, after an update installed
  /// (Android restarts the app) or was abandoned.
  Future<void> clearDownloads() async {
    if (!_enabled) return;
    try {
      final dir = Directory(
        p.join((await _cacheDirectory()).path, _downloadDirName),
      );
      if (dir.existsSync()) await dir.delete(recursive: true);
    } on Object {
      // Best-effort; the OS clears the cache dir under pressure anyway.
    }
  }

  Future<bool> canRequestInstalls() async {
    try {
      return await _channel.invokeMethod<bool>('canRequestInstalls') ?? false;
    } on Object {
      return false;
    }
  }

  Future<void> openInstallPermissionSettings() =>
      _channel.invokeMethod<void>('openInstallPermissionSettings');

  /// Starts the install; outcomes arrive on [installEvents].
  Future<void> install(File apk) {
    _ensureHandler();
    return _channel.invokeMethod<void>('install', {'path': apk.path});
  }

  static void _ensureHandler() {
    if (_handlerSet) return;
    _handlerSet = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'onInstallStatus') return;
      final args = call.arguments;
      if (args is! Map) return;
      final kind = switch (args['kind']) {
        'pendingUserAction' => ApkInstallEventKind.pendingUserAction,
        'success' => ApkInstallEventKind.success,
        _ => ApkInstallEventKind.failure,
      };
      _events.add(
        ApkInstallEvent(
          kind,
          code: args['code'] as int?,
          message: args['message'] as String?,
        ),
      );
    });
  }
}

class _DigestSink implements Sink<Digest> {
  late Digest value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

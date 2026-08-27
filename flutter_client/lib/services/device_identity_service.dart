// ignore_for_file: prefer_initializing_formals

import 'dart:io';
import 'dart:math';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:m3u_tv/app/device_type_resolver.dart';
import 'package:m3u_tv/services/app_version_service.dart';
import 'package:m3u_tv/services/secure_storage.dart';

/// Stable per-install identity the server keys its device registry on. The
/// `deviceId` is generated once and persisted; everything else is resolved
/// fresh each call so a renamed device or upgraded app reports the new value
/// the next time it talks to the server.
class DeviceIdentity {
  const DeviceIdentity({
    required this.deviceId,
    required this.platform,
    this.deviceName,
    this.appVersion,
  });

  final String deviceId;
  final String platform;
  final String? deviceName;
  final String? appVersion;

  /// Query params appended to the boot/resume notifications call so the
  /// server can upsert this device without a dedicated heartbeat.
  Map<String, String> toQueryParams() => {
    'device_id': deviceId,
    'platform': platform,
    if (deviceName != null && deviceName!.isNotEmpty)
      'device_name': deviceName!,
    if (appVersion != null && appVersion!.isNotEmpty)
      'app_version': appVersion!,
  };
}

class DeviceMeta {
  const DeviceMeta({required this.platform, this.name});

  final String platform;
  final String? name;
}

typedef DeviceMetaResolver = Future<DeviceMeta> Function();

class DeviceIdentityService {
  DeviceIdentityService({
    required SecureStorage storage,
    Future<String?> Function()? appVersionResolver,
    DeviceMetaResolver? metaResolver,
  }) : _storage = storage,
       _appVersionResolver =
           appVersionResolver ?? AppVersionService().currentVersion,
       _metaResolver = metaResolver ?? _defaultMetaResolver;

  static const _deviceIdKey = 'm3u_tv_device_id';

  final SecureStorage _storage;
  final Future<String?> Function() _appVersionResolver;
  final DeviceMetaResolver _metaResolver;

  String? _cachedId;

  /// The persistent install id, generated and stored on first use.
  Future<String> deviceId() async {
    final cached = _cachedId;
    if (cached != null) return cached;

    final existing = await _storage.read(_deviceIdKey);
    if (existing != null && existing.trim().isNotEmpty) {
      return _cachedId = existing.trim();
    }

    final generated = _uuidV4();
    await _storage.write(_deviceIdKey, generated);
    return _cachedId = generated;
  }

  Future<DeviceIdentity> resolve() async {
    final meta = await _safe(
      _metaResolver,
      const DeviceMeta(platform: 'unknown'),
    );
    final version = await _safe(_appVersionResolver, null);

    return DeviceIdentity(
      deviceId: await deviceId(),
      platform: meta.platform,
      deviceName: meta.name,
      appVersion: version,
    );
  }

  static Future<T> _safe<T>(Future<T> Function() run, T fallback) async {
    try {
      return await run();
    } on Object catch (_) {
      return fallback;
    }
  }
}

String _uuidV4() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

Future<DeviceMeta> _defaultMetaResolver() async {
  final televisionHint = await _safeTelevisionHint();
  final platform = _platformTag(televisionHint);

  String? name;
  try {
    final info = DeviceInfoPlugin();
    if (!kIsWeb && Platform.operatingSystem == 'tvos') {
      // device_info_plus has no tvOS channel; leave name null here and let
      // _fallbackName() below supply it (localHostname / "Apple TV").
      name = null;
    } else if (Platform.isIOS) {
      name = (await info.iosInfo).name;
    } else if (Platform.isAndroid) {
      final android = await info.androidInfo;
      name = '${android.manufacturer} ${android.model}'.trim();
    } else if (Platform.isMacOS) {
      name = (await info.macOsInfo).computerName;
    } else if (Platform.isWindows) {
      name = (await info.windowsInfo).computerName;
    } else if (Platform.isLinux) {
      name = (await info.linuxInfo).prettyName;
    }
  } on Object catch (_) {
    name = null;
  }

  name ??= _fallbackName(platform);

  return DeviceMeta(platform: platform, name: name);
}

Future<bool> _safeTelevisionHint() async {
  try {
    return await resolveNativeTelevisionHint();
  } on Object catch (_) {
    return false;
  }
}

String _platformTag(bool televisionHint) {
  if (!kIsWeb && Platform.operatingSystem == 'tvos') return 'tvos';

  return switch (defaultTargetPlatform) {
    TargetPlatform.android => televisionHint ? 'androidtv' : 'android',
    TargetPlatform.iOS => 'ios',
    TargetPlatform.macOS => 'macos',
    TargetPlatform.linux => 'linux',
    TargetPlatform.windows => 'windows',
    TargetPlatform.fuchsia => 'fuchsia',
  };
}

String? _fallbackName(String platform) {
  try {
    final host = Platform.localHostname.trim();
    if (host.isNotEmpty && host.toLowerCase() != 'localhost') return host;
  } on Object catch (_) {
    // localHostname can throw on some sandboxed platforms.
  }

  return switch (platform) {
    'tvos' => 'Apple TV',
    'androidtv' => 'Android TV',
    _ => null,
  };
}

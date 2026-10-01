import 'dart:io';
import 'dart:ui';

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';

import 'package:m3u_tv/services/device_identity_service.dart';
import 'package:m3u_tv/services/device_performance.dart';

const MethodChannel _deviceInfoChannel = MethodChannel('m3u_tv/device_info');

/// Builds the device header for the Logs & Diagnostics screen and its
/// uploads, so a report answers "which device, which build, which renderer,
/// which performance tier, how much memory" on its own (Plezy's logs screen
/// does the same). Never includes credentials: [serverHost] is the host only.
Future<String> buildDiagnosticsHeader({
  required String layout,
  DeviceIdentity? identity,
  String? serverHost,
  Future<String?> Function()? rendererResolver,
}) async {
  final renderer = await (rendererResolver ?? _resolveRenderer)();
  final view = PlatformDispatcher.instance.views.firstOrNull;
  final cache = PaintingBinding.instance.imageCache;

  String mb(int bytes) => '${bytes >> 20}MB';

  final os = '${Platform.operatingSystem} ${Platform.operatingSystemVersion}';
  final platform = identity?.platform ?? Platform.operatingSystem;
  final display = view == null
      ? null
      : '${view.physicalSize.width.round()}x${view.physicalSize.height.round()}'
            ' @ ${view.devicePixelRatio}x';
  final memory =
      'RSS ${mb(ProcessInfo.currentRss)}, image cache ${cache.currentSize} '
      'images / ${mb(cache.currentSizeBytes)} (max ${cache.maximumSize} / '
      '${mb(cache.maximumSizeBytes)}), live ${cache.liveImageCount}';

  final lines = <String>[
    'M3U TV ${identity?.appVersion ?? 'unknown version'}',
    'Platform: $platform ($os)',
    if (identity?.deviceName case final name? when name.isNotEmpty)
      'Device: $name',
    if (identity != null) 'Device ID: ${identity.deviceId}',
    'Layout: $layout',
    'Renderer: ${renderer ?? 'default'}',
    'Performance: ${DevicePerformance.describe()}',
    if (display != null) 'Display: $display',
    'Memory: $memory',
    if (serverHost != null && serverHost.isNotEmpty) 'Server: $serverHost',
    'Generated: ${DateTime.now().toIso8601String()}',
  ];
  return lines.join('\n');
}

/// Android reports what `MainActivity.getFlutterShellArgs` chose (Skia or
/// Impeller, plus any engine memory caps). Elsewhere there is no choice to
/// report, so this returns null and the header says "default".
Future<String?> _resolveRenderer() async {
  if (!Platform.isAndroid) return null;
  try {
    return await _deviceInfoChannel.invokeMethod<String>('getRenderer');
  } on Object catch (_) {
    return null;
  }
}

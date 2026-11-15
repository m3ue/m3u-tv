import 'package:flutter/services.dart';
import 'package:m3u_tv/shared/host_platform.dart';

enum SystemUiRouteMode { browsing, player }

typedef ApplySystemUiRouteMode = Future<void> Function(SystemUiRouteMode mode);

class SystemUiPolicy {
  SystemUiPolicy({
    bool? isAndroid,
    ApplySystemUiRouteMode? applySystemUiRouteMode,
  }) : _isAndroid = isAndroid ?? (HostPlatform.isAndroid),
       _applySystemUiRouteMode =
           applySystemUiRouteMode ?? _applyAndroidSystemUiRouteMode;

  static const _channel = MethodChannel('m3u_tv/system_ui');

  final bool _isAndroid;
  final ApplySystemUiRouteMode _applySystemUiRouteMode;

  static Future<void> _applyAndroidSystemUiRouteMode(
    SystemUiRouteMode mode,
  ) async {
    try {
      await _channel.invokeMethod<void>(mode.name);
    } on MissingPluginException {
      // No activity: Android Auto started the app, and there are no system
      // bars to set until the phone's screen opens.
    }
  }

  Future<void> applyBrowsing() async {
    if (_isAndroid) {
      await _applySystemUiRouteMode(SystemUiRouteMode.browsing);
    }
  }

  Future<void> applyPlayer() async {
    if (_isAndroid) {
      await _applySystemUiRouteMode(SystemUiRouteMode.player);
    }
  }
}

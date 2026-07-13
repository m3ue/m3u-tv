import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum SystemUiRouteMode { browsing, player }

typedef ApplySystemUiRouteMode = Future<void> Function(SystemUiRouteMode mode);

class SystemUiPolicy {
  SystemUiPolicy({
    bool? isAndroid,
    ApplySystemUiRouteMode? applySystemUiRouteMode,
  }) : _isAndroid = isAndroid ?? (!kIsWeb && Platform.isAndroid),
       _applySystemUiRouteMode =
           applySystemUiRouteMode ?? _applyAndroidSystemUiRouteMode;

  static const _channel = MethodChannel('m3u_tv/system_ui');

  final bool _isAndroid;
  final ApplySystemUiRouteMode _applySystemUiRouteMode;

  static Future<void> _applyAndroidSystemUiRouteMode(
    SystemUiRouteMode mode,
  ) => _channel.invokeMethod<void>(mode.name);

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

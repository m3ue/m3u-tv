import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

/// `dart:io`'s [Platform], safe to read in a web build, where every
/// [Platform] getter throws. On the web each `is*` check is false,
/// [operatingSystem] is `'web'` and [environment] is empty.
abstract final class HostPlatform {
  static bool get isWeb => kIsWeb;

  static String get operatingSystem =>
      kIsWeb ? 'web' : Platform.operatingSystem;

  static String get operatingSystemVersion =>
      kIsWeb ? '' : Platform.operatingSystemVersion;

  static Map<String, String> get environment =>
      kIsWeb ? const <String, String>{} : Platform.environment;

  static bool get isAndroid => !kIsWeb && Platform.isAndroid;

  static bool get isIOS => !kIsWeb && Platform.isIOS;

  /// The tvOS-patched engine reports `operatingSystem == 'tvos'`, with
  /// [isIOS] false.
  static bool get isTvOS => !kIsWeb && Platform.operatingSystem == 'tvos';

  static bool get isMacOS => !kIsWeb && Platform.isMacOS;

  static bool get isWindows => !kIsWeb && Platform.isWindows;

  static bool get isLinux => !kIsWeb && Platform.isLinux;

  static bool get isDesktop => isMacOS || isWindows || isLinux;
}

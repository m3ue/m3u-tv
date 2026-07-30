import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'desktop notification dependency is wired into Linux, Windows and macOS',
    () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final lockfile = File('pubspec.lock').readAsStringSync();
      final linuxCmake = File('linux/CMakeLists.txt').readAsStringSync();
      final windowsCmake = File('windows/CMakeLists.txt').readAsStringSync();
      final macosRegistrant = File(
        'macos/Flutter/GeneratedPluginRegistrant.swift',
      ).readAsStringSync();

      expect(pubspec, contains('flutter_local_notifications: ^22.2.0'));
      expect(lockfile, contains('flutter_local_notifications_linux:'));
      expect(lockfile, contains('flutter_local_notifications_windows:'));
      expect(linuxCmake, contains('generated_plugin_registrant.cc'));
      expect(linuxCmake, contains('include(flutter/generated_plugins.cmake)'));
      expect(
        windowsCmake,
        contains('include(flutter/generated_plugins.cmake)'),
      );
      expect(macosRegistrant, contains('import flutter_local_notifications'));
      expect(
        macosRegistrant,
        contains('FlutterLocalNotificationsPlugin.register('),
      );
    },
  );
}

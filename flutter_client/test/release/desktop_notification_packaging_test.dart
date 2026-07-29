import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('desktop notification dependency is wired into Linux and Windows', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final lockfile = File('pubspec.lock').readAsStringSync();
    final linuxCmake = File('linux/CMakeLists.txt').readAsStringSync();
    final windowsCmake = File('windows/CMakeLists.txt').readAsStringSync();

    expect(pubspec, contains('flutter_local_notifications_linux: ^8.0.1'));
    expect(pubspec, contains('flutter_local_notifications_windows: ^3.1.1'));
    expect(lockfile, contains('flutter_local_notifications_linux:'));
    expect(lockfile, contains('flutter_local_notifications_windows:'));
    expect(linuxCmake, contains('generated_plugin_registrant.cc'));
    expect(linuxCmake, contains('include(flutter/generated_plugins.cmake)'));
    expect(windowsCmake, contains('include(flutter/generated_plugins.cmake)'));
  });
}

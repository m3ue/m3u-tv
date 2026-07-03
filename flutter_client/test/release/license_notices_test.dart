import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  String readFile(String path) => File(path).readAsStringSync();

  test(
    'license notices checklist exists and documents required dependencies',
    () {
      const checklistPath = '../docs/release/license-notices-checklist.md';
      final checklist = readFile(checklistPath);

      for (final expected in <String>[
        'CC BY-NC-SA 4.0',
        'Media3 / ExoPlayer',
        'Apache License 2.0',
        'Flutter SDK and Flutter Plugins',
        'BSD-3-Clause',
        'mpv / libmpv',
        'LGPL-2.1+',
        'FFmpeg',
        'libass',
        'GPL Policy Gate',
        'Do not ship GPL-only binaries',
        'Release Artifact Checklist',
        'Honest Blockers',
      ]) {
        expect(
          checklist,
          contains(expected),
          reason: 'License checklist must mention $expected',
        );
      }
    },
  );

  test('no keystore or signing files are committed in the repository', () {
    final repoDir = Directory('..');
    final suspiciousExtensions = <String>[
      '.jks',
      '.keystore',
      '.p12',
      '.pfx',
    ];
    final suspiciousFileNames = <String>[
      'signing.properties',
      'release.keystore',
      'debug.keystore',
      'upload.keystore',
      'google-play-service-account.json',
      'play-store-service-account.json',
    ];

    final committedFiles = <String>[];

    void scanDirectory(Directory dir) {
      try {
        for (final entity in dir.listSync()) {
          final name = entity.path.split(Platform.pathSeparator).last;

          // Skip build artifacts, dependencies, and ignored directories
          if (entity is Directory) {
            if (name == '.git' ||
                name == '.dart_tool' ||
                name == 'build' ||
                name == 'node_modules' ||
                name == '.pub' ||
                name == '.pub-cache' ||
                name == 'ios' || // ignored by root .gitignore
                name == 'android' || // partially ignored
                name == 'legacy' ||
                name == '.omo' ||
                name == '.vscode' ||
                name == '.idea' ||
                name == '__pycache__') {
              continue;
            }
            scanDirectory(entity);
            continue;
          }

          if (entity is File) {
            final lowerName = name.toLowerCase();
            for (final ext in suspiciousExtensions) {
              if (lowerName.endsWith(ext)) {
                committedFiles.add(entity.path);
              }
            }
            for (final suspicious in suspiciousFileNames) {
              if (lowerName == suspicious) {
                committedFiles.add(entity.path);
              }
            }
          }
        }
      } on FileSystemException {
        // Skip directories we cannot read (e.g., permission denied)
      }
    }

    scanDirectory(repoDir);

    expect(
      committedFiles,
      isEmpty,
      reason:
          'Repository must not contain committed keystore, signing, or store credential files. Found: ${committedFiles.join(', ')}',
    );
  });

  test('no hardcoded signing secrets in gradle or manifest files', () {
    final checkedPaths = <String>[
      'android/app/build.gradle.kts',
      'android/app/src/main/AndroidManifest.xml',
    ];
    final suspiciousPatterns = <RegExp>[
      RegExp(r'storePassword\s*=\s*"[^"]+"', caseSensitive: false),
      RegExp(r"storePassword\s*=\s*'[^']+'", caseSensitive: false),
      RegExp(r'keyPassword\s*=\s*"[^"]+"', caseSensitive: false),
      RegExp(r"keyPassword\s*=\s*'[^']+'", caseSensitive: false),
      RegExp(r'storeFile\s*=\s*file\s*\(\s*"[^"]+"\s*\)', caseSensitive: false),
      RegExp(r"storeFile\s*=\s*file\s*\(\s*'[^']+'\s*\)", caseSensitive: false),
      RegExp(r'android_keystore\s*[:=]\s*', caseSensitive: false),
    ];

    for (final path in checkedPaths) {
      final content = readFile(path);
      for (final pattern in suspiciousPatterns) {
        expect(
          content,
          isNot(matches(pattern)),
          reason:
              '$path must not contain hardcoded signing secrets matching $pattern',
        );
      }
    }
  });

  test('root .gitignore blocks signing and keystore files', () {
    final gitignore = readFile('../.gitignore');

    for (final expected in <String>[
      '*.jks',
      '*.keystore',
      'flutter_client/android/signing.properties',
      'flutter_client/android/*.jks',
      'flutter_client/android/*.keystore',
    ]) {
      expect(
        gitignore,
        contains(expected),
        reason: 'Root .gitignore must block $expected',
      );
    }
  });

  test(
    'platform config files use production app ID or document template status',
    () {
      // Android is the active release platform and must use the production ID
      final androidBuildGradle = readFile('android/app/build.gradle.kts');
      expect(androidBuildGradle, contains('namespace = "dev.sparkison.tv"'));
      expect(
        androidBuildGradle,
        contains('applicationId = "dev.sparkison.tv"'),
      );
      expect(androidBuildGradle, isNot(contains('com.example')));

      // Non-Android platforms are future-gated; they may still have template IDs,
      // but we record them so they are not forgotten when those platforms activate.
      final linuxCmake = readFile('linux/CMakeLists.txt');
      final windowsRc = readFile('windows/runner/Runner.rc');
      final macosConfig = readFile('macos/Runner/Configs/AppInfo.xcconfig');

      // These are known template IDs in non-Android platforms; they are not
      // release blockers today but must be updated before those platforms ship.
      if (linuxCmake.contains('com.example')) {
        expect(
          linuxCmake,
          contains('com.example.m3u_tv'),
          reason: 'Linux template ID must be the known template value',
        );
      }
      if (windowsRc.contains('com.example')) {
        expect(
          windowsRc,
          contains('com.example'),
          reason: 'Windows template ID must be the known template value',
        );
      }
      if (macosConfig.contains('com.example')) {
        expect(
          macosConfig,
          contains('com.example.m3uTv'),
          reason: 'macOS template ID must be the known template value',
        );
      }
    },
  );

  test('Windows runner shows the shell before waiting for first frame', () {
    final flutterWindow = readFile('windows/runner/flutter_window.cpp');
    final attachViewIndex = flutterWindow.indexOf(
      'SetChildContent(flutter_controller_->view()->GetNativeWindow());',
    );
    final immediateShowIndex = flutterWindow.indexOf(
      'this->Show();',
      attachViewIndex,
    );
    final firstFrameIndex = flutterWindow.indexOf(
      'SetNextFrameCallback',
      attachViewIndex,
    );

    expect(attachViewIndex, isNonNegative);
    expect(immediateShowIndex, isNonNegative);
    expect(firstFrameIndex, isNonNegative);
    expect(
      immediateShowIndex,
      lessThan(firstFrameIndex),
      reason:
          'Windows startup must expose a window even if Dart delays frame 1',
    );
  });

  test('Windows bundles MediaKit native video libraries', () {
    final pubspec = readFile('pubspec.yaml');
    final windowsPlugins = readFile('windows/flutter/generated_plugins.cmake');

    expect(pubspec, contains('media_kit_libs_windows_video:'));
    expect(windowsPlugins, contains('media_kit_libs_windows_video'));
  });
}

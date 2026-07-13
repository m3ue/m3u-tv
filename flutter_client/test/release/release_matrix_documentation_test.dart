import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const workflowPath = '../.github/workflows/ci.yml';
  const releaseMatrixPath = '../docs/release/platform-release-matrix.md';
  const readmePath = 'README.md';

  String readFile(String path) => File(path).readAsStringSync();

  test('flutter workflow is the active CI contract', () {
    final workflow = readFile(workflowPath);

    expect(workflow, contains('working-directory: flutter_client'));
    expect(workflow, contains('git clone --depth 1 --branch stable'));
    expect(workflow, contains('/tmp/flutter/bin/flutter --version'));
    expect(workflow, contains('run: /tmp/flutter/bin/flutter analyze'));
    expect(workflow, contains('run: /tmp/flutter/bin/flutter test'));
  });

  test('release matrix documents required toolchains and blockers', () {
    final releaseMatrix = readFile(releaseMatrixPath);

    for (final expected in <String>[
      'Android SDK',
      'JDK',
      'GTK 3 development files',
      'libmpv.so',
      'clang++',
      'Windows GitHub runner',
      'Visual Studio Build Tools',
      'mpv-2.dll',
      'ANDROID_KEYSTORE_PATH',
      'physical Android phone/tablet QA',
      'physical Android TV hardware QA',
      'Emulator logs are supplemental only',
      'Android playback defaults to Media3/ExoPlayer',
      'blocking fallback is m3u-editor server transcode',
      'Android mpv/libmpv remains future-gated and non-blocking',
      'Authenticode/MSIX',
      'Apple Developer ID',
      'Honest Release Blockers',
      'does not expose an official `flutter build tvos` command',
    ]) {
      expect(releaseMatrix, contains(expected));
    }

    expect(releaseMatrix, isNot(contains('Linux production builds pass')));
    expect(releaseMatrix, isNot(contains('Windows production builds pass')));
    expect(releaseMatrix, isNot(contains('Android production builds pass')));
    expect(releaseMatrix, isNot(contains('device or emulator')));
    expect(releaseMatrix, isNot(contains('MPV fallback second')));
    expect(
      releaseMatrix,
      isNot(contains('Android playback is ExoPlayer first')),
    );
  });

  test(
    'apple playback docs keep Apple and tvOS gated outside blocking release scope',
    () {
      final releaseMatrix = readFile(releaseMatrixPath);
      final appleFeasibility = readFile(
        '../docs/migration/apple-playback-store-feasibility.md',
      );

      for (final expected in <String>[
        'AVKit/AVPlayer-safe default',
        'MPVKit/libmpv remains GATED',
        'GPL',
        'LGPL',
        'App Store policy',
        'crash/runtime review',
        'native dependency review',
        'legal review',
        'Platform.isIOS vs tvOS',
        'missing tvOS plugin implementations',
        'community/custom embedder proof',
        'tvOS remains BLOCKED/GATED',
      ]) {
        expect(appleFeasibility, contains(expected));
      }

      for (final expected in <String>[
        'Blocking release targets: Linux desktop, Windows desktop, Android phone/tablet, and Android TV.',
        'macOS desktop | NON-BLOCKING/GATED',
        'iOS/iPadOS | NON-BLOCKING/GATED',
        'tvOS | NON-BLOCKING/GATED and BLOCKED',
        'Apple/tvOS gates do not block the Desktop+Android release track',
      ]) {
        expect(releaseMatrix, contains(expected));
      }

      expect(releaseMatrix, isNot(contains('tvOS production readiness')));
      expect(releaseMatrix, isNot(contains('Apple platforms are blocking')));
      expect(appleFeasibility, isNot(contains('tvOS release-complete')));
      expect(appleFeasibility, isNot(contains('MPVKit is approved')));
    },
  );

  test(
    'android release configuration uses production identifiers and signing placeholders',
    () {
      final buildGradle = readFile('android/app/build.gradle.kts');
      final gitignore = readFile('../.gitignore');

      expect(buildGradle, contains('namespace = "dev.sparkison.tv"'));
      expect(buildGradle, contains('applicationId = "dev.sparkison.tv"'));
      expect(buildGradle, isNot(contains('com.example')));
      expect(buildGradle, contains('create("release")'));
      expect(buildGradle, contains('ANDROID_KEYSTORE_PATH'));
      expect(buildGradle, contains('ANDROID_KEY_ALIAS'));
      expect(buildGradle, contains('ANDROID_KEYSTORE_PASSWORD'));
      expect(buildGradle, contains('ANDROID_KEY_PASSWORD'));
      expect(buildGradle, contains('providers.environmentVariable'));
      expect(buildGradle, contains('signing.properties'));
      // Falls back to debug signing when release keys are absent so contributors
      // can build without credentials; CI supplies keys via env vars.
      expect(buildGradle, contains('hasReleaseSigningKeys()'));
      expect(buildGradle, contains('signingConfigs.getByName("debug")'));

      for (final ignored in <String>[
        'flutter_client/android/signing.properties',
        'flutter_client/android/*.jks',
        'flutter_client/android/*.keystore',
        '*.jks',
        '*.keystore',
      ]) {
        expect(gitignore, contains(ignored));
      }
    },
  );

  test('android gradle flags keep Flutter plugin on compatible DSL path', () {
    final gradleProperties = readFile('android/gradle.properties');
    final settingsGradle = readFile('android/settings.gradle.kts');

    // builtInKotlin=false keeps Flutter's own bundled packages (e.g. integration_test)
    // working because they still declare org.jetbrains.kotlin.android explicitly and break
    // when AGP 9 enforces builtInKotlin=true.
    expect(gradleProperties, contains('android.builtInKotlin=false'));
    expect(gradleProperties, contains('android.newDsl=false'));
    expect(settingsGradle, contains('org.jetbrains.kotlin.android'));
  });

  test('android manifest exposes Android TV launcher metadata', () {
    final manifest = readFile('android/app/src/main/AndroidManifest.xml');

    expect(manifest, contains('android.software.leanback'));
    expect(manifest, contains('android.hardware.touchscreen'));
    final launcherIcon = readFile(
      'android/app/src/main/res/mipmap-anydpi-v26/launcher_icon.xml',
    );
    final launcherIconConfig = readFile('flutter_launcher_icons.yaml');

    expect(manifest, contains('android:banner="@mipmap/ic_launcher"'));
    expect(manifest, contains('android:label="M3U TV"'));
    expect(manifest, contains('android.intent.category.LEANBACK_LAUNCHER'));
    expect(manifest, contains('android:enableOnBackInvokedCallback="true"'));
    expect(manifest, contains('android:exported="true"'));
    expect(launcherIconConfig, contains('adaptive_icon_foreground_inset: 0'));
    expect(launcherIcon, contains('android:inset="0%"'));
    expect(launcherIcon, isNot(contains('android:inset="16%"')));
  });

  test('Android launch and normal themes use the same edge-to-edge window', () {
    for (final path in <String>[
      'android/app/src/main/res/values/styles.xml',
      'android/app/src/main/res/values-night/styles.xml',
      'android/app/src/main/res/values-v31/styles.xml',
      'android/app/src/main/res/values-night-v31/styles.xml',
    ]) {
      final styles = readFile(path);

      expect(
        '<item name="android:windowDrawsSystemBarBackgrounds">true</item>'
            .allMatches(styles),
        hasLength(2),
        reason: path,
      );
      expect(
        '<item name="android:windowFullscreen">false</item>'.allMatches(styles),
        hasLength(2),
        reason: path,
      );
      expect(
        '<item name="android:windowLayoutInDisplayCutoutMode">shortEdges</item>'
            .allMatches(styles),
        hasLength(2),
        reason: path,
      );
    }
  });

  test('android system UI policy is route-aware', () {
    final mainDart = readFile('lib/main.dart');
    final systemUiPolicy = readFile('lib/app/system_ui_policy.dart');
    final mainActivity = readFile(
      'android/app/src/main/kotlin/dev/sparkison/tv/MainActivity.kt',
    );

    // Migration guard: old global immersive mode must not reappear.
    expect(mainDart, isNot(contains('SystemUiMode.immersiveSticky')));
    // Channel name must match between Dart and Kotlin.
    expect(systemUiPolicy, contains('m3u_tv/system_ui'));
    expect(mainActivity, contains('m3u_tv/system_ui'));
    // Native implementation must cover both show and hide paths.
    expect(mainActivity, contains('WindowCompat.setDecorFitsSystemWindows'));
    expect(mainActivity, contains('WindowInsetsCompat.Type.systemBars()'));
    expect(mainActivity, contains('insetsController.show(systemBars)'));
    expect(mainActivity, contains('insetsController.hide(systemBars)'));
    expect(
      mainActivity,
      contains('BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE'),
    );
  });

  test('release matrix documents signing, store, and license gates', () {
    final releaseMatrix = readFile(releaseMatrixPath);

    for (final expected in <String>[
      'Application ID: `dev.sparkison.tv`',
      'Release signing is intentionally blocked until external signing material exists',
      '`flutter_client/android/signing.properties`',
      'No debug signing is allowed for release builds',
      'Android TV launcher metadata',
      'Dependency and License Gates',
      'Media3',
      'Flutter plugins',
      'mpv/libmpv',
      'FFmpeg',
      'libass',
      'GPL',
      'license notices',
      'No Play Store, App Store, Microsoft Store, sideload, or direct-download release is complete',
    ]) {
      expect(releaseMatrix, contains(expected));
    }
  });

  test('repository release files do not commit signing secrets', () {
    final checkedPaths = <String>[
      '../.gitignore',
      'android/app/build.gradle.kts',
      'android/app/src/main/AndroidManifest.xml',
      releaseMatrixPath,
    ];
    final suspiciousSecretPatterns = <RegExp>[
      RegExp(
        '-----BEGIN (?:RSA |EC |OPENSSH |)?PRIVATE KEY-----',
        caseSensitive: false,
      ),
      RegExp(r'storePassword\s*=\s*"[^"]+"', caseSensitive: false),
      RegExp(r"storePassword\s*=\s*'[^']+'", caseSensitive: false),
      RegExp(r'keyPassword\s*=\s*"[^"]+"', caseSensitive: false),
      RegExp(r"keyPassword\s*=\s*'[^']+'", caseSensitive: false),
    ];

    for (final path in checkedPaths) {
      final content = readFile(path);
      for (final pattern in suspiciousSecretPatterns) {
        expect(
          content,
          isNot(matches(pattern)),
          reason: '$path matched $pattern',
        );
      }
    }
  });

  test('flutter readme points contributors at active gates only', () {
    final readme = readFile(readmePath);

    expect(readme, contains('flutter analyze'));
    expect(readme, contains('flutter test'));
    expect(readme, contains('../docs/release/platform-release-matrix.md'));
    expect(readme, contains('physical Android phone/tablet QA'));
    expect(readme, contains('physical Android TV hardware QA'));
    expect(readme, contains('Emulator logs are supplemental only'));
    expect(readme, contains('Android playback defaults to Media3/ExoPlayer'));
    expect(
      readme,
      contains('blocking fallback is m3u-editor server transcode'),
    );
    expect(
      readme,
      contains('Android mpv/libmpv remains future-gated and non-blocking'),
    );
    expect(readme, isNot(contains('device or emulator')));
    expect(readme, isNot(contains('MPV fallback second')));
    expect(readme, isNot(contains('Android playback is ExoPlayer first')));
  });
}

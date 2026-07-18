import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const ciWorkflowPath = '../.github/workflows/ci.yml';
  const releaseWorkflowPath = '../.github/workflows/release.yml';
  const releaseMatrixPath = '../docs/release/platform-release-matrix.md';
  const readmePath = 'README.md';

  String readFile(String path) => File(path).readAsStringSync();

  test('ci workflow is the active Flutter contract', () {
    final workflow = readFile(ciWorkflowPath);

    expect(workflow, contains('working-directory: flutter_client'));
    expect(workflow, contains('git clone --depth 1 --branch stable'));
    expect(workflow, contains('/tmp/flutter/bin/flutter --version'));
    expect(workflow, contains('run: /tmp/flutter/bin/flutter analyze'));
    expect(workflow, contains('run: /tmp/flutter/bin/flutter test'));
  });

  test('release workflow is the active publication contract', () {
    final releaseWorkflow = readFile(releaseWorkflowPath);

    expect(releaseWorkflow, contains('name: Create GitHub Release'));
    expect(releaseWorkflow, contains('name: Build Android APK'));
    expect(releaseWorkflow, contains('name: Build iOS IPA'));
    expect(releaseWorkflow, contains('name: Build tvOS IPA'));
    expect(releaseWorkflow, contains('name: Build macOS DMG'));
    expect(releaseWorkflow, contains('name: Build Linux ZIP'));
    expect(releaseWorkflow, contains('name: Build Windows ZIP'));
  });

  test('release workflow partitions non-Apple and Apple release tracks', () {
    final releaseWorkflow = readFile(releaseWorkflowPath);

    // Non-Apple release job depends only on non-Apple builds
    final nonAppleReleaseIdx = releaseWorkflow.indexOf('release:');
    expect(nonAppleReleaseIdx, greaterThan(-1));
    final nonAppleReleaseSection = releaseWorkflow.substring(
      nonAppleReleaseIdx,
    );
    final needsNonAppleReleaseIdx = nonAppleReleaseSection.indexOf('needs:');
    expect(needsNonAppleReleaseIdx, greaterThan(-1));
    // Extract the needs section by finding the next key at 4-space indent
    final afterNeeds = nonAppleReleaseSection.substring(
      needsNonAppleReleaseIdx,
    );
    final needsNonAppleReleaseEnd = afterNeeds.indexOf(RegExp(r'\n    [a-z]'));
    expect(needsNonAppleReleaseEnd, greaterThan(-1));
    final needsNonAppleRelease = afterNeeds.substring(
      0,
      needsNonAppleReleaseEnd,
    );
    expect(needsNonAppleRelease, contains('build-android'));
    expect(needsNonAppleRelease, contains('build-linux'));
    expect(needsNonAppleRelease, contains('build-windows'));
    expect(needsNonAppleRelease, isNot(contains('build-ios')));
    expect(needsNonAppleRelease, isNot(contains('build-tvos')));
    expect(needsNonAppleRelease, isNot(contains('build-macos')));

    // Apple release job depends on non-Apple release + Apple builds
    final appleReleaseIdx = releaseWorkflow.indexOf('release-apple:');
    expect(appleReleaseIdx, greaterThan(-1));
    final appleReleaseSection = releaseWorkflow.substring(appleReleaseIdx);
    final needsAppleReleaseIdx = appleReleaseSection.indexOf('needs:');
    expect(needsAppleReleaseIdx, greaterThan(-1));
    final afterAppleNeeds = appleReleaseSection.substring(needsAppleReleaseIdx);
    final needsAppleReleaseEnd = afterAppleNeeds.indexOf(
      RegExp(r'\n    [a-z]'),
    );
    expect(needsAppleReleaseEnd, greaterThan(-1));
    final needsAppleRelease = afterAppleNeeds.substring(
      0,
      needsAppleReleaseEnd,
    );
    expect(needsAppleRelease, contains('release'));
    expect(needsAppleRelease, contains('build-ios'));
    expect(needsAppleRelease, contains('build-tvos'));
    expect(needsAppleRelease, contains('build-macos'));
  });

  test('release workflow publishes generated checksum sidecars', () {
    final releaseWorkflow = readFile(releaseWorkflowPath);

    String jobSection(String start, String end) {
      final startIndex = releaseWorkflow.indexOf(start);
      final endIndex = releaseWorkflow.indexOf(end, startIndex + start.length);
      expect(startIndex, greaterThan(-1), reason: start);
      expect(endIndex, greaterThan(startIndex), reason: end);
      return releaseWorkflow.substring(startIndex, endIndex);
    }

    for (final contract
        in <
          ({
            String start,
            String end,
            List<String> checksumCommands,
            String uploadedAsset,
          })
        >[
          (
            start: '  build-android:',
            end: '  build-ios:',
            checksumCommands: const [r'sha256sum "$APK" > "$APK.sha256"'],
            uploadedAsset:
                r'flutter_client/m3u-tv-v${{ needs.validate.outputs.version }}-android.apk',
          ),
          (
            start: '  build-ios:',
            end: '  build-tvos:',
            checksumCommands: const [
              r'shasum -a 256 "$IPA" > "$IPA.sha256"',
            ],
            uploadedAsset:
                r'flutter_client/m3u-tv-v${{ needs.validate.outputs.version }}-ios.ipa',
          ),
          (
            start: '  build-tvos:',
            end: '  build-macos:',
            checksumCommands: const [
              r'shasum -a 256 "$IPA" > "$IPA.sha256"',
            ],
            uploadedAsset:
                r'flutter_client/m3u-tv-v${{ needs.validate.outputs.version }}-tvos.ipa',
          ),
          (
            start: '  build-macos:',
            end: '  build-linux:',
            checksumCommands: const [
              r'shasum -a 256 "$DMG" > "$DMG.sha256"',
            ],
            uploadedAsset:
                r'flutter_client/m3u-tv-v${{ needs.validate.outputs.version }}-macos.dmg',
          ),
          (
            start: '  build-linux:',
            end: '  build-windows:',
            checksumCommands: const [r'sha256sum "$ZIP" > "$ZIP.sha256"'],
            uploadedAsset:
                r'flutter_client/m3u-tv-v${{ needs.validate.outputs.version }}-linux.zip',
          ),
          (
            start: '  build-windows:',
            end: '  release:',
            checksumCommands: const [
              r'$Hash = (Get-FileHash -Algorithm SHA256 $Zip).Hash.ToLowerInvariant()',
              r'"$Hash  $Zip" | Set-Content "$Zip.sha256"',
            ],
            uploadedAsset:
                r'flutter_client/m3u-tv-v${{ needs.validate.outputs.version }}-windows.zip',
          ),
        ]) {
      final section = jobSection(contract.start, contract.end);
      for (final checksumCommand in contract.checksumCommands) {
        expect(section, contains(checksumCommand), reason: contract.start);
      }
      expect(section, contains(contract.uploadedAsset), reason: contract.start);
      expect(
        section,
        contains('${contract.uploadedAsset}.sha256'),
        reason: contract.start,
      );
    }

    void expectReleaseContract({
      required String section,
      required String verifyStep,
      required String releaseStep,
      required List<String> releaseCommands,
      required List<({String verified, String uploaded, bool published})>
      assets,
    }) {
      final verifyIndex = section.indexOf('name: $verifyStep');
      final releaseStepIndex = section.indexOf('name: $releaseStep');
      expect(verifyIndex, greaterThan(-1), reason: verifyStep);
      expect(releaseStepIndex, greaterThan(verifyIndex), reason: releaseStep);

      final verifier = section.substring(verifyIndex, releaseStepIndex);
      expect(verifier, contains('set -euo pipefail'));
      expect(verifier, contains(r'test -s "$asset"'));
      expect(verifier, contains(r'test -s "$asset.sha256"'));
      expect(verifier, contains('sha256sum -c'));

      final releaseBody = section.substring(releaseStepIndex);
      final assetsStart = releaseBody.indexOf('ASSETS=(');
      final assetsEnd = releaseBody.indexOf('\n          )', assetsStart);
      expect(assetsStart, greaterThan(-1), reason: releaseStep);
      expect(assetsEnd, greaterThan(assetsStart), reason: releaseStep);
      final assetArray = releaseBody.substring(assetsStart, assetsEnd);

      for (final asset in assets) {
        expect(verifier, contains('"${asset.verified}"'), reason: verifyStep);
        final artifact = '"${asset.uploaded}"';
        final sidecar = '"${asset.uploaded}.sha256"';
        expect(
          assetArray,
          asset.published ? contains(artifact) : isNot(contains(artifact)),
          reason: releaseStep,
        );
        expect(
          assetArray,
          asset.published ? contains(sidecar) : isNot(contains(sidecar)),
          reason: releaseStep,
        );
      }
      for (final releaseCommand in releaseCommands) {
        final commandIndex = releaseBody.indexOf(releaseCommand);
        expect(commandIndex, greaterThan(assetsEnd), reason: releaseCommand);
      }
    }

    final nonAppleRelease = jobSection('  release:', '  release-apple:');
    expectReleaseContract(
      section: nonAppleRelease,
      verifyStep: 'Verify non-Apple assets',
      releaseStep: 'Create or update release',
      releaseCommands: const ['gh release upload', 'gh release create'],
      assets: const [
        (
          verified: r'artifacts/android-apks/m3u-tv-v${V}-android.apk',
          uploaded: r'artifacts/android-apks/m3u-tv-v${V}-android.apk',
          published: true,
        ),
        (
          verified: r'artifacts/linux-zips/m3u-tv-v${V}-linux.zip',
          uploaded: r'artifacts/linux-zips/m3u-tv-v${V}-linux.zip',
          published: false,
        ),
        (
          verified: r'artifacts/windows-zips/m3u-tv-v${V}-windows.zip',
          uploaded: r'artifacts/windows-zips/m3u-tv-v${V}-windows.zip',
          published: false,
        ),
      ],
    );

    final appleRelease = releaseWorkflow.substring(
      releaseWorkflow.indexOf('  release-apple:'),
    );
    expectReleaseContract(
      section: appleRelease,
      verifyStep: 'Verify Apple assets',
      releaseStep: 'Add Apple assets to release',
      releaseCommands: const ['gh release upload'],
      assets: const [
        (
          verified: r'artifacts/ios-ipas/m3u-tv-v${V}-ios.ipa',
          uploaded:
              r'artifacts/ios-ipas/m3u-tv-v${{ needs.validate.outputs.version }}-ios.ipa',
          published: true,
        ),
        (
          verified: r'artifacts/tvos-ipas/m3u-tv-v${V}-tvos.ipa',
          uploaded:
              r'artifacts/tvos-ipas/m3u-tv-v${{ needs.validate.outputs.version }}-tvos.ipa',
          published: true,
        ),
        (
          verified: r'artifacts/macos-dmgs/m3u-tv-v${V}-macos.dmg',
          uploaded:
              r'artifacts/macos-dmgs/m3u-tv-v${{ needs.validate.outputs.version }}-macos.dmg',
          published: true,
        ),
      ],
    );
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

  test(
    'release workflow blocks desktop ZIPs from public assets while keeping them as workflow artifacts',
    () {
      final releaseWorkflow = readFile('../.github/workflows/release.yml');

      final releaseStepStart = releaseWorkflow.indexOf('  release:');
      final releaseStepEnd = releaseWorkflow.indexOf(
        '  release-apple:',
        releaseStepStart,
      );
      final releaseSection = releaseWorkflow.substring(
        releaseStepStart,
        releaseStepEnd,
      );

      expect(releaseSection, contains('name: Verify non-Apple assets'));
      expect(releaseSection, contains('artifacts/linux-zips/m3u-tv-v'));
      expect(releaseSection, contains('artifacts/windows-zips/m3u-tv-v'));

      final verifyIndex = releaseSection.indexOf(
        'name: Verify non-Apple assets',
      );
      final releaseStepIndex = releaseSection.indexOf(
        'name: Create or update release',
      );
      final verifierSection = releaseSection.substring(
        verifyIndex,
        releaseStepIndex,
      );

      expect(verifierSection, contains('artifacts/linux-zips/m3u-tv-v'));
      expect(verifierSection, contains('artifacts/windows-zips/m3u-tv-v'));

      final releaseBody = releaseSection.substring(releaseStepIndex);
      final assetsStart = releaseBody.indexOf('ASSETS=(');
      final assetsEnd = releaseBody.indexOf('\n          )', assetsStart);
      final assetArray = releaseBody.substring(assetsStart, assetsEnd);

      expect(
        assetArray,
        isNot(contains('linux-zip')),
        reason: 'Linux ZIP must NOT be in public release assets',
      );
      expect(
        assetArray,
        isNot(contains('windows-zip')),
        reason: 'Windows ZIP must NOT be in public release assets',
      );

      expect(
        assetArray,
        contains('android-apk'),
        reason: 'Android APK must remain in public release',
      );

      final releaseSummary = releaseSection.substring(
        releaseSection.indexOf('name: Release summary'),
      );
      expect(releaseSummary, contains('Android + Android TV'));
      expect(releaseSummary, isNot(contains('| Linux |')));
      expect(releaseSummary, isNot(contains('| Windows |')));
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

  test('android publication requires and verifies stable release signing', () {
    final buildGradle = readFile('android/app/build.gradle.kts');
    final releaseWorkflow = readFile(releaseWorkflowPath);
    final releaseMatrix = readFile(releaseMatrixPath);

    expect(buildGradle, contains('ANDROID_REQUIRE_RELEASE_SIGNING'));
    expect(buildGradle, contains('GradleException'));
    expect(
      buildGradle,
      contains('providers.gradleProperty(name).orNull?.takeIf'),
    );
    expect(
      buildGradle,
      contains('providers.environmentVariable(name).orNull?.takeIf'),
    );
    expect(
      buildGradle,
      contains('signingConfigs.getByName("debug")'),
      reason: 'Local contributor builds keep an explicit debug fallback.',
    );

    for (final expected in <String>[
      'set -euo pipefail',
      r'KEYSTORE_B64: ${{ secrets.ANDROID_KEYSTORE_BASE64 }}',
      r'ANDROID_KEY_ALIAS: ${{ secrets.ANDROID_KEY_ALIAS }}',
      r'ANDROID_KEYSTORE_PASSWORD: ${{ secrets.ANDROID_KEYSTORE_PASSWORD }}',
      r'ANDROID_KEY_PASSWORD: ${{ secrets.ANDROID_KEY_PASSWORD }}',
      'ANDROID_KEYSTORE_PATH: ../../upload-keystore.jks',
      'ANDROID_REQUIRE_RELEASE_SIGNING: "true"',
      'APKSIGNER=',
      'verify --verbose --print-certs',
      'Signer #1 certificate SHA-256 digest:',
      'Android Debug',
      r'$GITHUB_STEP_SUMMARY',
    ]) {
      expect(releaseWorkflow, contains(expected));
    }

    final signingPreflight = releaseWorkflow.indexOf(
      '- name: Validate and decode keystore',
    );
    final buildApk = releaseWorkflow.indexOf('- name: Build APK');
    final verifySigner = releaseWorkflow.indexOf('- name: Verify APK signer');
    final stageArtifact = releaseWorkflow.indexOf('- name: Stage artifact');
    final uploadArtifact = releaseWorkflow.indexOf(
      '- uses: actions/upload-artifact@v7',
      verifySigner,
    );
    expect(signingPreflight, lessThan(buildApk));
    expect(buildApk, lessThan(verifySigner));
    expect(verifySigner, lessThan(stageArtifact));
    expect(verifySigner, lessThan(uploadArtifact));

    for (final expected in <String>[
      'local development only',
      'must not publish it',
      'uninstall the existing debug-signed app once',
      'removes local app data and settings',
      'configure the app again',
    ]) {
      expect(releaseMatrix, contains(expected));
    }
  });

  test('desktop release jobs bundle and verify ZIP artifacts', () {
    final linuxCmake = readFile('linux/CMakeLists.txt');
    final releaseWorkflow = readFile(releaseWorkflowPath);

    expect(linuxCmake, contains('RENAME "libmpv.so.2"'));
    expect(linuxCmake, contains('if(TARGET media_kit_video_plugin)'));
    expect(linuxCmake, contains('BUILD_WITH_INSTALL_RPATH TRUE'));
    expect(linuxCmake, contains(r'INSTALL_RPATH "$ORIGIN"'));
    expect(releaseWorkflow, contains('name: Build Linux ZIP'));
    expect(releaseWorkflow, contains('name: Verify Linux bundle'));

    const verifyLinuxStepName = '      - name: Verify Linux bundle';
    final verifyLinuxStepIndex = releaseWorkflow.indexOf(verifyLinuxStepName);
    expect(verifyLinuxStepIndex, greaterThan(-1));
    final verifyLinuxStepEnd = releaseWorkflow.indexOf(
      '\n      - ',
      verifyLinuxStepIndex + verifyLinuxStepName.length,
    );
    expect(verifyLinuxStepEnd, greaterThan(verifyLinuxStepIndex));
    final verifyLinuxStep = releaseWorkflow.substring(
      verifyLinuxStepIndex,
      verifyLinuxStepEnd,
    );
    const runBlockMarker = '\n        run: |\n';
    final runBlockIndex = verifyLinuxStep.indexOf(runBlockMarker);
    expect(runBlockIndex, greaterThan(-1));
    final verifyLinuxRunBlock = verifyLinuxStep.substring(
      runBlockIndex + runBlockMarker.length,
    );
    final runLines = verifyLinuxRunBlock
        .split('\n')
        .map((line) => line.trim())
        .toList();

    final pluginReadelfIndex = runLines.indexOf(
      r'readelf -d "$BUNDLE/lib/libmedia_kit_video_plugin.so" '
      r'\',
    );
    expect(
      pluginReadelfIndex,
      greaterThan(-1),
      reason:
          'The plugin readelf command must be executable in this run block.',
    );
    expect(
      runLines[pluginReadelfIndex + 1],
      '> /tmp/m3u-tv-media-kit-video-dynamic.txt',
    );
    final runpathGrepIndex = runLines.indexOf(
      r"grep -F 'Library runpath: [$ORIGIN]' "
      r'\',
    );
    expect(
      runpathGrepIndex,
      greaterThan(pluginReadelfIndex),
      reason: 'The executable RUNPATH grep must follow the plugin readelf.',
    );
    expect(
      runLines[runpathGrepIndex + 1],
      '/tmp/m3u-tv-media-kit-video-dynamic.txt',
    );

    expect(
      verifyLinuxRunBlock,
      contains(r'test -s "$BUNDLE/lib/libmpv.so.2"'),
    );
    expect(verifyLinuxRunBlock, contains(r'readelf -d "$BUNDLE/m3u_tv"'));
    expect(releaseWorkflow, contains('python3 -m zipfile -c'));
    expect(releaseWorkflow, contains('python3 -m zipfile -t'));
    expect(releaseWorkflow, contains('sha256sum'));
    expect(releaseWorkflow, contains('name: Verify Windows bundle'));
    expect(releaseWorkflow, contains('Expand-Archive'));
    expect(releaseWorkflow, contains('Get-FileHash -Algorithm SHA256'));
    expect(releaseWorkflow, contains('.zip.sha256'));
    expect(releaseWorkflow, contains('.apk.sha256'));
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
      'The publication workflow enables `ANDROID_REQUIRE_RELEASE_SIGNING`',
      '`flutter_client/android/signing.properties`',
      'fail publication instead of producing a debug-signed artifact',
      'debug-signed release build for local development only',
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

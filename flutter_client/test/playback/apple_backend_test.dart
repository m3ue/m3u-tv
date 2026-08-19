import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/playback/apple_backend_feasibility.dart';
import 'package:m3u_tv/playback/playback_capabilities.dart';

void main() {
  group('AppleBackendFeasibility', () {
    test(
      'declares explicit build and playback gates for each Apple target',
      () {
        expect(
          AppleBackendFeasibility.targets.map(
            (target) => target.platform,
          ),
          <AppleTargetPlatform>[
            AppleTargetPlatform.ios,
            AppleTargetPlatform.ipados,
            AppleTargetPlatform.macos,
            AppleTargetPlatform.tvos,
          ],
        );

        final ios = AppleBackendFeasibility.forPlatform(
          AppleTargetPlatform.ios,
        );
        final ipados = AppleBackendFeasibility.forPlatform(
          AppleTargetPlatform.ipados,
        );
        final macos = AppleBackendFeasibility.forPlatform(
          AppleTargetPlatform.macos,
        );
        final tvos = AppleBackendFeasibility.forPlatform(
          AppleTargetPlatform.tvos,
        );

        expect(ios.build.status, AppleFeasibilityStatus.pass);
        expect(ios.playback.status, AppleFeasibilityStatus.pass);
        expect(ipados.build.status, AppleFeasibilityStatus.pass);
        expect(ipados.playback.status, AppleFeasibilityStatus.pass);
        expect(macos.build.status, AppleFeasibilityStatus.pass);
        expect(macos.playback.status, AppleFeasibilityStatus.pass);

        expect(tvos.officialFlutterTarget, isFalse);
        expect(tvos.requiresCustomEmbedder, isTrue);
        expect(tvos.build.status, AppleFeasibilityStatus.pass);
        expect(tvos.playback.status, AppleFeasibilityStatus.pass);
        expect(tvos.remoteInput.status, AppleFeasibilityStatus.blocked);
        expect(tvos.remoteInput.nextStep, contains('GCController'));
      },
    );

    test('keeps AVKit fallback in every iOS/tvOS Apple playback order', () {
      for (final target in AppleBackendFeasibility.targets) {
        expect(
          target.backendOrder.last.backend,
          PlaybackBackend.serverTranscode,
          reason:
              '${target.platform.label} needs server fallback after native paths',
        );
      }

      // iOS/iPadOS/tvOS register AppleAvKitBackend as an automatic fallback
      // (see buildPlaybackOrchestrator() in lib/navigation/app_router.dart).
      for (final platform in <AppleTargetPlatform>[
        AppleTargetPlatform.ios,
        AppleTargetPlatform.ipados,
        AppleTargetPlatform.tvos,
      ]) {
        expect(
          AppleBackendFeasibility.forPlatform(
            platform,
          ).backendOrder.map((capabilities) => capabilities.backend),
          contains(PlaybackBackend.appleAvKit),
          reason: '${platform.label} must not block playback on mpv',
        );
      }

      // macOS registers only MacMpvNativeBackend -- no automatic fallback
      // is wired up yet (media_kit is not a dependency of this project at
      // all, removed for the same MPVKit symbol-collision reason as iOS;
      // see the macOS playback gate's summary/evidence). This asserts the
      // current, accepted gap rather than a fallback that doesn't actually
      // exist, so a future PR that reintroduces a real macOS fallback has
      // to update this test too.
      final macos = AppleBackendFeasibility.forPlatform(
        AppleTargetPlatform.macos,
      );
      expect(
        macos.backendOrder.map((capabilities) => capabilities.backend),
        <PlaybackBackend>[
          PlaybackBackend.macMpvNative,
          PlaybackBackend.serverTranscode,
        ],
      );
    });

    test('records App Store gates and license obligations', () {
      expect(
        AppleBackendFeasibility.appStoreGates.map(
          (gate) => gate.id,
        ),
        containsAll(<String>[
          'public-apis',
          'self-contained-bundle',
          'remote-and-controller-input',
          'no-dynamic-code-download',
        ]),
      );

      final obligationsByName = <String, AppleLicenseObligation>{
        for (final obligation in AppleBackendFeasibility.licenseObligations)
          obligation.component: obligation,
      };

      expect(
        obligationsByName.keys,
        containsAll(<String>[
          'mpv',
          'FFmpeg',
          'MPVKit',
          'libass',
          'Plezy reference code',
        ]),
      );
      expect(obligationsByName['MPVKit']!.license, contains('GPL-3.0'));
      expect(obligationsByName['FFmpeg']!.obligations, contains('configure'));
      expect(
        obligationsByName['Plezy reference code']!.usagePolicy,
        contains('port and adapt directly'),
      );
    });
  });

  group('Apple feasibility document', () {
    test(
      'captures gated matrix, fallback, tvOS decision, and licenses',
      () {
        final document = File(
          '../docs/migration/apple-playback-store-feasibility.md',
        );

        expect(document.existsSync(), isTrue);
        final text = document.readAsStringSync();

        expect(
          text,
          contains(
            '| iOS | PASS for Flutter project generation | WORKING -- confirmed via click-testing on iOS Simulator |',
          ),
        );
        expect(
          text,
          contains(
            '| iPadOS | PASS for Flutter project generation | WORKING (shares the iOS target) |',
          ),
        );
        expect(
          text,
          contains(
            '| macOS | PASS for Flutter project generation | WORKING -- confirmed via click-testing |',
          ),
        );
        expect(
          text,
          contains(
            '| tvOS | Builds via a custom Xcode-based runner (no `flutter build tvos` CLI support) | WORKING',
          ),
        );
        expect(text, contains('Apple platforms stay non-blocking'));
        expect(text, isNot(contains('tvOS release-complete')));
        expect(text, isNot(contains('MPVKit is approved')));
        expect(text, contains('AVKit fallback'));
        expect(text, contains('GCController'));
        expect(text, contains('custom Flutter tvOS embedder'));
        expect(text, contains('App Store Review Guideline 2.5.1'));

        for (final component in <String>[
          'mpv',
          'FFmpeg',
          'MPVKit',
          'libass',
          'Plezy reference code',
        ]) {
          expect(text, contains(component));
        }
      },
    );
  });
}

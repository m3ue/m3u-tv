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
        expect(tvos.build.status, AppleFeasibilityStatus.fail);
        expect(tvos.playback.status, AppleFeasibilityStatus.fail);
        expect(tvos.remoteInput.status, AppleFeasibilityStatus.blocked);
        expect(tvos.remoteInput.nextStep, contains('GCController'));
      },
    );

    test('keeps AVKit or AVPlayer fallback in every Apple playback order', () {
      for (final target in AppleBackendFeasibility.targets) {
        expect(
          target.backendOrder.map(
            (capabilities) => capabilities.backend,
          ),
          contains(PlaybackBackend.appleAvKit),
          reason: '${target.platform.label} must not block playback on mpv',
        );
        expect(
          target.backendOrder.last.backend,
          PlaybackBackend.serverTranscode,
          reason:
              '${target.platform.label} needs server fallback after native paths',
        );
      }

      expect(
        AppleBackendFeasibility.forPlatform(
          AppleTargetPlatform.macos,
        ).backendOrder.first.backend,
        PlaybackBackend.desktopMediaKit,
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
        contains('conceptual'),
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
            '| iOS | PASS for Flutter project generation only | NON-BLOCKING/GATED | AVKit/AVPlayer-safe default for HLS/MP4, then server transcode.',
          ),
        );
        expect(
          text,
          contains(
            '| iPadOS | PASS for Flutter project generation only | NON-BLOCKING/GATED | AVKit/AVPlayer-safe default for HLS/MP4, then server transcode.',
          ),
        );
        expect(
          text,
          contains(
            '| macOS | PASS for Flutter project generation only | NON-BLOCKING/GATED | media_kit (AVFoundation-backed), then server transcode.',
          ),
        );
        expect(text, contains('| tvOS | FAIL | BLOCKED/GATED |'));
        expect(text, contains('Apple platforms stay non-blocking'));
        expect(text, isNot(contains('tvOS release-complete')));
        expect(text, isNot(contains('MPVKit is approved')));
        expect(text, contains('AVKit/AVPlayer fallback'));
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

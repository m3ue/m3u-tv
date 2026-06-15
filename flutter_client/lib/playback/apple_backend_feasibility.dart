import 'package:m3u_tv/playback/playback_capabilities.dart';

enum AppleTargetPlatform { ios, ipados, macos, tvos }

extension AppleTargetPlatformLabel on AppleTargetPlatform {
  String get label {
    return switch (this) {
      AppleTargetPlatform.ios => 'iOS',
      AppleTargetPlatform.ipados => 'iPadOS',
      AppleTargetPlatform.macos => 'macOS',
      AppleTargetPlatform.tvos => 'tvOS',
    };
  }
}

enum AppleFeasibilityStatus { pass, fail, blocked }

class AppleFeasibilityGate {
  const AppleFeasibilityGate({
    required this.status,
    required this.summary,
    required this.evidence,
    required this.nextStep,
  });

  final AppleFeasibilityStatus status;
  final String summary;
  final String evidence;
  final String nextStep;
}

class AppleRemoteInputFeasibility {
  const AppleRemoteInputFeasibility({
    required this.status,
    required this.strategy,
    required this.supportedEvents,
    required this.nextStep,
  });

  final AppleFeasibilityStatus status;
  final String strategy;
  final List<String> supportedEvents;
  final String nextStep;
}

class ApplePlaybackTarget {
  const ApplePlaybackTarget({
    required this.platform,
    required this.officialFlutterTarget,
    required this.requiresCustomEmbedder,
    required this.build,
    required this.playback,
    required this.backendOrder,
    required this.remoteInput,
    required this.signingRequirements,
    required this.publicApiConstraints,
  });

  final AppleTargetPlatform platform;
  final bool officialFlutterTarget;
  final bool requiresCustomEmbedder;
  final AppleFeasibilityGate build;
  final AppleFeasibilityGate playback;
  final List<PlaybackCapabilities> backendOrder;
  final AppleRemoteInputFeasibility remoteInput;
  final List<String> signingRequirements;
  final List<String> publicApiConstraints;
}

class AppleStoreGate {
  const AppleStoreGate({
    required this.id,
    required this.guideline,
    required this.requirement,
    required this.mitigation,
  });

  final String id;
  final String guideline;
  final String requirement;
  final String mitigation;
}

class AppleLicenseObligation {
  const AppleLicenseObligation({
    required this.component,
    required this.license,
    required this.obligations,
    required this.usagePolicy,
  });

  final String component;
  final String license;
  final String obligations;
  final String usagePolicy;
}

class AppleBackendFeasibility {
  const AppleBackendFeasibility._();

  static const List<ApplePlaybackTarget> targets = <ApplePlaybackTarget>[
    ApplePlaybackTarget(
      platform: AppleTargetPlatform.ios,
      officialFlutterTarget: true,
      requiresCustomEmbedder: false,
      build: AppleFeasibilityGate(
        status: AppleFeasibilityStatus.pass,
        summary:
            'Flutter iOS app target and Swift plugin embedding are supported.',
        evidence:
            'Pinned Flutter create help lists iOS project generation; device/App Store builds require a macOS/Xcode host.',
        nextStep:
            'Create an iOS plugin shell with AVPlayer first, then MPVKit behind a license gate.',
      ),
      playback: AppleFeasibilityGate(
        status: AppleFeasibilityStatus.pass,
        summary:
            'MPVKit is feasible for broad codec tests; AVKit/AVPlayer is required as the safe fallback.',
        evidence:
            'Existing React Native bridge links MPVKit and the capability matrix already has Apple AVKit fallback.',
        nextStep:
            'Prefer AVPlayer for HLS/MP4 and invoke MPVKit only when licensing and crash gates pass.',
      ),
      backendOrder: <PlaybackCapabilities>[
        PlaybackCapabilities.appleMpvKit,
        PlaybackCapabilities.appleAvKit,
        PlaybackCapabilities.serverTranscode,
      ],
      remoteInput: AppleRemoteInputFeasibility(
        status: AppleFeasibilityStatus.pass,
        strategy:
            'Use standard Flutter gestures and optional hardware keyboard/gamepad shortcuts.',
        supportedEvents: <String>['touch', 'keyboard', 'gamepad'],
        nextStep: 'Map media keys after the base AVPlayer plugin is running.',
      ),
      signingRequirements: <String>[
        'Bundle MPVKit or AVKit plugin code inside the signed app bundle.',
        'Use Apple Developer signing for device, TestFlight, and App Store builds.',
      ],
      publicApiConstraints: <String>[
        'Use AVFoundation, AVKit, UIKit, Metal, and VideoToolbox public APIs only.',
        'Do not download executable codecs or alter playback behavior with hidden features.',
      ],
    ),
    ApplePlaybackTarget(
      platform: AppleTargetPlatform.ipados,
      officialFlutterTarget: true,
      requiresCustomEmbedder: false,
      build: AppleFeasibilityGate(
        status: AppleFeasibilityStatus.pass,
        summary: 'iPadOS ships through the same supported Flutter iOS target.',
        evidence:
            'Flutter iOS output covers iPad idioms when the Xcode target enables iPad support.',
        nextStep:
            'Keep the plugin universal and verify split-screen safe AVPlayer layout.',
      ),
      playback: AppleFeasibilityGate(
        status: AppleFeasibilityStatus.pass,
        summary:
            'Same MPVKit and AVKit fallback strategy as iOS, with iPad layout validation.',
        evidence:
            'The Apple capability rows are UI-agnostic and do not require phone-only APIs.',
        nextStep:
            'Exercise AVPlayer full-screen, PiP eligibility, and track controls on iPad hardware.',
      ),
      backendOrder: <PlaybackCapabilities>[
        PlaybackCapabilities.appleMpvKit,
        PlaybackCapabilities.appleAvKit,
        PlaybackCapabilities.serverTranscode,
      ],
      remoteInput: AppleRemoteInputFeasibility(
        status: AppleFeasibilityStatus.pass,
        strategy:
            'Use Flutter focus plus optional keyboard/gamepad navigation for iPad accessories.',
        supportedEvents: <String>['touch', 'keyboard', 'gamepad'],
        nextStep:
            'Bind keyboard/gamepad shortcuts to the shared playback action model.',
      ),
      signingRequirements: <String>[
        'Ship as a universal iOS/iPadOS bundle with valid provisioning profiles.',
        'Keep native frameworks embedded and code-signed by Xcode.',
      ],
      publicApiConstraints: <String>[
        'Use AVKit and Flutter platform views through documented APIs.',
        'Keep provider credentials in app container storage and avoid private entitlements.',
      ],
    ),
    ApplePlaybackTarget(
      platform: AppleTargetPlatform.macos,
      officialFlutterTarget: true,
      requiresCustomEmbedder: false,
      build: AppleFeasibilityGate(
        status: AppleFeasibilityStatus.pass,
        summary: 'Flutter macOS desktop target is supported.',
        evidence:
            'Pinned Flutter create help lists macOS project generation; release builds require a macOS/Xcode host.',
        nextStep:
            'Create a macOS plugin that loads a bundled libmpv build and falls back to AVPlayerView.',
      ),
      playback: AppleFeasibilityGate(
        status: AppleFeasibilityStatus.pass,
        summary:
            'Desktop libmpv-style playback is feasible; AVKit/AVPlayer remains the App Store fallback.',
        evidence:
            'The existing playback contract has a Desktop libmpv row and Apple AVKit fallback row.',
        nextStep:
            'Verify sandbox-safe framework embedding and notarized/Mac App Store packaging.',
      ),
      backendOrder: <PlaybackCapabilities>[
        PlaybackCapabilities.desktopLibmpv,
        PlaybackCapabilities.appleAvKit,
        PlaybackCapabilities.serverTranscode,
      ],
      remoteInput: AppleRemoteInputFeasibility(
        status: AppleFeasibilityStatus.pass,
        strategy: 'Use keyboard shortcuts and GameController where available.',
        supportedEvents: <String>['keyboard', 'mouse', 'gamepad'],
        nextStep:
            'Route GCController events through the same playback action dispatcher used by TV remotes.',
      ),
      signingRequirements: <String>[
        'Embed libmpv and dependent dylibs or xcframeworks inside the .app bundle.',
        'Meet Mac App Store sandbox, hardened runtime, and notarization requirements for the chosen channel.',
      ],
      publicApiConstraints: <String>[
        'Use AppKit, AVKit, Metal, VideoToolbox, and GameController public APIs.',
        'Do not spawn unbundled helper binaries or install shared libraries outside the app bundle.',
      ],
    ),
    ApplePlaybackTarget(
      platform: AppleTargetPlatform.tvos,
      officialFlutterTarget: false,
      requiresCustomEmbedder: true,
      build: AppleFeasibilityGate(
        status: AppleFeasibilityStatus.fail,
        summary:
            'Flutter does not provide an official first-class tvOS target in this pinned toolchain.',
        evidence:
            'Flutter create help lists iOS, macOS, and darwin plugin platforms, but no tvOS app or plugin target.',
        nextStep:
            'Prototype or adopt a custom Flutter tvOS embedder before claiming build support.',
      ),
      playback: AppleFeasibilityGate(
        status: AppleFeasibilityStatus.fail,
        summary:
            'Native tvOS AVPlayer and MPVKit are plausible, but Flutter playback is blocked by the embedder gap.',
        evidence:
            'The Expo plugin podspec references tvOS MPVKit, but no Flutter tvOS runner exists to embed it.',
        nextStep:
            'Stand up a tvOS runner, then start with AVKit/AVPlayer fallback before enabling MPVKit.',
      ),
      backendOrder: <PlaybackCapabilities>[
        PlaybackCapabilities.appleMpvKit,
        PlaybackCapabilities.appleAvKit,
        PlaybackCapabilities.serverTranscode,
      ],
      remoteInput: AppleRemoteInputFeasibility(
        status: AppleFeasibilityStatus.blocked,
        strategy:
            'Custom handling must bridge Siri Remote presses and gamepads into Flutter focus actions.',
        supportedEvents: <String>[
          'UIPress',
          'GCController',
          'playPause',
          'menu',
        ],
        nextStep:
            'Prototype GCController and pressesBegan forwarding in the custom Flutter tvOS embedder.',
      ),
      signingRequirements: <String>[
        'Create a tvOS Xcode target with valid Apple TV provisioning and embedded framework signing.',
        'Keep MPVKit/FFmpeg artifacts inside the tvOS app bundle if the licensing decision allows them.',
      ],
      publicApiConstraints: <String>[
        'Use AVKit, AVFoundation, UIKit for tvOS, GameController, Metal, and VideoToolbox public APIs only.',
        'Do not require hardware input beyond Siri Remote unless metadata clearly declares controller requirements.',
      ],
    ),
  ];

  static const List<AppleStoreGate> appStoreGates = <AppleStoreGate>[
    AppleStoreGate(
      id: 'public-apis',
      guideline: 'App Store Review Guideline 2.5.1',
      requirement:
          'Apps may only use public APIs and must run on currently shipping OS versions.',
      mitigation:
          'Use AVKit/AVFoundation/VideoToolbox/Metal/GameController APIs and avoid private Flutter engine hooks in release builds.',
    ),
    AppleStoreGate(
      id: 'self-contained-bundle',
      guideline: 'App Store Review Guidelines 2.4.5 and 2.5.2',
      requirement:
          'Apps must be self-contained bundles and may not download executable playback code.',
      mitigation:
          'Embed and sign every native framework or dylib at build time; stream media only, never codecs.',
    ),
    AppleStoreGate(
      id: 'remote-and-controller-input',
      guideline: 'App Store Review Guideline 2.4.3',
      requirement:
          'Apple TV apps must work with Siri Remote and may add controller support when disclosed.',
      mitigation:
          'Bridge Siri Remote presses and GCController events to Flutter focus before a tvOS claim.',
    ),
    AppleStoreGate(
      id: 'no-dynamic-code-download',
      guideline: 'App Store Review Guideline 2.5.2',
      requirement:
          'Apps may not download or execute code that changes reviewed functionality.',
      mitigation:
          'Treat server transcoding as media output only; do not fetch executable filters or codec modules.',
    ),
  ];

  static const List<AppleLicenseObligation>
  licenseObligations = <AppleLicenseObligation>[
    AppleLicenseObligation(
      component: 'mpv',
      license:
          'GPL-2.0-or-later by default, with LGPL build modes depending on configuration',
      obligations:
          'Publish corresponding source and notices for GPL builds, or prove an LGPL-only configuration before App Store distribution.',
      usagePolicy:
          'Allowed for feasibility only until product/legal choose GPL-compatible distribution or an LGPL-only replacement.',
    ),
    AppleLicenseObligation(
      component: 'FFmpeg',
      license:
          'LGPL/GPL configuration-dependent; nonfree combinations are not redistributable',
      obligations:
          'Record configure flags, enabled codecs, linked libraries, source offers, and relink rights before shipping.',
      usagePolicy:
          'Use AVKit first on Apple; only bundle FFmpeg when the exact build configuration is legally approved.',
    ),
    AppleLicenseObligation(
      component: 'MPVKit',
      license: 'GPL-3.0 in the current local podspec reference',
      obligations:
          'GPL-3.0 distribution requires compatible app licensing and corresponding source for the combined work.',
      usagePolicy:
          'Feasibility-only dependency unless the app license and App Store strategy explicitly accept GPL obligations.',
    ),
    AppleLicenseObligation(
      component: 'libass',
      license: 'ISC permissive license',
      obligations:
          'Preserve copyright and license notices when bundled directly or through mpv/FFmpeg builds.',
      usagePolicy:
          'Permissive subtitle renderer dependency, but inherited mpv/FFmpeg obligations still govern combined binaries.',
    ),
    AppleLicenseObligation(
      component: 'Plezy reference code',
      license: 'GPL reference material',
      obligations:
          'Do not copy source unless the project accepts GPL-compatible licensing for the derived work.',
      usagePolicy:
          'conceptual reference only: architecture lessons may be used, code must not be copied into this repository.',
    ),
  ];

  static ApplePlaybackTarget forPlatform(AppleTargetPlatform platform) {
    return targets.firstWhere(
      (target) => target.platform == platform,
    );
  }
}

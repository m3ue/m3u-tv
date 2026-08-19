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
            'Native mpv via a Flutter PlatformView (vo=avfoundation + hwdec=videotoolbox, rendering to an AVSampleBufferDisplayLayer) is now the primary backend, modeled on the open-source Plezy player. AVKit (appleAvKit) is registered as an automatic fallback; media_kit is not a dependency of this project at all -- it was removed because it vendored a second, independently-versioned ffmpeg/libmpv build that collided at link time with the one MPVKit itself vendors.',
        evidence:
            'buildPlaybackOrchestrator() in lib/navigation/app_router.dart registers only PlaybackBackend.appleMpvNative and PlaybackBackend.appleAvKit for the apple platform; ios/Runner/MpvPlayer/ and tvos/Runner/MpvPlayer/ hold the native Swift implementation.',
        nextStep:
            'Add the MPVKit SPM dependency and verify hardware decode, track selection, and HDR on real iOS/iPadOS devices.',
      ),
      backendOrder: <PlaybackCapabilities>[
        PlaybackCapabilities.appleMpvNative,
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
        'Bundle the MPVKit XCFrameworks (LGPL-3.0 flavor) inside the signed app bundle, alongside AVKit plugin code.',
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
            'Same native mpv (appleMpvNative) primary + AVKit (appleAvKit) fallback strategy as iOS -- media_kit is not a dependency of this project at all -- with iPad layout validation.',
        evidence:
            'The Apple capability rows are UI-agnostic and do not require phone-only APIs.',
        nextStep:
            'Exercise the native mpv PlatformView full-screen, PiP eligibility, and track controls on iPad hardware.',
      ),
      backendOrder: <PlaybackCapabilities>[
        PlaybackCapabilities.appleMpvNative,
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
        nextStep: 'Verify notarized/Mac App Store packaging.',
      ),
      playback: AppleFeasibilityGate(
        status: AppleFeasibilityStatus.pass,
        summary:
            'Native mpv/MPVKit (vo=gpu-next + gpu-context=moltenvk + hwdec=videotoolbox, rendered through a Flutter PlatformView) is now the primary macOS backend, replacing media_kit (AVFoundation-backed) to address macOS performance and HDR limits. A prior native macOS attempt was prototyped and reverted, but it used MPV_RENDER_API_TYPE_SW through the Flutter texture bridge (the same class of bottleneck as media_kit itself), not a PlatformView -- see docs/migration/desktop-libmpv-feasibility.md for the historical record. The app relicensed to GPL-3.0 (with an App Store distribution exception) specifically to allow this, so the prior GPL-incompatibility blocker no longer applies. media_kit is not a dependency of this project at all -- it was removed because it vendored a second, independently-versioned ffmpeg/libmpv build that collided at link time with the one MPVKit itself vendors, so a recoverable macMpvNative load failure currently surfaces directly to the user (via the lastFailure path in PlaybackOrchestrator._openServerTranscode) rather than falling back to another player.',
        evidence:
            'buildPlaybackOrchestrator() in lib/navigation/app_router.dart registers only PlaybackBackend.macMpvNative for macOS -- no other desktop adapter and no server-transcode adapter are registered there, so macMpvNative currently has no automatic fallback.',
        nextStep:
            'Verify sandbox-safe framework embedding and notarized/Mac App Store packaging for the bundled MPVKit XCFrameworks.',
      ),
      backendOrder: <PlaybackCapabilities>[
        // No automatic fallback after macMpvNative -- see the playback gate
        // above and buildPlaybackOrchestrator() in
        // lib/navigation/app_router.dart.
        PlaybackCapabilities.macMpvNative,
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
        'Embed the MPVKit XCFrameworks (LGPL-3.0 flavor) for the native mpv backend inside the .app bundle.',
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
        status: AppleFeasibilityStatus.pass,
        summary:
            'Flutter has no official first-class tvOS target, but this repo already ships a working custom tvOS embedder/runner.',
        evidence:
            'tvos/Runner (AppDelegate.swift, Runner.xcodeproj, TopShelfExtension) is a standing, buildable custom embedder, not a future prototype -- this status previously said "fail" when it should have read the existing runner as evidence.',
        nextStep:
            'Keep the custom embedder current as Flutter tvOS tooling evolves upstream.',
      ),
      playback: AppleFeasibilityGate(
        status: AppleFeasibilityStatus.pass,
        summary:
            'Native mpv via a Flutter PlatformView (vo=avfoundation + hwdec=videotoolbox) is now the primary tvOS backend, same architecture as iOS, modeled on the open-source Plezy player. AVKit is registered as an automatic fallback; media_kit is not a dependency of this project at all.',
        evidence:
            "PlaybackBackend.appleMpvNative is registered first for tvOS in app_router.dart's apple branch; tvos/Runner/MpvPlayer/ holds the native Swift implementation.",
        nextStep:
            "Add the MPVKit SPM dependency, bump TVOS_DEPLOYMENT_TARGET to 15.0, and verify HDR/HDMI-mode-switch behavior on real Apple TV hardware -- the tvOS core does not yet implement Plezy's HDMI display-mode-switch coordination, see the KNOWN GAP note in tvos/Runner/MpvPlayer/MpvPlayerCore.swift.",
      ),
      backendOrder: <PlaybackCapabilities>[
        PlaybackCapabilities.appleMpvNative,
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
      license:
          'LGPL-3.0 (plain MPVKit product) or GPL-3.0 (MPVKit-GPL product, adds Samba support)',
      obligations:
          'Use the plain LGPL-3.0 MPVKit product (not MPVKit-GPL) unless Samba support is specifically needed. Either way, the app itself is now GPL-3.0 (see repository root LICENSE), so combining with either flavor is compatible; preserve upstream copyright/license notices for the bundled XCFrameworks.',
      usagePolicy:
          'Active dependency for the macOS native mpv backend (PlaybackBackend.macMpvNative).',
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
      license: 'GPL-3.0 (github.com/edde746/plezy)',
      obligations:
          'This app is GPL-3.0 as of the macOS native mpv backend work, so Plezy source may be directly adapted, provided upstream copyright/license notices are preserved in the ported files and the resulting m3u-tv code remains GPL-3.0 (or a GPL-compatible license).',
      usagePolicy:
          'Active reference for the macOS native mpv backend (vo=gpu-next/moltenvk/hwdec=videotoolbox) and any future iOS/tvOS work (vo=avfoundation): port and adapt directly rather than reimplementing from scratch, per past ground-up attempts having repeatedly failed.',
    ),
  ];

  static ApplePlaybackTarget forPlatform(AppleTargetPlatform platform) {
    return targets.firstWhere(
      (target) => target.platform == platform,
    );
  }
}

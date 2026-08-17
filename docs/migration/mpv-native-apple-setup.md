# Native mpv Apple Backend: Manual Xcode Setup

The Dart and native Swift source for `PlaybackBackend.macMpvNative` (macOS)
and `PlaybackBackend.appleMpvNative` (iOS/tvOS) is in place, but three steps
require Xcode itself rather than a text edit, because hand-editing
`project.pbxproj` for SPM package resolution or file-reference wiring is
fragile (checksums, `Package.resolved`, build-phase membership) compared to
letting Xcode do it. Do these once per platform target before building.

## 1. Add the MPVKit Swift Package

For **each** of `macos/Runner.xcodeproj`, `ios/Runner.xcodeproj`, and
`tvos/Runner.xcodeproj`:

1. Open the project in Xcode.
2. File > Add Package Dependencies...
3. Enter `https://github.com/mpvkit/MPVKit.git`.
4. Choose the **`MPVKit`** product (plain LGPL-3.0 flavor) -- not
   `MPVKit-GPL`, since Samba support isn't needed. See
   `docs/release/license-notices-checklist.md` for the license rationale.
5. Add it to the `Runner` target (not `RunnerTests`).

## 2. Bump deployment targets

MPVKit's `Package.swift` requires macOS 12+, iOS 15+, tvOS 15+.

| Target | Current | Required | Where |
|---|---|---|---|
| macOS | 10.15 | 12.0 | `macos/Runner.xcodeproj/project.pbxproj`, `MACOSX_DEPLOYMENT_TARGET` (3 occurrences: Debug/Release/Profile) |
| iOS | 15.0 | 15.0 | Already meets the requirement, no change needed |
| tvOS | 13.0 | 15.0 | `tvos/Runner.xcodeproj/project.pbxproj`, `TVOS_DEPLOYMENT_TARGET` |

In Xcode: select the `Runner` project > `Runner` target > Build Settings >
search "Deployment Target" > update for all configurations (or edit the
project-level setting if it's not overridden per-target).

## 3. Add the new Swift files to each Runner target

New files on disk are not automatically compiled by Xcode -- they need an
explicit file reference and target membership.

For each platform, right-click the `Runner` group in the Project Navigator >
"Add Files to Runner..." > select the corresponding `MpvPlayer/` folder,
with "Create groups" and the `Runner` target checkbox both enabled:

- `macos/Runner/MpvPlayer/` (`MpvPlayerCore.swift`, `MpvPlayerPlatformView.swift`, `MpvPlayerPlugin.swift`)
- `ios/Runner/MpvPlayer/` (same three files)
- `tvos/Runner/MpvPlayer/` (same three files)

`macos/Runner/MainFlutterWindow.swift`, `ios/Runner/AppDelegate.swift`, and
`tvos/Runner/AppDelegate.swift` are already-tracked project files and were
edited in place to register the new plugin/platform-view-factory -- no
extra Xcode step needed for those three.

## After setup: build and verify

Follow the verification steps in the approved plan
(`/Users/shaunparkison/.claude/plans/piped-dreaming-wind.md`):

1. `cd flutter_client && flutter analyze lib test` -- clean.
2. `cd flutter_client && flutter test` -- all passing.
3. `flutter build macos` / `flutter build ios` / a tvOS build via Xcode --
   confirm the app launches, play an HLS/VOD fixture on each platform, and
   check:
   - Hardware decode is active (Activity Monitor GPU usage on macOS, not
     100% CPU; Xcode's GPU/CPU gauges on iOS/tvOS).
   - Duration detection and scrubbing work correctly -- this is exactly the
     regression class the previously reverted macOS prototype failed on
     (see `docs/migration/desktop-libmpv-feasibility.md`, "macOS: not
     planned").
   - No CPU spike in the first few seconds after `load()` (the prior
     prototype's `force-seekable=yes` bug; this implementation never sets
     that option).
   - Audio and subtitle track switching works end to end through
     `PlaybackControls`/`TrackSelector`.
   - HDR-tagged sources trigger a wide-gamut/HDR display mode switch. On
     tvOS specifically, this is a known gap -- see the "KNOWN GAP" comment
     in `tvos/Runner/MpvPlayer/MpvPlayerCore.swift` -- and should not be
     advertised as supported until verified on real Apple TV hardware.

If `appleMpvNative` fails to load a stream on iOS/tvOS, the orchestrator
automatically falls back to `AppleAvKitBackend` -- confirm that fallback
path itself still works too, since it's the safety net for this rollout.
`MediaKitIosAdapter` has been removed from the adapter registration
entirely and is no longer a fallback on iOS. On macOS, `MediaKitDesktopAdapter`
was also removed as a fallback for `macMpvNative` -- there is currently no
automatic fallback if native mpv throws on macOS. `MediaKitDesktopAdapter`
is no longer used anywhere on macOS: the separate Multiview surface now
also runs on `MacMpvNativeBackend` -- see `playback-backend-matrix.md`.

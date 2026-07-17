# Non-Apple platform audit and artifact design

## Scope

Audit the current upstream `dev` branch with PR #102 and PR #105 stacked on top. Apple source, Apple builds, and Apple artifacts are excluded.

Target platforms:

- Android and Android TV
- Linux x64 desktop
- Windows x64 desktop

## Audit method

Each platform receives a focused review of platform configuration, native plugins, application startup, playback, persistence, navigation, release build commands, and packaging. Findings must be reproduced through tests, static contract checks, or actual builds before they are treated as defects.

Independent defects are handled separately. Each reproducible defect receives its own upstream issue and its own minimal fix branch and pull request against `dev`. Existing PR #102 and PR #105 remain unchanged.

## Verification

Shared gates:

- dependency resolution
- Dart formatting check
- Flutter analysis
- full Flutter test suite
- platform-specific regression tests
- release build for every requested platform
- archive content inspection
- SHA-256 checksum generation

Android output:

- release APK
- ZIP containing the APK and checksum metadata
- APK signature verification

Linux output:

- complete release bundle ZIP
- executable and shared-library inspection

Windows output:

- complete release bundle ZIP built on a Windows GitHub Actions runner
- archive inspection after download

## Delivery

Final artifacts are built from one pinned integration head containing upstream `dev`, PR #102, PR #105, and every confirmed audit fix. The handoff records the exact commit, archive sizes, SHA-256 checksums, test results, and any hardware-only verification that could not be performed automatically.

// @ts-check

/**
 * Expo config plugin for react-native-mpv.
 *
 * iOS/tvOS: MPVKit is published to the CocoaPods trunk CDN, so no custom
 * `source` line or spec repo registration is needed. The podspec dependency
 * `s.dependency "MPVKit", "~> 0.40.0"` resolves automatically.
 *
 * Android: libmpv is pulled from Maven Central via the module's build.gradle
 * (`dev.jdtech.mpv:libmpv`), so no extra config is needed here either.
 */
module.exports = (config) => config;

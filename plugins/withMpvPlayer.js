// @ts-check
const { withDangerousMod } = require('@expo/config-plugins');
const fs = require('fs');
const path = require('path');

/**
 * Expo config plugin for react-native-mpv.
 *
 * react-native-mpv's podspec lives at the module root, so expo-modules-autolinking
 * discovers and links it automatically. This plugin's only job is to override the
 * MPVKit CocoaPods dependency:
 *
 *   - The trunk CDN specs for MPVKit reference git tags that don't exist and
 *     vendored_framework paths that don't match the actual release zip layout.
 *   - We copy a local MPVKit.podspec into the iOS platform directory and add a
 *     Podfile override that uses it. The local spec downloads the working
 *     0.40.0-av release zip and references the single combined MPVKit.xcframework.
 */

const LOCAL_MPVKIT_PODSPEC = `\
Pod::Spec.new do |s|
  s.name             = 'MPVKit'
  s.version          = '0.40.0'
  s.summary          = 'MPVKit — combined libmpv + FFmpeg xcframework for iOS/tvOS'
  s.homepage         = 'https://github.com/Alexk2309/MPVKit'
  s.license          = { :type => 'GPL-3.0' }
  s.author           = { 'Alexk2309' => 'https://github.com/Alexk2309' }

  s.source = {
    :http => 'https://github.com/Alexk2309/MPVKit/releases/download/0.40.0-av/MPVKit-GPL-Frameworks.zip'
  }

  s.ios.deployment_target  = '13.0'
  s.tvos.deployment_target = '13.0'

  s.static_framework = true

  s.vendored_frameworks = 'MPVKit.xcframework'

  s.frameworks = %w[
    AudioToolbox AVFoundation CoreAudio CoreFoundation
    CoreMedia CoreVideo Metal QuartzCore VideoToolbox
  ]

  s.libraries = %w[bz2 c++ iconv expat resolv xml2 z]

  s.pod_target_xcconfig = {
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]'  => 'i386',
    'EXCLUDED_ARCHS[sdk=appletvsimulator*]' => 'i386 x86_64',
  }
end
`;

module.exports = (config) =>
  withDangerousMod(config, [
    'ios',
    (config) => {
      const iosDir = config.modRequest.platformProjectRoot;

      // Write the local MPVKit podspec into the ios/ directory
      fs.writeFileSync(path.join(iosDir, 'MPVKit.podspec'), LOCAL_MPVKIT_PODSPEC);

      // Patch the Podfile to use the local spec (overrides the broken trunk spec)
      const podfilePath = path.join(iosDir, 'Podfile');
      let podfile = fs.readFileSync(podfilePath, 'utf-8');

      if (!podfile.includes('MPVKit override')) {
        podfile = podfile.replace(
          /(\n[ \t]*post_install do \|installer\|)/,
          [
            '',
            '  # MPVKit override — CocoaPods trunk spec is broken (wrong git tags / bad framework paths).',
            "  # This local spec downloads the working 0.40.0-av release with the correct xcframework.",
            "  pod 'MPVKit', :podspec => './MPVKit.podspec'",
            '',
            '$1',
          ].join('\n'),
        );
        fs.writeFileSync(podfilePath, podfile);
      }

      return config;
    },
  ]);

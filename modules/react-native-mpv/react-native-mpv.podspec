require 'json'

package = JSON.parse(File.read(File.join(__dir__, 'package.json')))

Pod::Spec.new do |s|
  s.name         = "react-native-mpv"
  s.version      = package["version"]
  s.summary      = "React Native mpv player for TV platforms"
  s.homepage     = "https://github.com/nickolay168/libmpv-android"
  s.license      = "MIT"
  s.author       = "m3u-tv"
  s.source       = { :git => ".", :tag => s.version }

  s.ios.deployment_target = '15.1'
  s.tvos.deployment_target = '15.1'

  s.source_files = "ios/*.{h,m,mm,swift}"
  s.swift_version = "5.0"

  s.dependency "React-Core"
  s.dependency "MPVKit", "~> 0.40.0"

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
  }
end

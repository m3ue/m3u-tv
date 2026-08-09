//
//  Generated file. Do not edit.
//

import Flutter
import Foundation

import flutter_secure_storage_tvos
import path_provider_tvos
import sqflite_tvos
import wakelock_plus_tvos

func RegisterGeneratedPlugins(registry: FlutterPluginRegistry) {
  // The registry returns nil registrars when the Flutter engine is not
  // running (on a physical Apple TV the debug engine requires an attached
  // debugger). Nil crashes plugin registration, so bail out loudly.
  guard registry.registrar(forPlugin: "__flutter_tvos_engine_probe__") != nil else {
    NSLog("[GeneratedPluginRegistrant] Flutter engine is not running; skipping plugin registration. Debug builds on a physical Apple TV must be launched via 'flutter-tvos run' (the debug engine requires an attached debugger).")
    return
  }
  FlutterSecureStorageDarwinPlugin.register(with: registry.registrar(forPlugin: "FlutterSecureStorageDarwinPlugin"))
  PathProviderPlugin.register(with: registry.registrar(forPlugin: "PathProviderPlugin"))
  SqflitePlugin.register(with: registry.registrar(forPlugin: "SqflitePlugin"))
  WakelockPlusPlugin.register(with: registry.registrar(forPlugin: "WakelockPlusPlugin"))
}

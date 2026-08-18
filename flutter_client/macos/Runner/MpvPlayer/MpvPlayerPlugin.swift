// Method/event channel plugin for `m3u_tv/mac_mpv` + `m3u_tv/mac_mpv/events`.
//
// Owns a registry of MpvPlayerCore instances keyed by the Dart-generated
// `viewId` (see lib/playback/mac_mpv_native_backend.dart). The core for a
// given viewId is created by MpvPlayerPlatformViewFactory when Flutter
// instantiates the AppKitView, which can race with the Dart adapter's
// `load()` method call arriving first -- `load` retries briefly if the core
// isn't registered yet rather than failing immediately.

import FlutterMacOS
import AppKit

final class MpvPlayerPlugin: NSObject, FlutterStreamHandler, MpvPlayerCoreDelegate {
  static let methodChannelName = "m3u_tv/mac_mpv"
  static let eventChannelName = "m3u_tv/mac_mpv/events"

  private var cores: [Int: MpvPlayerCore] = [:]
  private var eventSink: FlutterEventSink?
  private let lock = NSLock()

  func attachCore(viewId: Int, to view: NSView) {
    lock.lock()
    let staleCore = cores[viewId]
    lock.unlock()
    // A platform view being recreated under a reused viewId before the old
    // one's async dispose completed would otherwise silently orphan its
    // core -- it'd keep running (and holding its native resources) with no
    // reference left in `cores` to ever dispose it.
    if let staleCore {
      staleCore.dispose {}
    }

    let core = MpvPlayerCore(viewId: viewId)
    core.delegate = self
    lock.lock()
    cores[viewId] = core
    lock.unlock()
    core.attach(to: view)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any], let viewId = (args["viewId"] as? NSNumber)?.intValue else {
      result(FlutterError(code: "bad-arguments", message: "viewId is required", details: nil))
      return
    }

    switch call.method {
    case "load":
      waitForCore(viewId: viewId, attemptsRemaining: 100) { [weak self] core in
        guard let core else {
          result(["ok": false, "error": "mpv core not attached", "code": "backend_unavailable"])
          return
        }
        core.load(
          uri: args["uri"] as? String ?? "",
          title: args["title"] as? String,
          startPositionMs: (args["startPositionMs"] as? NSNumber)?.intValue ?? 0,
          isLive: args["isLive"] as? Bool ?? false,
          userAgent: args["userAgent"] as? String,
          headers: args["headers"] as? [String: String],
          externalSubtitles: Self.parseExternalSubtitles(args["externalSubtitles"])
        )
        result(["ok": true])
      }
    case "play":
      core(for: viewId)?.play()
      result(nil)
    case "pause":
      core(for: viewId)?.pause()
      result(nil)
    case "seek":
      let positionMs = (args["positionMs"] as? NSNumber)?.intValue ?? 0
      core(for: viewId)?.seek(positionMs: positionMs)
      result(nil)
    case "stop":
      core(for: viewId)?.stop()
      result(nil)
    case "setAudioTrack":
      core(for: viewId)?.setAudioTrack(trackId: args["trackId"] as? String)
      result(nil)
    case "setSubtitleTrack":
      core(for: viewId)?.setSubtitleTrack(trackId: args["trackId"] as? String)
      result(nil)
    case "setPlaybackSpeed":
      let speed = (args["speed"] as? NSNumber)?.doubleValue ?? 1.0
      core(for: viewId)?.setPlaybackSpeed(speed)
      result(nil)
    case "setVolume":
      let volume = (args["volume"] as? NSNumber)?.doubleValue ?? 100.0
      core(for: viewId)?.setVolume(volume)
      result(nil)
    case "dispose":
      guard let existingCore = core(for: viewId) else {
        result(nil)
        return
      }
      // Only drop the strong reference (`cores`) once teardown has actually
      // finished -- see MpvPlayerCore.dispose's header comment for why.
      existingCore.dispose { [weak self] in
        self?.lock.lock()
        self?.cores.removeValue(forKey: viewId)
        self?.lock.unlock()
        result(nil)
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - MpvPlayerCoreDelegate

  func mpvPlayerCore(_ core: MpvPlayerCore, didEmit event: [String: Any]) {
    DispatchQueue.main.async { [weak self] in
      self?.eventSink?(event)
    }
  }

  // MARK: - FlutterStreamHandler

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  // MARK: - Helpers

  private func core(for viewId: Int) -> MpvPlayerCore? {
    lock.lock()
    defer { lock.unlock() }
    return cores[viewId]
  }

  private func waitForCore(viewId: Int, attemptsRemaining: Int, completion: @escaping (MpvPlayerCore?) -> Void) {
    if let core = core(for: viewId) {
      completion(core)
      return
    }
    if attemptsRemaining <= 0 {
      completion(nil)
      return
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
      self?.waitForCore(viewId: viewId, attemptsRemaining: attemptsRemaining - 1, completion: completion)
    }
  }

  /// Parses the `externalSubtitles` list `PlaybackSource` sends over the
  /// `load` method call (see `MpvNativeBackendBase.load` in
  /// lib/playback/mpv_native_backend_base.dart) into the tuple shape
  /// `MpvPlayerCore.load(externalSubtitles:)` expects.
  static func parseExternalSubtitles(_ raw: Any?) -> [(uri: String, title: String?, language: String?)] {
    guard let list = raw as? [[String: Any]] else { return [] }
    return list.compactMap { entry in
      guard let uri = entry["uri"] as? String, !uri.isEmpty else { return nil }
      return (uri: uri, title: entry["title"] as? String, language: entry["language"] as? String)
    }
  }
}

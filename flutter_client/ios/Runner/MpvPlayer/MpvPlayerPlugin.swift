// Method/event channel plugin for `m3u_tv/apple_mpv` +
// `m3u_tv/apple_mpv/events`.
//
// Owns a registry of MpvPlayerCore instances keyed by the Dart-generated
// `viewId` (see lib/playback/apple_mpv_native_backend.dart). The core for a
// given viewId is created by MpvPlayerPlatformViewFactory when Flutter
// instantiates the UiKitView, which can race with the Dart adapter's
// `load()` method call arriving first -- `load` retries briefly if the core
// isn't registered yet rather than failing immediately.

import AVFoundation
import Flutter

final class MpvPlayerPlugin: NSObject, FlutterStreamHandler, MpvPlayerCoreDelegate {
  static let methodChannelName = "m3u_tv/apple_mpv"
  static let eventChannelName = "m3u_tv/apple_mpv/events"

  private var cores: [Int: MpvPlayerCore] = [:]
  private var eventSink: FlutterEventSink?
  private let lock = NSLock()

  /// `m3u_tv/system_ui`, the channel Android reports picture-in-picture on
  /// (`pipModeChanged`), so PlayerScreen handles both the same way. Also
  /// carries `pipDismissed` (closed without returning to the app) and the
  /// PiP window's buttons (`pipSetPlaying`, `pipSkip`).
  var systemUiChannel: FlutterMethodChannel?

  /// `displayLayer` nil: an audio-only core, created by `load` itself since
  /// no platform view will ever create one (CarPlay with no phone screen).
  func attachCore(viewId: Int, to displayLayer: AVSampleBufferDisplayLayer?) {
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
    core.attach(to: displayLayer)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any], let viewId = (args["viewId"] as? NSNumber)?.intValue else {
      result(FlutterError(code: "bad-arguments", message: "viewId is required", details: nil))
      return
    }

    switch call.method {
    case "load":
      if args["audioOnly"] as? Bool == true, core(for: viewId) == nil {
        Self.activatePlaybackAudioSession()
        attachCore(viewId: viewId, to: nil)
      }
      waitForCore(viewId: viewId, attemptsRemaining: 100) { core in
        guard let core else {
          result(["ok": false, "error": "mpv core not attached", "code": "backend_unavailable"])
          return
        }
        core.load(
          uri: args["uri"] as? String ?? "",
          title: args["title"] as? String,
          startPositionMs: (args["startPositionMs"] as? NSNumber)?.intValue ?? 0,
          isLive: args["isLive"] as? Bool ?? false,
          isCatchup: args["isCatchup"] as? Bool ?? false,
          userAgent: args["userAgent"] as? String,
          headers: args["headers"] as? [String: String],
          externalSubtitles: Self.parseExternalSubtitles(args["externalSubtitles"]),
          deinterlace: args["deinterlace"] as? Bool ?? false,
          prebufferLive: args["prebufferLive"] as? Bool ?? false
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
    case "seekWindow":
      guard let core = core(for: viewId) else {
        result(nil)
        return
      }
      core.seekWindow { state in
        result(state.map { ["cacheState": $0] })
      }
    case "stop":
      core(for: viewId)?.stop()
      result(nil)
    case "setAudioTrack":
      core(for: viewId)?.setAudioTrack(trackId: args["trackId"] as? String)
      result(nil)
    case "setSubtitleTrack":
      core(for: viewId)?.setSubtitleTrack(trackId: args["trackId"] as? String)
      result(nil)
    case "addExternalSubtitle":
      if let uri = args["uri"] as? String, !uri.isEmpty {
        core(for: viewId)?.addExternalSubtitle(
          uri: uri,
          title: args["title"] as? String,
          language: args["language"] as? String
        )
      }
      result(nil)
    case "setPlaybackSpeed":
      let speed = (args["speed"] as? NSNumber)?.doubleValue ?? 1.0
      core(for: viewId)?.setPlaybackSpeed(speed)
      result(nil)
    case "setAutoPictureInPicture":
      core(for: viewId)?.setAutoPictureInPicture(args["enabled"] as? Bool ?? false)
      result(nil)
    case "setSyncOffset":
      let property = args["property"] as? String ?? ""
      let milliseconds = (args["milliseconds"] as? NSNumber)?.intValue ?? 0
      core(for: viewId)?.setSyncOffset(property, seconds: Double(milliseconds) / 1000)
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

  func mpvPlayerCore(_ core: MpvPlayerCore, pictureInPictureActive active: Bool, restored: Bool) {
    invokeSystemUi("pipModeChanged", active)
    if !active && !restored {
      invokeSystemUi("pipDismissed", nil)
    }
  }

  func mpvPlayerCore(_ core: MpvPlayerCore, pictureInPictureSetPlaying playing: Bool) {
    invokeSystemUi("pipSetPlaying", playing)
  }

  func mpvPlayerCore(_ core: MpvPlayerCore, pictureInPictureSkip seconds: Double) {
    invokeSystemUi("pipSkip", seconds)
  }

  private func invokeSystemUi(_ method: String, _ arguments: Any?) {
    DispatchQueue.main.async { [weak self] in
      self?.systemUiChannel?.invokeMethod(method, arguments: arguments)
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

  /// With the phone's screen never opened (the car started the app), no
  /// player has set up the audio session yet, and without the playback
  /// category audio stops when the phone locks.
  private static func activatePlaybackAudioSession() {
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(.playback, mode: .default)
      try session.setActive(true)
    } catch {
      NSLog("[MpvPlayerPlugin] Audio session setup failed: %@", error.localizedDescription)
    }
  }

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
      // Torn down mid-poll: answer the pending Dart load instead of leaving it unresolved.
      guard let self else {
        completion(nil)
        return
      }
      self.waitForCore(viewId: viewId, attemptsRemaining: attemptsRemaining - 1, completion: completion)
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

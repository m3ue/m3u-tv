// Native macOS mpv playback core.
//
// Modeled directly on Plezy's macos/Runner/MpvPlayer/MpvPlayerCore.swift and
// shared/apple/MpvPlayer/MpvPlayerCoreBase.swift (github.com/edde746/plezy,
// GPL-3.0), ported under this app's own GPL-3.0 license -- see repository
// root LICENSE and docs/release/license-notices-checklist.md.
//
// Renders through `vo=gpu-next` + `gpu-context=moltenvk` +
// `hwdec=videotoolbox`, handing mpv the NSView's layer directly via the
// `wid` option so mpv owns and draws into that surface itself, rather than
// going through libmpv's separate render-API embedding path or a Flutter
// texture/CVPixelBuffer bridge. Subtitles are rendered natively (mpv's own
// libass compositing, baked into the gpu-next/libplacebo output).
//
// Deliberately does NOT set `force-seekable=yes` -- that option caused a
// 900% CPU spike (full-stream probing) in a prior, reverted macOS prototype.
// See docs/migration/desktop-libmpv-feasibility.md, "macOS: not planned",
// for that history.

import AppKit
import Libmpv

protocol MpvPlayerCoreDelegate: AnyObject {
  func mpvPlayerCore(_ core: MpvPlayerCore, didEmit event: [String: Any])
}

/// MoltenVK's `vkCreateMetalSurfaceEXT` (`MVKSurface::initLayer`) requires an
/// actual `CAMetalLayer` -- handing mpv a plain `NSView`-backed layer via
/// `wid` crashes inside MoltenVK trying to treat it as one. Ported from
/// Plezy's `MpvMetalLayer`; the zero-drawable-size guard matches
/// https://github.com/mpv-player/mpv/pull/13651.
final class MpvMetalLayer: CAMetalLayer {
  override var drawableSize: CGSize {
    get { super.drawableSize }
    set {
      guard newValue.width > 0, newValue.height > 0 else { return }
      super.drawableSize = newValue
    }
  }
}

final class MpvPlayerCore {
  let viewId: Int
  weak var delegate: MpvPlayerCoreDelegate?

  private var mpv: OpaquePointer?
  private let queue: DispatchQueue
  private var sequence = 0
  private var readyEmitted = false
  private var disposed = false
  private var metalLayer: MpvMetalLayer?
  private var frameObserver: NSObjectProtocol?

  init(viewId: Int) {
    self.viewId = viewId
    self.queue = DispatchQueue(label: "m3u_tv.mac_mpv.\(viewId)")
  }

  /// Creates and initializes the mpv handle, targeting a `CAMetalLayer`
  /// inserted into `view`'s layer as the render surface. Must be called
  /// once, before `load`.
  func attach(to view: NSView) {
    // Layer/view mutation is AppKit UI work and must happen on the main
    // thread -- everything else below is safe to do on the mpv queue.
    view.wantsLayer = true
    let metalLayer = MpvMetalLayer()
    metalLayer.autoresizingMask = [.layerWidthSizable, .layerHeightSizable]
    view.layer?.addSublayer(metalLayer)
    self.metalLayer = metalLayer

    // `CAMetalLayer.drawableSize` is independent of `frame`/`bounds` and is
    // never synced by AppKit automatically. The `AppKitView` is also
    // created with `frame: .zero` before Flutter lays it out (see
    // MpvPlayerPlatformView.swift), so the size at `attach()` time is not
    // yet the real one either -- track every subsequent frame change so
    // libplacebo's swapchain gets a real drawable size once layout
    // actually happens. Without this, `vo/gpu-next` silently fails its
    // `reconfig` (drawable size 0x0) and mpv drops the video track
    // entirely, falling back to audio-only playback with a black screen.
    view.postsFrameChangedNotifications = true
    updateMetalLayerGeometry(metalLayer, for: view)
    frameObserver = NotificationCenter.default.addObserver(
      forName: NSView.frameDidChangeNotification,
      object: view,
      queue: .main
    ) { [weak self, weak view] _ in
      guard let self, let view, let metalLayer = self.metalLayer else { return }
      self.updateMetalLayerGeometry(metalLayer, for: view)
    }

    queue.async { [weak self] in
      guard let self, self.mpv == nil else { return }

      guard let handle = mpv_create() else {
        self.emitError(message: "mpv_create failed", code: "backend_unavailable")
        return
      }
      self.mpv = handle

      var layerPointer = Int64(bitPattern: UInt64(UInt(bitPattern: Unmanaged.passUnretained(metalLayer).toOpaque())))
      mpv_set_option(handle, "wid", MPV_FORMAT_INT64, &layerPointer)

      mpv_set_option_string(handle, "vo", "gpu-next")
      mpv_set_option_string(handle, "gpu-context", "moltenvk")
      mpv_set_option_string(handle, "hwdec", "videotoolbox")
      mpv_set_option_string(handle, "hwdec-codecs", "all")
      mpv_set_option_string(handle, "hwdec-software-fallback", "yes")
      mpv_set_option_string(handle, "keep-open", "yes")
      mpv_set_option_string(handle, "vd-lavc-dr", "yes")
      // Deliberately no `force-seekable` -- see file header.

      let observed: [(String, mpv_format)] = [
        ("time-pos", MPV_FORMAT_DOUBLE),
        ("duration", MPV_FORMAT_DOUBLE),
        ("pause", MPV_FORMAT_FLAG),
        ("core-idle", MPV_FORMAT_FLAG),
        ("eof-reached", MPV_FORMAT_FLAG),
        ("speed", MPV_FORMAT_DOUBLE),
        ("aid", MPV_FORMAT_STRING),
        ("sid", MPV_FORMAT_STRING),
        ("track-list", MPV_FORMAT_NODE),
        ("video-params/aspect", MPV_FORMAT_DOUBLE),
      ]
      for (index, entry) in observed.enumerated() {
        mpv_observe_property(handle, UInt64(index), entry.0, entry.1)
      }

      let context = Unmanaged.passUnretained(self).toOpaque()
      mpv_set_wakeup_callback(handle, { context in
        guard let context else { return }
        let core = Unmanaged<MpvPlayerCore>.fromOpaque(context).takeUnretainedValue()
        core.queue.async { core.drainEvents() }
      }, context)

      let result = mpv_initialize(handle)
      if result < 0 {
        self.emitError(message: "mpv_initialize failed (\(result))", code: "backend_unavailable")
        mpv_terminate_destroy(handle)
        self.mpv = nil
        return
      }
    }
  }

  private func updateMetalLayerGeometry(_ metalLayer: MpvMetalLayer, for view: NSView) {
    let scale = view.window?.backingScaleFactor ?? 2.0
    metalLayer.frame = view.bounds
    metalLayer.contentsScale = scale
    metalLayer.drawableSize = CGSize(
      width: view.bounds.width * scale,
      height: view.bounds.height * scale
    )
  }

  func load(
    uri: String,
    title: String?,
    startPositionMs: Int,
    isLive: Bool,
    userAgent: String?,
    headers: [String: String]?
  ) {
    queue.async { [weak self] in
      guard let self, let handle = self.mpv else { return }
      self.readyEmitted = false

      if let userAgent, !userAgent.isEmpty {
        mpv_set_option_string(handle, "user-agent", userAgent)
      }
      if let headers, !headers.isEmpty {
        let headerString = headers.map { "\($0.key): \($0.value)" }.joined(separator: ",")
        mpv_set_option_string(handle, "http-header-fields", headerString)
      }

      var args: [String?] = ["loadfile", uri, "replace"]
      if startPositionMs > 0 {
        args.append("0")
        args.append("start=\(startPositionMs / 1000)")
      }
      self.command(handle, args.compactMap { $0 })
    }
  }

  func play() {
    queue.async { [weak self] in
      guard let self, let handle = self.mpv else { return }
      mpv_set_property_string(handle, "pause", "no")
    }
  }

  func pause() {
    queue.async { [weak self] in
      guard let self, let handle = self.mpv else { return }
      mpv_set_property_string(handle, "pause", "yes")
    }
  }

  func seek(positionMs: Int) {
    queue.async { [weak self] in
      guard let self, let handle = self.mpv else { return }
      self.command(handle, ["seek", String(Double(positionMs) / 1000.0), "absolute"])
    }
  }

  func stop() {
    queue.async { [weak self] in
      guard let self, let handle = self.mpv else { return }
      self.command(handle, ["stop"])
    }
  }

  func setAudioTrack(trackId: String?) {
    queue.async { [weak self] in
      guard let self, let handle = self.mpv else { return }
      mpv_set_property_string(handle, "aid", trackId ?? "no")
    }
  }

  func setSubtitleTrack(trackId: String?) {
    queue.async { [weak self] in
      guard let self, let handle = self.mpv else { return }
      mpv_set_property_string(handle, "sid", trackId ?? "no")
    }
  }

  func setPlaybackSpeed(_ speed: Double) {
    queue.async { [weak self] in
      guard let self, let handle = self.mpv else { return }
      mpv_set_property_string(handle, "speed", String(speed))
    }
  }

  func setVolume(_ volume: Double) {
    queue.async { [weak self] in
      guard let self, let handle = self.mpv else { return }
      mpv_set_property_string(handle, "volume", String(volume))
    }
  }

  /// `completion` fires only once `mpv_terminate_destroy` has actually
  /// finished -- that call blocks until mpv's internal render thread has
  /// stopped touching the `CAMetalLayer` handed to it via `wid` (an
  /// unretained pointer -- `Unmanaged.passUnretained` -- so ARC has no idea
  /// mpv still needs it alive). If the plugin's `dispose` method-channel
  /// call resolved before mpv actually stopped, Dart could tear down the
  /// platform view -- deallocating that layer -- while mpv's render thread
  /// was still mid-write to it: a use-after-free that reliably crashes with
  /// EXC_BAD_ACCESS on stop. Mirrors the tvOS/iOS cores' `dispose(completion:)`.
  func dispose(completion: @escaping () -> Void) {
    // Deliberately a strong capture, not `[weak self]`: `MpvPlayerPlugin`
    // calls `dispose(completion:)` and only drops its own dictionary entry
    // -- the only other strong reference -- once `completion` fires. A weak
    // capture would let ARC deallocate `self` before this block runs, so
    // `guard let self` would fail silently and
    // `mpv_terminate_destroy`/unregistering the wakeup callback would never
    // happen. mpv's core thread would keep running with its wakeup callback
    // pointing at freed memory, crashing (SIGSEGV) the next time it fires
    // an event. Keeping `self` alive until real teardown completes here is
    // required, not just tidiness.
    queue.async {
      guard let handle = self.mpv, !self.disposed else {
        DispatchQueue.main.async { completion() }
        return
      }
      self.disposed = true
      mpv_set_wakeup_callback(handle, nil, nil)
      mpv_terminate_destroy(handle)
      self.mpv = nil
      DispatchQueue.main.async {
        if let frameObserver = self.frameObserver {
          NotificationCenter.default.removeObserver(frameObserver)
          self.frameObserver = nil
        }
        self.metalLayer?.removeFromSuperlayer()
        self.metalLayer = nil
        completion()
      }
    }
  }

  // MARK: - Event pump

  private func drainEvents() {
    guard let handle = mpv, !disposed else { return }
    while true {
      guard let event = mpv_wait_event(handle, 0) else { break }
      if event.pointee.event_id == MPV_EVENT_NONE { break }
      handle_(event: event.pointee)
    }
  }

  private func handle_(event: mpv_event) {
    switch event.event_id {
    case MPV_EVENT_START_FILE:
      emit(kind: "START_FILE", extra: [:])
    case MPV_EVENT_FILE_LOADED:
      readyEmitted = true
      emit(kind: "FILE_LOADED", extra: snapshot(includeTracks: true))
    case MPV_EVENT_PLAYBACK_RESTART:
      emit(kind: "PLAYBACK_RESTART", extra: snapshot(includeTracks: true))
    case MPV_EVENT_PROPERTY_CHANGE:
      if readyEmitted {
        // Most property-change events are `time-pos` ticks (essentially
        // every frame during playback); only re-walk the track list when
        // the property that actually changed is track-related, so a
        // position tick doesn't pay for an mpv_get_property(track-list)
        // NODE walk + Dart-side re-parse dozens of times a second.
        let includeTracks = Self.trackRelatedPropertyIndices.contains(event.reply_userdata)
        emit(kind: "PLAYBACK_RESTART", extra: snapshot(includeTracks: includeTracks))
      }
    case MPV_EVENT_END_FILE:
      if let data = event.data {
        let endFile = data.assumingMemoryBound(to: mpv_event_end_file.self).pointee
        if endFile.reason == MPV_END_FILE_REASON_ERROR {
          let message = String(cString: mpv_error_string(endFile.error))
          emitError(message: message, code: "mac-mpv-error")
          return
        }
      }
      emit(kind: "END_FILE", extra: [:])
    case MPV_EVENT_IDLE, MPV_EVENT_SHUTDOWN:
      emit(kind: "SHUTDOWN", extra: [:])
    default:
      break
    }
  }

  /// Indices passed to `mpv_observe_property` in `attach(to:)` for
  /// properties whose change should trigger a `track-list` re-walk in
  /// `snapshot(includeTracks:)` -- `aid`, `sid`, `track-list`.
  private static let trackRelatedPropertyIndices: Set<UInt64> = [6, 7, 8]

  private func snapshot(includeTracks: Bool) -> [String: Any] {
    guard let handle = mpv else { return [:] }
    var result: [String: Any] = [:]

    var doublePos: Double = 0
    if mpv_get_property(handle, "time-pos", MPV_FORMAT_DOUBLE, &doublePos) >= 0 {
      result["positionMs"] = Int(doublePos * 1000)
    }
    var doubleDur: Double = 0
    if mpv_get_property(handle, "duration", MPV_FORMAT_DOUBLE, &doubleDur) >= 0, doubleDur > 0 {
      result["durationMs"] = Int(doubleDur * 1000)
    }
    var pauseFlag: Int32 = 0
    if mpv_get_property(handle, "pause", MPV_FORMAT_FLAG, &pauseFlag) >= 0 {
      result["paused"] = pauseFlag != 0
    }
    var idleFlag: Int32 = 0
    if mpv_get_property(handle, "core-idle", MPV_FORMAT_FLAG, &idleFlag) >= 0 {
      result["buffering"] = idleFlag != 0 && (result["paused"] as? Bool) != true
    }
    var speed: Double = 1
    if mpv_get_property(handle, "speed", MPV_FORMAT_DOUBLE, &speed) >= 0 {
      result["speed"] = speed
    }
    var aspect: Double = 0
    if mpv_get_property(handle, "video-params/aspect", MPV_FORMAT_DOUBLE, &aspect) >= 0, aspect > 0 {
      result["videoAspectRatio"] = aspect
    }

    if let aid = stringProperty(handle, "aid") {
      result["aid"] = aid
    }
    if let sid = stringProperty(handle, "sid") {
      result["sid"] = sid
    }

    if includeTracks {
      let tracks = trackList(handle)
      result["audioTracks"] = tracks.filter { $0["type"] as? String == "audio" }
        .map { ["id": $0["id"] as Any, "label": $0["label"] as Any, "language": $0["language"] as Any] }
      result["subtitleTracks"] = tracks.filter { $0["type"] as? String == "sub" }
        .map { ["id": $0["id"] as Any, "label": $0["label"] as Any, "language": $0["language"] as Any] }
    }

    return result
  }

  private func stringProperty(_ handle: OpaquePointer, _ name: String) -> String? {
    guard let raw = mpv_get_property_string(handle, name) else { return nil }
    defer { mpv_free(raw) }
    let value = String(cString: raw)
    return value.isEmpty || value == "no" ? nil : value
  }

  private func trackList(_ handle: OpaquePointer) -> [[String: Any]] {
    var node = mpv_node()
    guard mpv_get_property(handle, "track-list", MPV_FORMAT_NODE, &node) >= 0 else { return [] }
    defer { mpv_free_node_contents(&node) }
    guard node.format == MPV_FORMAT_NODE_ARRAY, let list = node.u.list else { return [] }

    var tracks: [[String: Any]] = []
    for i in 0..<Int(list.pointee.num) {
      guard let itemNode = list.pointee.values?[i] else { continue }
      guard itemNode.format == MPV_FORMAT_NODE_MAP, let map = itemNode.u.list else { continue }

      var id: String?
      var type: String?
      var lang: String?
      var title: String?
      for j in 0..<Int(map.pointee.num) {
        guard let key = map.pointee.keys?[j] else { continue }
        let keyName = String(cString: key)
        let valueNode = map.pointee.values?[j]
        switch keyName {
        case "id":
          if let valueNode, valueNode.format == MPV_FORMAT_INT64 {
            id = String(valueNode.u.int64)
          }
        case "type":
          if let valueNode, valueNode.format == MPV_FORMAT_STRING, let cstr = valueNode.u.string {
            type = String(cString: cstr)
          }
        case "lang":
          if let valueNode, valueNode.format == MPV_FORMAT_STRING, let cstr = valueNode.u.string {
            lang = String(cString: cstr)
          }
        case "title":
          if let valueNode, valueNode.format == MPV_FORMAT_STRING, let cstr = valueNode.u.string {
            title = String(cString: cstr)
          }
        default:
          break
        }
      }

      guard let id, let type, type == "audio" || type == "sub" else { continue }
      tracks.append([
        "id": id,
        "type": type,
        "label": title ?? lang ?? "Track \(id)",
        "language": lang as Any,
      ])
    }
    return tracks
  }

  private func command(_ handle: OpaquePointer, _ args: [String]) {
    var cArgs: [UnsafePointer<CChar>?] = args.map { strdup($0).map { UnsafePointer($0) } }
    cArgs.append(nil)
    _ = mpv_command(handle, &cArgs)
    for pointer in cArgs where pointer != nil {
      free(UnsafeMutableRawPointer(mutating: pointer))
    }
  }

  private func emit(kind: String, extra: [String: Any]) {
    sequence += 1
    var payload: [String: Any] = ["viewId": viewId, "sequence": sequence, "kind": kind]
    payload.merge(extra) { _, new in new }
    delegate?.mpvPlayerCore(self, didEmit: payload)
  }

  private func emitError(message: String, code: String) {
    sequence += 1
    delegate?.mpvPlayerCore(self, didEmit: [
      "viewId": viewId,
      "sequence": sequence,
      "kind": "ERROR",
      "message": message,
      "code": code,
      "recoverable": true,
    ])
  }
}

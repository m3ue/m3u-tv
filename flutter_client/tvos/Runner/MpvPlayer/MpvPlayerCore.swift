// Native tvOS mpv playback core.
//
// Modeled directly on Plezy's tvOS MpvPlayerCore (github.com/edde746/plezy,
// GPL-3.0), ported under this app's own GPL-3.0 license -- see repository
// root LICENSE and docs/release/license-notices-checklist.md.
//
// Renders through `vo=avfoundation` + `hwdec=videotoolbox`, handing mpv an
// AVSampleBufferDisplayLayer directly via the `wid` option, the same
// approach as the iOS core (ios/Runner/MpvPlayer/MpvPlayerCore.swift).
//
// Deliberately does NOT set `force-seekable=yes` -- see the macOS core's
// header comment and docs/migration/desktop-libmpv-feasibility.md for why.
//
// HDR playback requests an actual HDMI display-mode switch on the TV via
// `AVDisplayManager`/`AVDisplayCriteria` (tvOS 17+) -- `target-colorspace-hint`
// (the option that works for Windows/Linux) is inert on the avfoundation VO,
// since tvOS EDR requires switching the physical HDMI link, not just the
// render surface. Ported from Plezy's `updateDisplayCriteria`
// (ios/Runner/MpvPlayer/MpvPlayerCore.swift, `#if os(tvOS)` branches) and
// `validateSideDataDimensions` (shared/apple/MpvPlayer/MpvPlayerCoreBase.swift).
// Deliberately simplified relative to that reference: no user-facing HDR
// toggle (this app applies HDR automatically per source everywhere, matching
// the Windows/Linux HDR paths), no `ServerDisplayCriteria` metadata-hint-server
// integration (not applicable to this app's architecture), and no
// `DisplayModeSwitchWaiter` mode-switch-completion choreography -- a momentary
// flash during the HDMI switch is a cosmetic risk worth deferring until real
// Apple TV/HDR-display testing shows it's actually needed, not a functional
// blocker to build around up front.

import AVFoundation
import AVKit
import Libmpv
import UIKit

protocol MpvPlayerCoreDelegate: AnyObject {
  func mpvPlayerCore(_ core: MpvPlayerCore, didEmit event: [String: Any])
}

private enum DisplayDynamicRange: String {
  case sdr = "SDR"
  case hdr10 = "HDR10"
  case hlg = "HLG"
  case dolbyVision = "Dolby Vision"
}

private struct DisplayCriteriaInputs: Equatable {
  var width: Double = 0
  var height: Double = 0
  var sigPeak: Double = 0
  var doviProfile: Int64 = 0
  var doviLevel: Int64 = 0
  var containerFps: Double = 0
  /// `estimated-vf-fps` at the first shown frame. Changes every frame, so it
  /// is read at PLAYBACK_RESTART only, never observed.
  var estimatedFps: Double = 0
  var deinterlaceActive = false
  var gamma: String?
  var primaries: String?
  var colorMatrix: String?
}

final class MpvPlayerCore {
  let viewId: Int
  weak var delegate: MpvPlayerCoreDelegate?

  private var mpv: OpaquePointer?
  private let queue: DispatchQueue
  private var sequence = 0
  private var readyEmitted = false
  private var disposed = false

  // Set once from `attach(to:hostView:)` so `updateDisplayCriteria` can
  // resolve `.window` later -- the view isn't in the hierarchy yet (and has
  // no window) at attach time, so this can't be resolved up front.
  private weak var hostView: UIView?
  private var activeDisplayCriteriaKey: String?

  // Display-criteria inputs and hold, both owned by `queue`. Held from a
  // file's START_FILE/END_FILE until its first PLAYBACK_RESTART (and before
  // the first file): nothing is committed while held, so the previous
  // file's mode stays on the HDMI link until the next file's first frame
  // shows whether it needs to change. Without the hold, the teardown and
  // startup property deliveries of a channel zap or episode advance cleared
  // the criteria ("invalid video dimensions") and re-set the same mode,
  // renegotiating HDMI for seconds per transition (Plezy e30ba79c5).
  private var displayCriteriaInputs = DisplayCriteriaInputs()
  private var displayCriteriaHeld = true

  // Set fresh on every `load()`, read only on `queue` (see
  // `commitDisplayCriteria`, which captures it into the main-thread
  // `updateDisplayCriteria` call rather than reading it there directly) --
  // same single-queue-owns-it convention as `readyEmitted`/`disposed`.
  // Default true is a belt-and-suspenders fallback only; the authoritative
  // default lives in ViewSettingsService.matchRefreshRate (Dart), which
  // defaults tvOS on to preserve this path's pre-toggle unconditional
  // behavior.
  private var matchRefreshRateEnabled = true

  private static let maximumSideDataDimension: Int64 = 16384
  private static let maximumSideDataPixels: Int64 = 16384 * 16384

  // `UIWindow.avDisplayManager` throws `doesNotRecognizeSelector:` when
  // touched on the tvOS Simulator -- the class doesn't implement it there,
  // unlike `isDisplayCriteriaMatchingEnabled`-style flags that just report a
  // safe default. HDMI display-mode switching is meaningless in Simulator
  // anyway, so skip the whole AVDisplayManager path there instead of
  // depending on any one property being safe to call.
  //
  // The same "unrecognized selector" crash also hit real devices (GitHub
  // #239) -- `avDisplayManager` is an AVKit Objective-C category on
  // UIWindow, and Swift's automatic linking doesn't reliably emit
  // `-framework AVKit` for category-only usage. Fixed by explicitly linking
  // AVKit via `OTHER_LDFLAGS` on the Runner target in
  // Runner.xcodeproj/project.pbxproj (all three configs: Debug/Release/
  // Profile) -- deliberately NOT in tvos/Flutter/{Debug,Release}.xcconfig
  // (Plezy's approach) because `flutter-tvos build tvos` regenerates those
  // files, silently dropping any manual edits on every build.
  private static let isSimulator: Bool = {
    #if targetEnvironment(simulator)
      return true
    #else
      return false
    #endif
  }()

  init(viewId: Int) {
    self.viewId = viewId
    self.queue = DispatchQueue(label: "m3u_tv.apple_mpv.tvos.\(viewId)")
  }

  /// Creates and initializes the mpv handle, targeting `displayLayer` as the
  /// render surface. `hostView` is the layer's containing view, retained
  /// weakly so HDR display-criteria updates can resolve its `.window` once
  /// it's actually in the view hierarchy. Must be called once, before `load`.
  func attach(to displayLayer: AVSampleBufferDisplayLayer, hostView: UIView) {
    self.hostView = hostView
    queue.async { [weak self] in
      guard let self, self.mpv == nil else { return }

      guard let handle = mpv_create() else {
        self.emitError(message: "mpv_create failed", code: "backend_unavailable")
        return
      }
      self.mpv = handle

      var layerPointer = Int64(
        bitPattern: UInt64(UInt(bitPattern: Unmanaged.passUnretained(displayLayer).toOpaque()))
      )
      mpv_set_option(handle, "wid", MPV_FORMAT_INT64, &layerPointer)

      // Must be set before mpv_initialize -- Plezy's tvOS core notes this
      // ordering avoids a freeze on player exit specific to this VO on tvOS.
      mpv_set_option_string(handle, "avfoundation-composite-osd", "yes")
      mpv_set_option_string(handle, "vo", "avfoundation")
      mpv_set_option_string(handle, "hwdec", "videotoolbox")
      mpv_set_option_string(handle, "hwdec-codecs", "all")
      mpv_set_option_string(handle, "hwdec-software-fallback", "yes")
      mpv_set_option_string(handle, "keep-open", "yes")
      mpv_set_option_string(handle, "vd-lavc-dr", "yes")
      // `fuzzy` auto-loads sidecar subtitle files (`.srt`/`.vtt`) next to a
      // local/network URI whose filename fuzzily matches, in addition to
      // whatever `sub-add` calls `load(subtitles:)` issues explicitly below.
      mpv_set_option_string(handle, "sub-auto", "fuzzy")
      // This app only ever plays direct/proxy/server URLs, never generic
      // web pages, and never bundles a youtube-dl/yt-dlp binary -- mpv's
      // built-in ytdl_hook script would otherwise try (and fail to find)
      // one on every URL load, surfacing as an opaque "ytdl_hook:
      // youtube-dl failed: not found or not enough permissions" end-file
      // error even for plain local/network media.
      mpv_set_option_string(handle, "ytdl", "no")
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
        // HDR display-criteria inputs -- appended rather than interleaved so
        // the indices above (relied on by trackRelatedPropertyIndices) don't
        // shift. See resolveBaseDisplayDynamicRange/updateDisplayCriteria.
        ("video-params/sig-peak", MPV_FORMAT_DOUBLE),
        ("width", MPV_FORMAT_DOUBLE),
        ("height", MPV_FORMAT_DOUBLE),
        ("current-tracks/video/dolby-vision-profile", MPV_FORMAT_INT64),
        ("current-tracks/video/dolby-vision-level", MPV_FORMAT_INT64),
        ("container-fps", MPV_FORMAT_DOUBLE),
        ("video-params/gamma", MPV_FORMAT_STRING),
        ("video-params/primaries", MPV_FORMAT_STRING),
        ("video-params/colormatrix", MPV_FORMAT_STRING),
        ("deinterlace-active", MPV_FORMAT_FLAG),
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

  func load(
    uri: String,
    title: String?,
    startPositionMs: Int,
    isLive: Bool,
    isCatchup: Bool,
    userAgent: String?,
    headers: [String: String]?,
    externalSubtitles: [(uri: String, title: String?, language: String?)] = [],
    matchRefreshRate: Bool = true,
    deinterlace: Bool = false
  ) {
    queue.async { [weak self] in
      guard let self, let handle = self.mpv else { return }
      self.readyEmitted = false
      self.matchRefreshRateEnabled = matchRefreshRate

      if let userAgent, !userAgent.isEmpty {
        mpv_set_option_string(handle, "user-agent", userAgent)
      }
      if let headers, !headers.isEmpty {
        let headerString = headers.map { "\($0.key): \($0.value)" }.joined(separator: ",")
        mpv_set_option_string(handle, "http-header-fields", headerString)
      }
      // Live sources get a larger demuxer probe budget -- ffmpeg's default
      // analyzeduration/probesize can be too tight for a live MPEG-TS/HLS
      // stream under network jitter (VPN hops, slow first-byte), especially
      // at higher (UHD) bitrates: "No format found, try lowering probescore
      // or forcing the format" is ffmpeg giving up before enough consistent
      // data arrived, not a real format mismatch. Deliberately not forcing
      // demuxer-lavf-format -- live sources vary (raw MPEG-TS vs real HLS
      // depending on the server/proxy setup), so this only widens ffmpeg's
      // own auto-probe window rather than assuming a container. Always set
      // explicitly (not just when live) -- this mpv handle persists across
      // every load (see `attach(to:hostView:)`), so a live-set override must
      // not leak into a subsequent VOD/Series load on the same handle; the
      // non-live values match ffmpeg's own stock defaults, so this is a
      // no-op for VOD, not a behavior change.
      mpv_set_option_string(handle, "demuxer-lavf-analyzeduration", isLive ? "10" : "5")
      mpv_set_option_string(handle, "demuxer-lavf-probesize", isLive ? "10000000" : "5000000")
      // A catchup timeline comes from the EPG, not the file, so skip FFmpeg reading the end
      // of the file to estimate its duration, and let the probe rewind inside a larger
      // stream buffer: a catchup open then costs one request to the provider instead of
      // three. Reset for every other load, since this handle persists across loads.
      mpv_set_option_string(handle, "demuxer-lavf-o", isCatchup ? "skip_estimate_duration_from_pts=1" : "")
      mpv_set_option_string(handle, "stream-buffer-size", isCatchup ? "4MiB" : "128KiB")
      // The Deinterlace setting: `auto` filters only frames flagged interlaced. Set on
      // every load, since this handle persists across loads.
      mpv_set_option_string(handle, "deinterlace", deinterlace ? "auto" : "no")

      var args: [String?] = ["loadfile", uri, "replace"]
      if startPositionMs > 0 {
        args.append("0")
        args.append("start=\(startPositionMs / 1000)")
      }
      self.command(handle, args.compactMap { $0 })

      // Queued right after `loadfile` -- mpv processes commands in order, so
      // each sidecar subtitle is attached to the file that was just queued
      // rather than whatever was previously playing.
      for subtitle in externalSubtitles {
        var subArgs = ["sub-add", subtitle.uri, "auto"]
        if let title = subtitle.title, !title.isEmpty {
          subArgs.append(title)
          if let language = subtitle.language, !language.isEmpty {
            subArgs.append(language)
          }
        }
        self.command(handle, subArgs)
      }
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

  /// mpv's demuxer cache state, as JSON. Its `seekable-ranges` are the positions a seek
  /// reaches without fetching more data, which Dart uses to plan catchup seeks.
  func seekWindow(completion: @escaping (String?) -> Void) {
    queue.async { [weak self] in
      var state: String?
      if let self, let handle = self.mpv {
        state = self.stringProperty(handle, "demuxer-cache-state")
      }
      DispatchQueue.main.async { completion(state) }
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

  /// `completion` fires only once `mpv_terminate_destroy` has actually
  /// finished -- that call blocks until mpv's internal render thread has
  /// stopped touching the `AVSampleBufferDisplayLayer` handed to it via
  /// `wid` (an unretained pointer -- `Unmanaged.passUnretained` -- so ARC
  /// has no idea mpv still needs it alive). If the plugin's `dispose`
  /// method-channel call resolved before mpv actually stopped (as the old
  /// `queue.async`-and-forget version did), Dart could tear down the
  /// platform view -- deallocating that layer -- while mpv's render thread
  /// was still mid-write to it: a use-after-free that reliably crashed with
  /// EXC_BAD_ACCESS on stop.
  ///
  /// This runs `mpv_terminate_destroy` on `queue` via `async`, not `sync`:
  /// blocking the caller (the method channel handler, which Flutter invokes
  /// on the main thread) for however long mpv takes to fully tear down
  /// stalled the whole UI thread long enough to look unresponsive to the
  /// debugger/watchdog. `completion` gives callers the same "don't proceed
  /// until mpv is actually done" guarantee without blocking anything.
  func dispose(completion: @escaping () -> Void) {
    // Reset the HDMI display-mode hint on main before mpv tears down --
    // otherwise the TV stays switched into whatever range the last clip
    // requested even after playback stops. Safe to fire-and-forget async
    // here (unlike Plezy's synchronous version): `completion` and this
    // core's removal from MpvPlayerPlugin's `cores` dictionary only happen
    // after the `queue.async` block below finishes, so `self` stays alive
    // for this to run against.
    DispatchQueue.main.async { [weak self] in
      guard let self, !Self.isSimulator, let window = self.hostView?.window else { return }
      self.clearDisplayCriteria(window.avDisplayManager, reason: "dispose")
    }

    // Captures `self` strongly, deliberately -- not `[weak self]`. mpv holds
    // an *unretained* raw pointer to this instance (`wid`, and the wakeup
    // callback below via `Unmanaged.passUnretained`) for as long as the mpv
    // handle is alive, and can call into it from its own internal thread at
    // any time until `mpv_terminate_destroy` actually unregisters it. If
    // this instance's only strong reference (MpvPlayerPlugin's `cores`
    // entry) were dropped before this block runs, ARC could deallocate it
    // while mpv still holds that raw pointer -- exactly the EXC_BAD_ACCESS
    // this crashed with, in the wakeup callback's `Unmanaged...
    // .takeUnretainedValue()`. Capturing `self` here keeps it alive for the
    // full duration of teardown, matching what mpv actually needs.
    queue.async {
      guard let handle = self.mpv, !self.disposed else {
        DispatchQueue.main.async { completion() }
        return
      }
      self.disposed = true
      mpv_set_wakeup_callback(handle, nil, nil)
      mpv_terminate_destroy(handle)
      self.mpv = nil
      DispatchQueue.main.async { completion() }
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
      displayCriteriaHeld = true
      emit(kind: "START_FILE", extra: [:])
    case MPV_EVENT_FILE_LOADED:
      readyEmitted = true
      emit(kind: "FILE_LOADED", extra: snapshot(includeTracks: true))
    case MPV_EVENT_PLAYBACK_RESTART:
      // The first shown frame after a load or seek. mpv delivers queued
      // events before pending property changes, so the observed values can
      // still be the previous file's or its teardown's here; this one
      // synchronous read is the file's authoritative snapshot and its first
      // commit.
      if let handle = mpv {
        displayCriteriaInputs = readDisplayCriteriaInputs(handle)
        displayCriteriaHeld = false
        commitDisplayCriteria()
      }
      emit(kind: "PLAYBACK_RESTART", extra: snapshot(includeTracks: true))
    case MPV_EVENT_PROPERTY_CHANGE:
      if Self.displayCriteriaPropertyIndices.contains(event.reply_userdata), !displayCriteriaHeld,
        let data = event.data,
        refineDisplayCriteria(with: data.assumingMemoryBound(to: mpv_event_property.self).pointee)
      {
        commitDisplayCriteria()
      }
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
      // Queued before any teardown-valued property delivery, so the hold is
      // in place before those could commit.
      displayCriteriaHeld = true
      if let data = event.data {
        let endFile = data.assumingMemoryBound(to: mpv_event_end_file.self).pointee
        if endFile.reason == MPV_END_FILE_REASON_ERROR {
          let message = String(cString: mpv_error_string(endFile.error))
          emitError(message: message, code: "apple-mpv-error")
          return
        }
        // A `stop` (or quit) ends the current file too, but only a real end
        // of stream is END_FILE, which Dart reads as playback completed. The
        // Windows core makes the same split.
        if endFile.reason == MPV_END_FILE_REASON_STOP {
          emit(kind: "STOP", extra: [:])
          return
        }
        if endFile.reason == MPV_END_FILE_REASON_QUIT {
          emit(kind: "QUIT", extra: [:])
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

  /// Indices passed to `mpv_observe_property` in `attach(to:hostView:)` for
  /// properties whose change should trigger a `track-list` re-walk in
  /// `snapshot(includeTracks:)` -- `aid`, `sid`, `track-list`.
  private static let trackRelatedPropertyIndices: Set<UInt64> = [6, 7, 8]

  /// Indices of the HDR display-criteria inputs appended to `observed` in
  /// `attach(to:hostView:)` (sig-peak, width, height, Dolby Vision
  /// profile/level, container-fps, gamma, primaries, colormatrix,
  /// deinterlace-active).
  private static let displayCriteriaPropertyIndices: Set<UInt64> = [10, 11, 12, 13, 14, 15, 16, 17, 18, 19]

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

  // MARK: - HDR display-mode switching

  /// Reads every display-criteria input synchronously (on `queue`, where mpv
  /// access is safe). Taken as authoritative: an unavailable property means
  /// the stream lacks it.
  private func readDisplayCriteriaInputs(_ handle: OpaquePointer) -> DisplayCriteriaInputs {
    var inputs = DisplayCriteriaInputs()
    _ = mpv_get_property(handle, "video-params/sig-peak", MPV_FORMAT_DOUBLE, &inputs.sigPeak)
    _ = mpv_get_property(handle, "width", MPV_FORMAT_DOUBLE, &inputs.width)
    _ = mpv_get_property(handle, "height", MPV_FORMAT_DOUBLE, &inputs.height)
    _ = mpv_get_property(handle, "current-tracks/video/dolby-vision-profile", MPV_FORMAT_INT64, &inputs.doviProfile)
    _ = mpv_get_property(handle, "current-tracks/video/dolby-vision-level", MPV_FORMAT_INT64, &inputs.doviLevel)
    _ = mpv_get_property(handle, "container-fps", MPV_FORMAT_DOUBLE, &inputs.containerFps)
    _ = mpv_get_property(handle, "estimated-vf-fps", MPV_FORMAT_DOUBLE, &inputs.estimatedFps)
    var deinterlaceActive: Int32 = 0
    _ = mpv_get_property(handle, "deinterlace-active", MPV_FORMAT_FLAG, &deinterlaceActive)
    inputs.deinterlaceActive = deinterlaceActive != 0
    inputs.gamma = stringProperty(handle, "video-params/gamma")
    inputs.primaries = stringProperty(handle, "video-params/primaries")
    inputs.colorMatrix = stringProperty(handle, "video-params/colormatrix")
    return inputs
  }

  /// Folds one observer delivery into `displayCriteriaInputs`, returning
  /// whether anything changed. Only a delivered value counts: an unavailable
  /// one is ambiguous (teardown, a superseded read, or genuinely absent) and
  /// only the PLAYBACK_RESTART snapshot can tell which.
  private func refineDisplayCriteria(with property: mpv_event_property) -> Bool {
    guard property.format != MPV_FORMAT_NONE, let data = property.data, let name = property.name else {
      return false
    }
    var inputs = displayCriteriaInputs
    switch (String(cString: name), property.format) {
    case ("video-params/sig-peak", MPV_FORMAT_DOUBLE): inputs.sigPeak = data.load(as: Double.self)
    case ("width", MPV_FORMAT_DOUBLE): inputs.width = data.load(as: Double.self)
    case ("height", MPV_FORMAT_DOUBLE): inputs.height = data.load(as: Double.self)
    case ("current-tracks/video/dolby-vision-profile", MPV_FORMAT_INT64):
      inputs.doviProfile = data.load(as: Int64.self)
    case ("current-tracks/video/dolby-vision-level", MPV_FORMAT_INT64):
      inputs.doviLevel = data.load(as: Int64.self)
    case ("container-fps", MPV_FORMAT_DOUBLE): inputs.containerFps = data.load(as: Double.self)
    case ("deinterlace-active", MPV_FORMAT_FLAG): inputs.deinterlaceActive = data.load(as: Int32.self) != 0
    case (let key, MPV_FORMAT_STRING):
      guard let cString = data.assumingMemoryBound(to: UnsafePointer<CChar>?.self).pointee else { return false }
      let value = String(cString: cString)
      switch key {
      case "video-params/gamma": inputs.gamma = value
      case "video-params/primaries": inputs.primaries = value
      case "video-params/colormatrix": inputs.colorMatrix = value
      default: return false
      }
    default:
      return false
    }
    guard inputs != displayCriteriaInputs else { return false }
    displayCriteriaInputs = inputs
    return true
  }

  /// Hands the current inputs to `updateDisplayCriteria` on main (where
  /// `AVDisplayManager` must be touched). Runs on `queue`; never while held.
  private func commitDisplayCriteria() {
    guard !displayCriteriaHeld else { return }
    let inputs = displayCriteriaInputs
    // Presented one frame per field when mpv's deinterlacer runs, or when
    // the first frame's cadence says the decoder deinterlaced by itself:
    // either way the display should run at twice the container rate.
    let fieldOutput =
      inputs.deinterlaceActive
      || Self.presentsFields(container: inputs.containerFps, presented: inputs.estimatedFps)
    let fps = Self.nominalRefreshRate(fieldOutput ? inputs.containerFps * 2 : inputs.containerFps)
    // Read here, on `queue` -- see `matchRefreshRateEnabled`'s doc comment.
    let matchRefreshRateEnabled = self.matchRefreshRateEnabled

    DispatchQueue.main.async { [weak self] in
      self?.updateDisplayCriteria(
        doviProfile: inputs.doviProfile,
        doviLevel: inputs.doviLevel,
        fps: fps,
        width: Int32(inputs.width),
        height: Int32(inputs.height),
        sigPeak: inputs.sigPeak,
        gamma: inputs.gamma,
        primaries: inputs.primaries,
        colorMatrix: inputs.colorMatrix,
        matchRefreshRateEnabled: matchRefreshRateEnabled
      )
    }
  }

  /// Whether the measured output cadence is the container rate doubled. The
  /// band absorbs millisecond timestamp rounding and one duplicated
  /// timestamp in the measurement window while rejecting duplicated,
  /// dropped or telecined cadences (3.0, 0.5, 1.25). From Plezy's
  /// `MpvPlayerCoreBase.presentsFields`.
  private static func presentsFields(container: Double, presented: Double) -> Bool {
    guard container > 0, presented > 0 else { return false }
    let ratio = presented / container
    return ratio > 1.7 && ratio < 2.3
  }

  /// Rates a TV advertises display modes for, in Hz.
  private static let nominalRefreshRates: [Double] = [
    23.976, 24, 25, 29.97, 30, 48, 50, 59.94, 60, 100, 119.88, 120,
  ]

  /// The nearest nominal rate when `fps` is within 1% of one (FFmpeg's own
  /// band for rounding a guessed frame rate), otherwise `fps` unchanged.
  /// Container rates are declared or averaged, never measured (a 29.97i
  /// capture reads 29.95784, an MKV with a 42 ms frame duration 23.8095),
  /// and tvOS hands the pick to AVDisplayManager, which only has modes for
  /// nominal rates, so the request itself has to be nominal (Plezy
  /// 81f0b49cb).
  private static func nominalRefreshRate(_ fps: Double) -> Double {
    guard fps > 0 else { return 0 }
    guard let nearest = nominalRefreshRates.min(by: { abs($0 - fps) < abs($1 - fps) }) else { return fps }
    return abs(nearest - fps) / nearest < 0.01 ? nearest : fps
  }

  /// Requests an HDMI display-mode switch matching the current source's
  /// dynamic range via `AVDisplayManager`/`AVDisplayCriteria`. Must run on
  /// main. Ported from Plezy's tvOS `updateDisplayCriteria` -- see file
  /// header for what was deliberately left out.
  @discardableResult
  private func updateDisplayCriteria(
    doviProfile: Int64,
    doviLevel: Int64,
    fps: Double,
    width: Int32,
    height: Int32,
    sigPeak: Double,
    gamma: String?,
    primaries: String?,
    colorMatrix: String?,
    matchRefreshRateEnabled: Bool
  ) -> Bool {
    guard !Self.isSimulator, let window = hostView?.window else { return false }
    let displayManager = window.avDisplayManager

    guard Self.validateSideDataDimensions(width: Int64(width), height: Int64(height)) else {
      clearDisplayCriteria(displayManager, reason: "invalid video dimensions")
      return false
    }

    // The bail-out below (and the criteria key/request itself) uses
    // `effectiveRefreshRate`, gated on the toggle -- dynamic-range criteria
    // stays unconditional either way, matching this app's "HDR is always
    // automatic on Apple platforms" rule (see player_adapter.dart's
    // HdrToggleProvider doc comment). The raw `refreshRate` still decides
    // whether *anything* about the stream is display-metadata-worthy, so a
    // genuinely fps-less/metadata-less source bails out the same as before
    // this toggle existed, regardless of the setting.
    let refreshRate = Float(fps > 0 ? fps : 0)
    let effectiveRefreshRate = matchRefreshRateEnabled ? refreshRate : 0
    let sourceHasDolbyVision = doviProfile > 0
    guard
      refreshRate > 0 || sourceHasDolbyVision || sigPeak > 0 || gamma != nil || primaries != nil
        || colorMatrix != nil
    else {
      clearDisplayCriteria(displayManager, reason: "no display metadata")
      return false
    }

    guard displayManager.isDisplayCriteriaMatchingEnabled else {
      clearDisplayCriteria(displayManager, reason: "matching disabled")
      return false
    }
    guard #available(tvOS 17.0, *) else {
      clearDisplayCriteria(displayManager, reason: "display criteria unavailable")
      return false
    }

    let sourceBaseRange = Self.resolveBaseDisplayDynamicRange(
      sigPeak: sigPeak, gamma: gamma, primaries: primaries, colorMatrix: colorMatrix)
    var displayRange: DisplayDynamicRange =
      sourceHasDolbyVision ? .dolbyVision : Self.supportedDisplayDynamicRange(for: sourceBaseRange)

    var formatDescription = Self.makeDisplayFormatDescription(
      dynamicRange: displayRange, width: width, height: height,
      doviProfile: doviProfile, doviLevel: doviLevel)
    if formatDescription == nil, sourceHasDolbyVision {
      // Profile/level didn't yield a usable Dolby Vision format description
      // (e.g. mpv hasn't resolved them yet) -- fall back to the base HDR10/
      // HLG/SDR range derived from color tags alone rather than requesting
      // nothing.
      displayRange = sourceBaseRange
      formatDescription = Self.makeDisplayFormatDescription(
        dynamicRange: displayRange, width: width, height: height,
        doviProfile: doviProfile, doviLevel: doviLevel)
    }

    guard let formatDescription else {
      clearDisplayCriteria(displayManager, reason: "format description failed")
      return false
    }

    let criteriaKey =
      "\(displayRange.rawValue)|\(effectiveRefreshRate)|\(width)x\(height)|\(doviProfile)|\(doviLevel)"
    if activeDisplayCriteriaKey == criteriaKey && displayManager.preferredDisplayCriteria != nil {
      return true
    }

    displayManager.preferredDisplayCriteria = AVDisplayCriteria(
      refreshRate: effectiveRefreshRate, formatDescription: formatDescription)
    activeDisplayCriteriaKey = criteriaKey
    NSLog(
      "[MpvPlayerCore] preferredDisplayCriteria set to %@ (fps: %@, %dx%d, DV profile: %@, level: %@)",
      displayRange.rawValue, String(effectiveRefreshRate), width, height, String(doviProfile), String(doviLevel)
    )
    return true
  }

  private func clearDisplayCriteria(_ displayManager: AVDisplayManager, reason: String) {
    guard displayManager.isDisplayCriteriaMatchingEnabled else { return }
    guard activeDisplayCriteriaKey != nil || displayManager.preferredDisplayCriteria != nil else { return }
    displayManager.preferredDisplayCriteria = nil
    activeDisplayCriteriaKey = nil
    NSLog("[MpvPlayerCore] preferredDisplayCriteria cleared (%@)", reason)
  }

  /// Sanity bounds check before touching CoreMedia APIs -- guards against
  /// nonsensical/overflowing dimensions from malformed video-params.
  private static func validateSideDataDimensions(width: Int64, height: Int64) -> Bool {
    guard width > 0, height > 0, width <= maximumSideDataDimension, height <= maximumSideDataDimension
    else { return false }
    let (pixels, overflow) = width.multipliedReportingOverflow(by: height)
    return !overflow && pixels <= maximumSideDataPixels
  }

  private static func normalizeColorTag(_ value: String?) -> String {
    value?.lowercased().filter { $0.isLetter || $0.isNumber } ?? ""
  }

  private static func resolveBaseDisplayDynamicRange(
    sigPeak: Double,
    gamma: String?,
    primaries: String?,
    colorMatrix: String?
  ) -> DisplayDynamicRange {
    let normalizedGamma = normalizeColorTag(gamma)
    let normalizedPrimaries = normalizeColorTag(primaries)
    let normalizedColorMatrix = normalizeColorTag(colorMatrix)

    if normalizedGamma.contains("hlg") || normalizedGamma.contains("arib") {
      return .hlg
    }
    if normalizedGamma.contains("pq") || normalizedGamma.contains("smpte2084")
      || normalizedGamma.contains("st2084") || sigPeak > 1.0
      || normalizedPrimaries.contains("bt2020") || normalizedColorMatrix.contains("bt2020")
    {
      return .hdr10
    }
    return .sdr
  }

  /// Clamps to what the connected TV actually supports (`AVPlayer.availableHDRModes`)
  /// so we never request a display mode the hardware can't do.
  private static func supportedDisplayDynamicRange(for range: DisplayDynamicRange) -> DisplayDynamicRange {
    let availableModes = AVPlayer.availableHDRModes
    switch range {
    case .dolbyVision:
      if availableModes.contains(.dolbyVision) { return .dolbyVision }
      if availableModes.contains(.hdr10) { return .hdr10 }
      if availableModes.contains(.hlg) { return .hlg }
      return .sdr
    case .hdr10:
      return availableModes.contains(.hdr10) ? .hdr10 : .sdr
    case .hlg:
      return availableModes.contains(.hlg) ? .hlg : .sdr
    case .sdr:
      return .sdr
    }
  }

  private static func makeDisplayFormatDescription(
    dynamicRange: DisplayDynamicRange,
    width: Int32,
    height: Int32,
    doviProfile: Int64,
    doviLevel: Int64
  ) -> CMVideoFormatDescription? {
    if dynamicRange == .dolbyVision {
      return makeDolbyVisionFormatDescription(
        width: width, height: height,
        profile: UInt8(truncatingIfNeeded: doviProfile),
        level: UInt8(truncatingIfNeeded: doviLevel))
    }

    let extensions: [CFString: Any]
    switch dynamicRange {
    case .hdr10:
      extensions = [
        kCMFormatDescriptionExtension_ColorPrimaries: kCMFormatDescriptionColorPrimaries_ITU_R_2020,
        kCMFormatDescriptionExtension_TransferFunction:
          kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ,
        kCMFormatDescriptionExtension_YCbCrMatrix: kCMFormatDescriptionYCbCrMatrix_ITU_R_2020,
      ]
    case .hlg:
      extensions = [
        kCMFormatDescriptionExtension_ColorPrimaries: kCMFormatDescriptionColorPrimaries_ITU_R_2020,
        kCMFormatDescriptionExtension_TransferFunction: kCMFormatDescriptionTransferFunction_ITU_R_2100_HLG,
        kCMFormatDescriptionExtension_YCbCrMatrix: kCMFormatDescriptionYCbCrMatrix_ITU_R_2020,
      ]
    case .sdr:
      extensions = [
        kCMFormatDescriptionExtension_ColorPrimaries: kCMFormatDescriptionColorPrimaries_ITU_R_709_2,
        kCMFormatDescriptionExtension_TransferFunction: kCMFormatDescriptionTransferFunction_ITU_R_709_2,
        kCMFormatDescriptionExtension_YCbCrMatrix: kCMFormatDescriptionYCbCrMatrix_ITU_R_709_2,
      ]
    case .dolbyVision:
      return nil
    }

    var fd: CMVideoFormatDescription?
    let status = CMVideoFormatDescriptionCreate(
      allocator: kCFAllocatorDefault,
      codecType: kCMVideoCodecType_HEVC,
      width: width,
      height: height,
      extensions: extensions as CFDictionary,
      formatDescriptionOut: &fd
    )
    return status == noErr ? fd : nil
  }

  /// Build a synthetic 'dvh1' `CMVideoFormatDescription` from the Dolby
  /// Vision metadata mpv exposes. Used solely as a hint object for
  /// `AVDisplayCriteria(refreshRate:formatDescription:)` -- it is never
  /// enqueued onto the sample-buffer layer. mpv does not expose the
  /// compatibility id, so profile 8 (which always carries one) assumes
  /// bl_signal_compatibility_id = 1 (HDR10 base), by far the most common
  /// case; profile 5 has none, so 0.
  private static func makeDolbyVisionFormatDescription(
    width: Int32,
    height: Int32,
    profile: UInt8,
    level: UInt8
  ) -> CMVideoFormatDescription? {
    let compatibility: UInt8 = profile == 8 ? 1 : 0

    // 24-byte Dolby Vision configuration record (dvcC <= profile 7, dvvC >=
    // 8). Layout from ETSI TS 103 572 Section 7.1.1:
    //   [0]     dv_version_major (= 1)
    //   [1]     dv_version_minor (= 0)
    //   [2..3]  big-endian uint16: profile<<9 | level<<3 | rpu<<2 | el<<1 | bl
    //   [4]     compatibility<<4 | md_compression<<2
    //   [5..23] reserved zero
    var dovi = [UInt8](repeating: 0, count: 24)
    dovi[0] = 1
    dovi[1] = 0
    let flags: UInt16 =
      (UInt16(profile) & 0x7f) << 9
      | (UInt16(level) & 0x3f) << 3
      | (1 << 2)  // rpu_present_flag
      | (1 << 0)  // bl_present_flag
    dovi[2] = UInt8((flags >> 8) & 0xff)
    dovi[3] = UInt8(flags & 0xff)
    dovi[4] = (compatibility & 0x0f) << 4

    // CoreMedia carries codec-specific boxes under
    // kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms.
    let recordKey: CFString = (profile > 7 ? "dvvC" : "dvcC") as CFString
    let atoms: [CFString: Any] = [recordKey: Data(dovi) as CFData]

    let extensions: [CFString: Any] = [
      kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms: atoms as CFDictionary,
      kCMFormatDescriptionExtension_ColorPrimaries: kCMFormatDescriptionColorPrimaries_ITU_R_2020,
      kCMFormatDescriptionExtension_TransferFunction: kCMFormatDescriptionTransferFunction_SMPTE_ST_2084_PQ,
      kCMFormatDescriptionExtension_YCbCrMatrix: kCMFormatDescriptionYCbCrMatrix_ITU_R_2020,
    ]

    var fd: CMVideoFormatDescription?
    let status = CMVideoFormatDescriptionCreate(
      allocator: kCFAllocatorDefault,
      codecType: kCMVideoCodecType_DolbyVisionHEVC,  // 'dvh1'
      width: width,
      height: height,
      extensions: extensions as CFDictionary,
      formatDescriptionOut: &fd
    )
    return status == noErr ? fd : nil
  }
}

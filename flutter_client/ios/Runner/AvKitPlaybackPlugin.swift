import AVFoundation
import Flutter
import UIKit

// MARK: - Plugin

/// AVKit/AVPlayer-based playback plugin for iOS.
///
/// Mirrors the Android Media3PlaybackPlugin API surface so the Dart
/// AppleAvKitAdapter can drive either platform through the same
/// MethodChannel + EventChannel contract.
///
/// Channel names:
///   Method:  m3u_tv/apple_avkit
///   Events:  m3u_tv/apple_avkit/events
class AvKitPlaybackPlugin: NSObject, FlutterStreamHandler {
    static let methodChannelName = "m3u_tv/apple_avkit"
    static let eventChannelName  = "m3u_tv/apple_avkit/events"

    private let textureRegistry: FlutterTextureRegistry
    private var eventSink: FlutterEventSink?
    private var state: _PlayerState?

    init(textureRegistry: FlutterTextureRegistry) {
        self.textureRegistry = textureRegistry
        super.init()
    }

    // MARK: FlutterStreamHandler

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }

    // MARK: MethodChannel handler

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "probe":
            result(["backend": "avkit", "inAppOnly": true, "externalIntents": false])

        case "load":
            guard let args = call.arguments as? [String: Any],
                  let source = args["source"] as? [String: Any],
                  let uri = source["uri"] as? String else {
                result(FlutterError(code: "avkit-load-missing-uri", message: "Missing source uri", details: nil))
                return
            }
            releasePlayer()

            let headers = source["headers"] as? [String: String] ?? [:]
            let userAgent = source["userAgent"] as? String
            let startMs = (source["startPositionMs"] as? NSNumber)?.int64Value ?? 0

            guard let url = URL(string: uri) else {
                result(FlutterError(code: "avkit-load-bad-uri", message: "Invalid URI: \(uri)", details: nil))
                return
            }

            var asset: AVURLAsset
            if headers.isEmpty && userAgent == nil {
                asset = AVURLAsset(url: url)
            } else {
                var options: [String: Any] = [:]
                var httpHeaders: [String: String] = headers
                if let ua = userAgent {
                    httpHeaders["User-Agent"] = ua
                }
                if !httpHeaders.isEmpty {
                    options["AVURLAssetHTTPHeaderFieldsKey"] = httpHeaders
                }
                asset = AVURLAsset(url: url, options: options)
            }

            let item = AVPlayerItem(asset: asset)
            let player = AVPlayer(playerItem: item)

            // Pixel buffer output for FlutterTexture
            let pixelBufferAttributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            ]
            let videoOutput = AVPlayerItemVideoOutput(pixelBufferAttributes: pixelBufferAttributes)
            item.add(videoOutput)

            let avTexture = _AvKitTexture(videoOutput: videoOutput)
            let textureId = textureRegistry.register(avTexture)
            avTexture.onFrameAvailable = { [weak self] in
                self?.textureRegistry.textureFrameAvailable(textureId)
            }
            avTexture.startDisplayLink()

            let playerState = _PlayerState(
                player: player,
                item: item,
                texture: avTexture,
                textureId: textureId,
                uri: uri
            )
            state = playerState
            playerState.addObservers(plugin: self)

            if startMs > 0 {
                let startTime = CMTime(value: CMTimeValue(startMs), timescale: 1000)
                player.seek(to: startTime)
            }
            emit(type: "buffering", textureId: textureId, uri: uri)
            player.play()

            result(["ok": true, "textureId": textureId, "backend": "avkit"])

        case "play":
            state?.player.play()
            result(nil)

        case "pause":
            state?.player.pause()
            result(nil)

        case "seek":
            guard let args = call.arguments as? [String: Any],
                  let posMs = (args["positionMs"] as? NSNumber)?.int64Value else {
                result(FlutterError(code: "avkit-seek-missing", message: "Missing positionMs", details: nil))
                return
            }
            let time = CMTime(value: CMTimeValue(posMs), timescale: 1000)
            state?.player.seek(to: time)
            result(nil)

        case "stop":
            state?.player.pause()
            emit(type: "stopped")
            result(nil)

        case "setAudioTrack":
            let args = call.arguments as? [String: Any]
            selectTrack(characteristic: .audible, trackId: args?["trackId"] as? String)
            result(nil)

        case "setSubtitleTrack":
            let args = call.arguments as? [String: Any]
            selectTrack(characteristic: .legible, trackId: args?["trackId"] as? String)
            result(nil)

        case "dispose":
            releasePlayer()
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: Internal

    func releasePlayer() {
        guard let s = state else { return }
        s.player.pause()
        s.removeObservers()
        s.texture.stopDisplayLink()
        textureRegistry.unregisterTexture(s.textureId)
        state = nil
        emit(type: "disposed")
    }

    fileprivate func handleStatusChange(item: AVPlayerItem) {
        guard let s = state, s.item === item else { return }
        switch item.status {
        case .readyToPlay:
            let posMs = currentPositionMs()
            emit(
                type: s.player.rate > 0 ? "playing" : "ready",
                positionMs: posMs,
                audioTracks: playbackTracks(characteristic: .audible),
                subtitleTracks: playbackTracks(characteristic: .legible),
                selectedAudioTrackId: selectedTrackId(characteristic: .audible),
                selectedSubtitleTrackId: selectedTrackId(characteristic: .legible),
                includeSelectedAudioTrackId: true,
                includeSelectedSubtitleTrackId: true
            )
        case .failed:
            let msg = item.error?.localizedDescription ?? "AVPlayer item failed"
            emit(type: "error", code: "avkit-item-failed", message: msg, recoverable: true)
        default:
            break
        }
    }

    fileprivate func handleRateChange() {
        guard let s = state else { return }
        let posMs = currentPositionMs()
        emit(type: s.player.rate > 0 ? "playing" : "ready", positionMs: posMs)
    }

    fileprivate func handlePlaybackEnded() {
        emit(type: "end", positionMs: currentPositionMs())
    }

    private func selectTrack(characteristic: AVMediaCharacteristic, trackId: String?) {
        guard let item = state?.item,
              let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: characteristic) else {
            return
        }

        if let trackId = trackId, let index = parseTrackIndex(trackId), index < group.options.count {
            item.select(group.options[index], in: group)
        } else {
            item.select(nil, in: group)
        }

        emit(
            type: state?.player.rate ?? 0 > 0 ? "playing" : "ready",
            positionMs: currentPositionMs(),
            audioTracks: playbackTracks(characteristic: .audible),
            subtitleTracks: playbackTracks(characteristic: .legible),
            selectedAudioTrackId: selectedTrackId(characteristic: .audible),
            selectedSubtitleTrackId: selectedTrackId(characteristic: .legible),
            includeSelectedAudioTrackId: true,
            includeSelectedSubtitleTrackId: true
        )
    }

    private func playbackTracks(characteristic: AVMediaCharacteristic) -> [[String: Any?]] {
        guard let item = state?.item,
              let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: characteristic) else {
            return []
        }
        let prefix = characteristic == .audible ? "audio" : "subtitle"
        return group.options.enumerated().map { index, option in
            [
                "id": "\(prefix):\(index)",
                "label": option.displayName,
                "language": option.locale?.identifier,
            ]
        }
    }

    private func selectedTrackId(characteristic: AVMediaCharacteristic) -> String? {
        guard let item = state?.item,
              let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: characteristic),
              let selected = item.selectedMediaOption(in: group),
              let index = group.options.firstIndex(of: selected) else {
            return nil
        }
        let prefix = characteristic == .audible ? "audio" : "subtitle"
        return "\(prefix):\(index)"
    }

    private func parseTrackIndex(_ trackId: String) -> Int? {
        let parts = trackId.split(separator: ":")
        guard parts.count == 2 else { return nil }
        return Int(parts[1])
    }

    private func currentPositionMs() -> Int64 {
        guard let player = state?.player else { return 0 }
        let seconds = CMTimeGetSeconds(player.currentTime())
        return seconds.isFinite ? Int64(seconds * 1000) : 0
    }

    private func emit(
        type: String,
        textureId: Int64? = nil,
        uri: String? = nil,
        positionMs: Int64? = nil,
        audioTracks: [[String: Any?]]? = nil,
        subtitleTracks: [[String: Any?]]? = nil,
        selectedAudioTrackId: String? = nil,
        selectedSubtitleTrackId: String? = nil,
        includeSelectedAudioTrackId: Bool = false,
        includeSelectedSubtitleTrackId: Bool = false,
        code: String? = nil,
        message: String? = nil,
        recoverable: Bool = false
    ) {
        var event: [String: Any] = ["type": type, "backend": "appleAvKit"]
        if let id = textureId  { event["textureId"]   = id       }
        if let u  = uri         { event["uri"]         = u        }
        if let p  = positionMs  { event["positionMs"]  = p        }
        if let a  = audioTracks { event["audioTracks"] = a        }
        if let st = subtitleTracks { event["subtitleTracks"] = st }
        if includeSelectedAudioTrackId { event["selectedAudioTrackId"] = selectedAudioTrackId }
        if includeSelectedSubtitleTrackId { event["selectedSubtitleTrackId"] = selectedSubtitleTrackId }
        if let c  = code        { event["code"]        = c        }
        if let m  = message     { event["message"]     = m        }
        if recoverable          { event["recoverable"] = true      }
        eventSink?(event)
    }
}

// MARK: - Player state

private class _PlayerState {
    let player: AVPlayer
    let item: AVPlayerItem
    let texture: _AvKitTexture
    let textureId: Int64
    let uri: String

    private var statusObservation: NSKeyValueObservation?
    private var rateObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?

    init(player: AVPlayer, item: AVPlayerItem, texture: _AvKitTexture, textureId: Int64, uri: String) {
        self.player    = player
        self.item      = item
        self.texture   = texture
        self.textureId = textureId
        self.uri       = uri
    }

    func addObservers(plugin: AvKitPlaybackPlugin) {
        statusObservation = item.observe(\.status, options: [.new]) { [weak plugin] item, _ in
            plugin?.handleStatusChange(item: item)
        }
        rateObservation = player.observe(\.rate, options: [.new]) { [weak plugin] _, _ in
            plugin?.handleRateChange()
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak plugin] _ in
            plugin?.handlePlaybackEnded()
        }
    }

    func removeObservers() {
        statusObservation?.invalidate()
        rateObservation?.invalidate()
        if let obs = endObserver {
            NotificationCenter.default.removeObserver(obs)
        }
    }
}

// MARK: - FlutterTexture backed by AVPlayerItemVideoOutput

private class _AvKitTexture: NSObject, FlutterTexture {
    private let videoOutput: AVPlayerItemVideoOutput
    private var displayLink: CADisplayLink?
    var onFrameAvailable: (() -> Void)?

    init(videoOutput: AVPlayerItemVideoOutput) {
        self.videoOutput = videoOutput
    }

    func copyPixelBuffer() -> Unmanaged<CVPixelBuffer>? {
        let time = videoOutput.itemTime(forHostTime: CACurrentMediaTime())
        guard videoOutput.hasNewPixelBuffer(forItemTime: time),
              let pixelBuffer = videoOutput.copyPixelBuffer(forItemTime: time, itemTimeForDisplay: nil) else {
            return nil
        }
        return Unmanaged.passRetained(pixelBuffer)
    }

    func startDisplayLink() {
        let link = CADisplayLink(target: self, selector: #selector(displayLinkFired))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func displayLinkFired() {
        let time = videoOutput.itemTime(forHostTime: CACurrentMediaTime())
        if videoOutput.hasNewPixelBuffer(forItemTime: time) {
            onFrameAvailable?()
        }
    }
}

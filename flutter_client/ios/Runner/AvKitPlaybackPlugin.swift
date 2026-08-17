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
/// Every call after "probe" carries a Dart-assigned `playerId` string, and
/// player state is keyed by it (`states[playerId]`) rather than held in a
/// single field -- this lets Multiview run several concurrent AVPlayers over
/// the one channel pair without any AppDelegate/registration changes.
/// Mirrors tvos/Runner/AvKitPlaybackPlugin.swift.
///
/// Channel names:
///   Method:  m3u_tv/apple_avkit
///   Events:  m3u_tv/apple_avkit/events
class AvKitPlaybackPlugin: NSObject, FlutterStreamHandler {
    static let methodChannelName = "m3u_tv/apple_avkit"
    static let eventChannelName  = "m3u_tv/apple_avkit/events"

    private let textureRegistry: FlutterTextureRegistry
    private var eventSink: FlutterEventSink?
    private var states: [String: _PlayerState] = [:]

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
        let args = call.arguments as? [String: Any]
        let playerId = (args?["playerId"] as? String) ?? "default"

        switch call.method {
        case "probe":
            result(["backend": "avkit", "inAppOnly": true, "externalIntents": false])

        case "load":
            guard let args = args,
                  let source = args["source"] as? [String: Any],
                  let uri = source["uri"] as? String else {
                result(FlutterError(code: "avkit-load-missing-uri", message: "Missing source uri", details: nil))
                return
            }
            releasePlayer(playerId: playerId)

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

            // Pixel buffer output for FlutterTexture. Metal compatibility must be
            // requested explicitly -- without it CoreVideo hands back buffers
            // FlutterDarwinExternalTextureMetal can't wrap, failing every frame
            // with CVReturn -6660 (kCVReturnPixelBufferNotMetalCompatible).
            let pixelBufferAttributes: [String: Any] = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferMetalCompatibilityKey as String: true,
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
                playerId: playerId,
                player: player,
                item: item,
                texture: avTexture,
                textureId: textureId,
                uri: uri
            )
            states[playerId] = playerState
            playerState.addObservers(plugin: self)

            if startMs > 0 {
                let startTime = CMTime(value: CMTimeValue(startMs), timescale: 1000)
                player.seek(to: startTime)
            }
            emit(playerId: playerId, type: "buffering", textureId: textureId, uri: uri)
            player.play()

            result(["ok": true, "textureId": textureId, "backend": "avkit"])

        case "play":
            states[playerId]?.player.play()
            result(nil)

        case "pause":
            states[playerId]?.player.pause()
            result(nil)

        case "seek":
            guard let posMs = (args?["positionMs"] as? NSNumber)?.int64Value else {
                result(FlutterError(code: "avkit-seek-missing", message: "Missing positionMs", details: nil))
                return
            }
            let time = CMTime(value: CMTimeValue(posMs), timescale: 1000)
            states[playerId]?.player.seek(to: time)
            result(nil)

        case "stop":
            states[playerId]?.player.pause()
            emit(playerId: playerId, type: "stopped")
            result(nil)

        case "setVolume":
            let volume = (args?["volume"] as? NSNumber)?.floatValue ?? 1
            states[playerId]?.player.volume = volume
            result(nil)

        case "setAudioTrack":
            selectTrack(playerId: playerId, characteristic: .audible, trackId: args?["trackId"] as? String)
            result(nil)

        case "setSubtitleTrack":
            selectTrack(playerId: playerId, characteristic: .legible, trackId: args?["trackId"] as? String)
            result(nil)

        case "dispose":
            releasePlayer(playerId: playerId)
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: Internal

    func releasePlayer(playerId: String) {
        guard let s = states.removeValue(forKey: playerId) else { return }
        s.player.pause()
        s.removeObservers()
        s.texture.stopDisplayLink()
        textureRegistry.unregisterTexture(s.textureId)
        emit(playerId: playerId, type: "disposed")
    }

    fileprivate func handleStatusChange(playerId: String, item: AVPlayerItem) {
        guard let s = states[playerId], s.item === item else { return }
        switch item.status {
        case .readyToPlay:
            let posMs = currentPositionMs(playerId: playerId)
            emit(
                playerId: playerId,
                type: s.player.rate > 0 ? "playing" : "ready",
                positionMs: posMs,
                videoAspectRatio: videoAspectRatio(for: item),
                audioTracks: playbackTracks(playerId: playerId, characteristic: .audible),
                subtitleTracks: playbackTracks(playerId: playerId, characteristic: .legible),
                selectedAudioTrackId: selectedTrackId(playerId: playerId, characteristic: .audible),
                selectedSubtitleTrackId: selectedTrackId(playerId: playerId, characteristic: .legible),
                includeSelectedAudioTrackId: true,
                includeSelectedSubtitleTrackId: true
            )
        case .failed:
            let msg = item.error?.localizedDescription ?? "AVPlayer item failed"
            emit(playerId: playerId, type: "error", code: "avkit-item-failed", message: msg, recoverable: true)
        default:
            break
        }
    }

    fileprivate func handleRateChange(playerId: String) {
        guard let s = states[playerId] else { return }
        let posMs = currentPositionMs(playerId: playerId)
        emit(playerId: playerId, type: s.player.rate > 0 ? "playing" : "ready", positionMs: posMs)
    }

    fileprivate func handlePlaybackEnded(playerId: String) {
        emit(playerId: playerId, type: "end", positionMs: currentPositionMs(playerId: playerId))
    }

    private func selectTrack(playerId: String, characteristic: AVMediaCharacteristic, trackId: String?) {
        guard let item = states[playerId]?.item,
              let group = item.asset.mediaSelectionGroup(forMediaCharacteristic: characteristic) else {
            return
        }

        if let trackId = trackId, let index = parseTrackIndex(trackId), index < group.options.count {
            item.select(group.options[index], in: group)
        } else {
            item.select(nil, in: group)
        }

        emit(
            playerId: playerId,
            type: (states[playerId]?.player.rate ?? 0) > 0 ? "playing" : "ready",
            positionMs: currentPositionMs(playerId: playerId),
            audioTracks: playbackTracks(playerId: playerId, characteristic: .audible),
            subtitleTracks: playbackTracks(playerId: playerId, characteristic: .legible),
            selectedAudioTrackId: selectedTrackId(playerId: playerId, characteristic: .audible),
            selectedSubtitleTrackId: selectedTrackId(playerId: playerId, characteristic: .legible),
            includeSelectedAudioTrackId: true,
            includeSelectedSubtitleTrackId: true
        )
    }

    private func playbackTracks(playerId: String, characteristic: AVMediaCharacteristic) -> [[String: Any?]] {
        guard let item = states[playerId]?.item,
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

    private func selectedTrackId(playerId: String, characteristic: AVMediaCharacteristic) -> String? {
        guard let item = states[playerId]?.item,
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

    private func currentPositionMs(playerId: String) -> Int64 {
        guard let player = states[playerId]?.player else { return 0 }
        let seconds = CMTimeGetSeconds(player.currentTime())
        return seconds.isFinite ? Int64(seconds * 1000) : 0
    }

    private func videoAspectRatio(for item: AVPlayerItem) -> Double? {
        let size = item.presentationSize
        guard size.width > 0, size.height > 0 else { return nil }
        return Double(size.width / size.height)
    }

    private func emit(
        playerId: String,
        type: String,
        textureId: Int64? = nil,
        uri: String? = nil,
        positionMs: Int64? = nil,
        videoAspectRatio: Double? = nil,
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
        var event: [String: Any] = ["type": type, "backend": "appleAvKit", "playerId": playerId]
        if let id = textureId  { event["textureId"]   = id       }
        if let u  = uri         { event["uri"]         = u        }
        if let p  = positionMs  { event["positionMs"]  = p        }
        if let ar = videoAspectRatio { event["videoAspectRatio"] = ar }
        if let a  = audioTracks { event["audioTracks"] = a        }
        if let st = subtitleTracks { event["subtitleTracks"] = st }
        if includeSelectedAudioTrackId { event["selectedAudioTrackId"] = selectedAudioTrackId ?? NSNull() }
        if includeSelectedSubtitleTrackId { event["selectedSubtitleTrackId"] = selectedSubtitleTrackId ?? NSNull() }
        if let c  = code        { event["code"]        = c        }
        if let m  = message     { event["message"]     = m        }
        if recoverable          { event["recoverable"] = true      }
        eventSink?(event)
    }
}

// MARK: - Player state

private class _PlayerState {
    let playerId: String
    let player: AVPlayer
    let item: AVPlayerItem
    let texture: _AvKitTexture
    let textureId: Int64
    let uri: String

    private var statusObservation: NSKeyValueObservation?
    private var rateObservation: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?

    init(playerId: String, player: AVPlayer, item: AVPlayerItem, texture: _AvKitTexture, textureId: Int64, uri: String) {
        self.playerId  = playerId
        self.player    = player
        self.item      = item
        self.texture   = texture
        self.textureId = textureId
        self.uri       = uri
    }

    func addObservers(plugin: AvKitPlaybackPlugin) {
        let id = playerId
        statusObservation = item.observe(\.status, options: [.new]) { [weak plugin] item, _ in
            plugin?.handleStatusChange(playerId: id, item: item)
        }
        rateObservation = player.observe(\.rate, options: [.new]) { [weak plugin] _, _ in
            plugin?.handleRateChange(playerId: id)
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak plugin] _ in
            plugin?.handlePlaybackEnded(playerId: id)
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

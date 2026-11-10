import Flutter
import MediaPlayer
import UIKit

/// Publishes the open player's title, artwork and progress to the system's
/// Now Playing surfaces (lock screen, Control Center, and later CarPlay), and
/// forwards their transport buttons back to Dart.
///
/// Channel: `m3u_tv/now_playing`
///   Dart -> native: `update` (see `update(_:)`), `clear`
///   Native -> Dart: `command` `{name, positionMs?}`
final class NowPlayingPlugin {
  static let channelName = "m3u_tv/now_playing"

  private static let skipIntervalSeconds: NSNumber = 10

  private let channel: FlutterMethodChannel
  private var commandsRegistered = false
  private var nowPlayingInfo: [String: Any] = [:]
  private var artworkUrl: String?
  private var artwork: MPMediaItemArtwork?
  private var artworkTask: URLSessionDataTask?

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "update":
      update(call.arguments as? [String: Any] ?? [:])
      result(nil)
    case "clear":
      clear()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func update(_ args: [String: Any]) {
    let isLive = args["isLive"] as? Bool ?? false
    let isPlaying = args["isPlaying"] as? Bool ?? false

    var info: [String: Any] = [
      MPMediaItemPropertyTitle: args["title"] as? String ?? "",
      MPNowPlayingInfoPropertyIsLiveStream: isLive,
      MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.video.rawValue,
      MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
      MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
    ]
    if let subtitle = args["subtitle"] as? String, !subtitle.isEmpty {
      info[MPMediaItemPropertyArtist] = subtitle
    }
    if !isLive, let durationMs = args["durationMs"] as? Int, durationMs > 0 {
      info[MPMediaItemPropertyPlaybackDuration] = Double(durationMs) / 1000
      info[MPNowPlayingInfoPropertyElapsedPlaybackTime] =
        Double(args["positionMs"] as? Int ?? 0) / 1000
    }

    let requestedArtwork = args["artworkUrl"] as? String
    if requestedArtwork != artworkUrl {
      artworkUrl = requestedArtwork
      artwork = nil
      artworkTask?.cancel()
      artworkTask = nil
      loadArtwork(requestedArtwork)
    }
    if let artwork {
      info[MPMediaItemPropertyArtwork] = artwork
    }

    nowPlayingInfo = info
    MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    configureCommands(
      canSeek: args["canSeek"] as? Bool ?? false,
      canChangeChannel: args["canChangeChannel"] as? Bool ?? false
    )
  }

  private func clear() {
    artworkTask?.cancel()
    artworkTask = nil
    artworkUrl = nil
    artwork = nil
    nowPlayingInfo = [:]
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
    guard commandsRegistered else { return }
    commandsRegistered = false
    for command in Self.allCommands() {
      command.removeTarget(nil)
      command.isEnabled = false
    }
  }

  private func loadArtwork(_ urlString: String?) {
    guard let urlString, let url = URL(string: urlString) else { return }
    let task = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
      guard let data, let image = UIImage(data: data) else { return }
      DispatchQueue.main.async {
        guard let self, self.artworkUrl == urlString else { return }
        let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        self.artwork = artwork
        guard !self.nowPlayingInfo.isEmpty else { return }
        self.nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
        MPNowPlayingInfoCenter.default().nowPlayingInfo = self.nowPlayingInfo
      }
    }
    artworkTask = task
    task.resume()
  }

  private static func allCommands() -> [MPRemoteCommand] {
    let center = MPRemoteCommandCenter.shared()
    return [
      center.playCommand,
      center.pauseCommand,
      center.togglePlayPauseCommand,
      center.skipForwardCommand,
      center.skipBackwardCommand,
      center.changePlaybackPositionCommand,
      center.nextTrackCommand,
      center.previousTrackCommand,
    ]
  }

  private func configureCommands(canSeek: Bool, canChangeChannel: Bool) {
    let center = MPRemoteCommandCenter.shared()
    if !commandsRegistered {
      commandsRegistered = true
      center.skipForwardCommand.preferredIntervals = [Self.skipIntervalSeconds]
      center.skipBackwardCommand.preferredIntervals = [Self.skipIntervalSeconds]
      addTarget(center.playCommand, name: "play")
      addTarget(center.pauseCommand, name: "pause")
      addTarget(center.togglePlayPauseCommand, name: "toggle")
      addTarget(center.skipForwardCommand, name: "skipForward")
      addTarget(center.skipBackwardCommand, name: "skipBackward")
      addTarget(center.nextTrackCommand, name: "next")
      addTarget(center.previousTrackCommand, name: "previous")
      center.changePlaybackPositionCommand.addTarget { [weak self] event in
        guard let self,
              let event = event as? MPChangePlaybackPositionCommandEvent else {
          return .commandFailed
        }
        self.send("seek", positionMs: Int(event.positionTime * 1000))
        return .success
      }
    }
    center.playCommand.isEnabled = true
    center.pauseCommand.isEnabled = true
    center.togglePlayPauseCommand.isEnabled = true
    center.skipForwardCommand.isEnabled = canSeek
    center.skipBackwardCommand.isEnabled = canSeek
    center.changePlaybackPositionCommand.isEnabled = canSeek
    center.nextTrackCommand.isEnabled = canChangeChannel
    center.previousTrackCommand.isEnabled = canChangeChannel
  }

  private func addTarget(_ command: MPRemoteCommand, name: String) {
    command.addTarget { [weak self] _ in
      guard let self else { return .commandFailed }
      self.send(name)
      return .success
    }
  }

  private func send(_ name: String, positionMs: Int? = nil) {
    var arguments: [String: Any] = ["name": name]
    if let positionMs { arguments["positionMs"] = positionMs }
    channel.invokeMethod("command", arguments: arguments)
  }
}

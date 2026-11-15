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
  private var artworkIsLogo = false
  private var artwork: MPMediaItemArtwork?
  private var artworkTask: URLSessionDataTask?
  private var sceneObservers: [NSObjectProtocol] = []

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(name: Self.channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    // The media type follows whether CarPlay is connected (see mediaType),
    // so a car connecting or leaving mid-stream re-publishes it.
    let center = NotificationCenter.default
    sceneObservers = [UIScene.willConnectNotification, UIScene.didDisconnectNotification].map { name in
      center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
        guard (notification.object as? UIScene)?.session.role == .carTemplateApplication else { return }
        self?.republishMediaType()
      }
    }
  }

  /// CarPlay shows audio only, and showed a video item as "Not Playing"
  /// even while its sound came through the car. The lock screen keeps the
  /// video type when no car is connected.
  private static var mediaType: MPNowPlayingInfoMediaType {
    let carConnected = UIApplication.shared.connectedScenes.contains {
      $0.session.role == .carTemplateApplication
    }
    return carConnected ? .audio : .video
  }

  private func republishMediaType() {
    guard !nowPlayingInfo.isEmpty else { return }
    nowPlayingInfo[MPNowPlayingInfoPropertyMediaType] = Self.mediaType.rawValue
    MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
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
      MPNowPlayingInfoPropertyMediaType: Self.mediaType.rawValue,
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
    let requestedIsLogo = args["artworkIsLogo"] as? Bool ?? false
    if requestedArtwork != artworkUrl || requestedIsLogo != artworkIsLogo {
      artworkUrl = requestedArtwork
      artworkIsLogo = requestedIsLogo
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
    let isLogo = artworkIsLogo
    let task = URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
      guard let data, let image = UIImage(data: data) else { return }
      DispatchQueue.main.async {
        guard let self, self.artworkUrl == urlString else { return }
        let artwork = Self.artwork(for: image, isLogo: isLogo)
        self.artwork = artwork
        guard !self.nowPlayingInfo.isEmpty else { return }
        self.nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
        MPNowPlayingInfoCenter.default().nowPlayingInfo = self.nowPlayingInfo
      }
    }
    artworkTask = task
    task.resume()
  }

  // The system asks for artwork at its own (square) sizes and crops whatever
  // it gets back, which cut a wide channel logo down to a sliver. Render to
  // the requested size instead: a logo is fitted with a margin around it, a
  // poster fills the frame. Logos sit on a dark tile: most are white on a
  // transparent background, made for a dark UI, and vanished on the light
  // notification background.
  private static let artworkBounds = CGSize(width: 600, height: 600)
  private static let logoInset: CGFloat = 0.12
  private static let logoBackground = UIColor(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255, alpha: 1)

  private static func artwork(for image: UIImage, isLogo: Bool) -> MPMediaItemArtwork {
    MPMediaItemArtwork(boundsSize: artworkBounds) { size in
      render(image, size: size, isLogo: isLogo)
    }
  }

  private static func render(_ image: UIImage, size: CGSize, isLogo: Bool) -> UIImage {
    guard size.width > 0, size.height > 0,
          image.size.width > 0, image.size.height > 0 else { return image }
    let frame = isLogo
      ? CGRect(origin: .zero, size: size).insetBy(
          dx: size.width * logoInset,
          dy: size.height * logoInset
        )
      : CGRect(origin: .zero, size: size)
    let widthScale = frame.width / image.size.width
    let heightScale = frame.height / image.size.height
    let scale = isLogo ? min(widthScale, heightScale) : max(widthScale, heightScale)
    let drawSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
    let drawRect = CGRect(
      x: frame.midX - drawSize.width / 2,
      y: frame.midY - drawSize.height / 2,
      width: drawSize.width,
      height: drawSize.height
    )
    let format = UIGraphicsImageRendererFormat.default()
    format.opaque = isLogo
    return UIGraphicsImageRenderer(size: size, format: format).image { context in
      if isLogo {
        logoBackground.setFill()
        context.fill(CGRect(origin: .zero, size: size))
      }
      image.draw(in: drawRect)
    }
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

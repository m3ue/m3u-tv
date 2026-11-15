// Picture-in-picture for the mpv player on iPhone and iPad.
//
// Modeled on Plezy's ios/Runner/MpvPlayer/MpvPipController.swift
// (github.com/edde746/plezy, GPL-3.0), ported under this app's own GPL-3.0
// license and cut down to what this app uses: automatic PiP when the viewer
// leaves the app from the full-screen player, like Android. There is no
// manual start, so none of Plezy's start retry and timeout handling.
//
// mpv's vo=avfoundation already draws into an AVSampleBufferDisplayLayer,
// which AVKit can show in PiP directly (iOS 15's ContentSource API), so
// nothing about rendering changes while PiP is up. The PiP window's buttons
// are forwarded (`onSetPlaying`, `onSkip`) rather than acted on here, so
// they go through the same Dart logic as the lock screen's.

import AVFoundation
import AVKit

final class MpvPipController: NSObject {
  /// PiP's open state: true as it starts, false once it's gone. `restored`
  /// is whether the viewer brought the app back from it (false when they
  /// closed it, or it failed to start).
  var onActiveChanged: ((_ active: Bool, _ restored: Bool) -> Void)?
  var onSetPlaying: ((Bool) -> Void)?
  var onSkip: ((Double) -> Void)?
  /// Read on main by AVKit while PiP is up.
  var isPlaying: () -> Bool = { false }
  /// Seconds; 0 for live, which shows PiP's live timeline.
  var duration: () -> Double = { 0 }
  var position: () -> Double = { 0 }

  private var controller: AVPictureInPictureController?
  private weak var layer: AVSampleBufferDisplayLayer?
  private var restoreRequested = false
  private(set) var isActive = false

  // A skip from the PiP window, until mpv has landed on the new position.
  // AVKit expects its completion only then (it re-reads the timeline right
  // after), and answered an early one by pausing playback.
  private var pendingSkipCompletion: (() -> Void)?
  private var pendingSkipGeneration = 0
  private static let skipTimeout: TimeInterval = 2.0
  private static let skipSettleDelay: TimeInterval = 0.1

  static let liveTimeRange = CMTimeRange(start: .negativeInfinity, duration: .positiveInfinity)

  static var isSupported: Bool { AVPictureInPictureController.isPictureInPictureSupported() }

  init(layer: AVSampleBufferDisplayLayer) {
    self.layer = layer
    super.init()
    let source = AVPictureInPictureController.ContentSource(
      sampleBufferDisplayLayer: layer,
      playbackDelegate: self
    )
    let controller = AVPictureInPictureController(contentSource: source)
    controller.delegate = self
    controller.canStartPictureInPictureAutomaticallyFromInline = false
    self.controller = controller
  }

  /// Whether leaving the app moves this player into PiP. Only the full-screen
  /// player turns it on.
  func setAutomaticStart(_ enabled: Bool) {
    controller?.canStartPictureInPictureAutomaticallyFromInline = enabled
  }

  /// Live has no timeline to skip along, so PiP hides its skip buttons.
  func setLive(_ live: Bool) {
    controller?.requiresLinearPlayback = live
  }

  /// Makes PiP read the play state and timeline again.
  func invalidatePlaybackState() {
    controller?.invalidatePlaybackState()
  }

  /// mpv finished a seek (its playback restarted). Main thread.
  func seekFinished() {
    guard pendingSkipCompletion != nil else { return }
    let generation = pendingSkipGeneration
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.skipSettleDelay) { [weak self] in
      self?.completeSkip(generation: generation)
    }
  }

  private func completeSkip(generation: Int) {
    guard generation == pendingSkipGeneration, let completion = pendingSkipCompletion else { return }
    pendingSkipCompletion = nil
    controller?.invalidatePlaybackState()
    completion()
  }

  func teardown() {
    pendingSkipCompletion?()
    pendingSkipCompletion = nil
    controller?.canStartPictureInPictureAutomaticallyFromInline = false
    controller?.stopPictureInPicture()
    controller?.delegate = nil
    controller = nil
    onActiveChanged = nil
    onSetPlaying = nil
    onSkip = nil
  }

  private func finish(restored: Bool) {
    guard isActive else { return }
    isActive = false
    restoreRequested = false
    onActiveChanged?(false, restored)
  }
}

extension MpvPipController: AVPictureInPictureControllerDelegate {
  func pictureInPictureControllerWillStartPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    isActive = true
    restoreRequested = false
    onActiveChanged?(true, false)
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    failedToStartPictureInPictureWithError error: Error
  ) {
    NSLog("[MpvPipController] PiP failed to start: %@", error.localizedDescription)
    finish(restored: false)
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    restoreUserInterfaceForPictureInPictureStopWithCompletionHandler completionHandler:
      @escaping (Bool) -> Void
  ) {
    restoreRequested = true
    completionHandler(true)
  }

  func pictureInPictureControllerDidStopPictureInPicture(
    _ pictureInPictureController: AVPictureInPictureController
  ) {
    finish(restored: restoreRequested)
  }
}

extension MpvPipController: AVPictureInPictureSampleBufferPlaybackDelegate {
  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    setPlaying playing: Bool
  ) {
    // AVKit can ask to pause mid-skip, while the timeline it shows stands
    // still; that isn't the viewer's pause.
    if !playing && pendingSkipCompletion != nil { return }
    onSetPlaying?(playing)
  }

  /// PiP shows the layer timebase's time minus the range start as elapsed
  /// time. mpv's host presentation runs that timebase on its own clock, not
  /// the playback position, so the range starts at (timebase now - position).
  /// Re-sent after every seek and play/pause (see MpvPlayerCore).
  func pictureInPictureControllerTimeRangeForPlayback(
    _ pictureInPictureController: AVPictureInPictureController
  ) -> CMTimeRange {
    let duration = duration()
    guard duration > 0, let timebase = layer?.controlTimebase else { return Self.liveTimeRange }
    let position = min(max(position(), 0), duration)
    let start = CMTimeSubtract(
      CMTimebaseGetTime(timebase),
      CMTime(seconds: position, preferredTimescale: 1_000_000_000)
    )
    return CMTimeRange(start: start, duration: CMTime(seconds: duration, preferredTimescale: 1_000_000_000))
  }

  func pictureInPictureControllerIsPlaybackPaused(
    _ pictureInPictureController: AVPictureInPictureController
  ) -> Bool {
    !isPlaying()
  }

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    didTransitionToRenderSize newRenderSize: CMVideoDimensions
  ) {}

  func pictureInPictureController(
    _ pictureInPictureController: AVPictureInPictureController,
    skipByInterval skipInterval: CMTime,
    completion completionHandler: @escaping () -> Void
  ) {
    // A skip pressed again before the last one landed answers that one now.
    pendingSkipCompletion?()
    pendingSkipGeneration &+= 1
    let generation = pendingSkipGeneration
    pendingSkipCompletion = completionHandler
    onSkip?(CMTimeGetSeconds(skipInterval))
    DispatchQueue.main.asyncAfter(deadline: .now() + Self.skipTimeout) { [weak self] in
      self?.completeSkip(generation: generation)
    }
  }
}

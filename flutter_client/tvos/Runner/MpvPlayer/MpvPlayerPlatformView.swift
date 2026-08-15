// UiKitView factory backing `m3u_tv/apple_mpv_view` on tvOS. Creates a
// UIView backed by an AVSampleBufferDisplayLayer, which mpv's
// vo=avfoundation driver draws into directly (see MpvPlayerCore.attach), and
// registers the resulting core with MpvPlayerPlugin so the method/event
// channel can find it by `viewId`.

import AVFoundation
import Flutter
import UIKit

final class MpvPlayerUIView: UIView {
  override class var layerClass: AnyClass { AVSampleBufferDisplayLayer.self }

  var displayLayer: AVSampleBufferDisplayLayer {
    layer as! AVSampleBufferDisplayLayer
  }
}

final class MpvPlayerPlatformView: NSObject, FlutterPlatformView {
  private let uiView: MpvPlayerUIView

  init(viewId: Int, frame: CGRect, plugin: MpvPlayerPlugin) {
    self.uiView = MpvPlayerUIView(frame: frame)
    self.uiView.backgroundColor = .black
    self.uiView.displayLayer.videoGravity = .resizeAspect
    super.init()
    plugin.attachCore(viewId: viewId, to: uiView.displayLayer)
  }

  func view() -> UIView { uiView }
}

final class MpvPlayerPlatformViewFactory: NSObject, FlutterPlatformViewFactory {
  private let plugin: MpvPlayerPlugin

  init(plugin: MpvPlayerPlugin) {
    self.plugin = plugin
    super.init()
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    let params = args as? [String: Any]
    let mpvViewId = (params?["viewId"] as? NSNumber)?.intValue ?? Int(viewId)
    return MpvPlayerPlatformView(viewId: mpvViewId, frame: frame, plugin: plugin)
  }
}

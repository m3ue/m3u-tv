// AppKitView factory backing `m3u_tv/mac_mpv_view`. Creates the NSView mpv
// draws directly into (via the `wid` option in MpvPlayerCore.attach), and
// registers the resulting core with MpvPlayerPlugin so the method/event
// channel can find it by `viewId`.

import FlutterMacOS
import AppKit

final class MpvPlayerNSView: NSView {
  override var isFlipped: Bool { true }
}

final class MpvPlayerPlatformView: NSObject, FlutterPlatformView {
  private let nsView: MpvPlayerNSView

  init(viewId: Int, frame: CGRect, plugin: MpvPlayerPlugin) {
    self.nsView = MpvPlayerNSView(frame: frame)
    self.nsView.wantsLayer = true
    super.init()
    plugin.attachCore(viewId: viewId, to: nsView)
  }

  func view() -> NSView { nsView }
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

  func create(withViewIdentifier viewId: Int64, arguments args: Any?) -> NSView {
    let params = args as? [String: Any]
    let mpvViewId = (params?["viewId"] as? NSNumber)?.intValue ?? Int(viewId)
    let platformView = MpvPlayerPlatformView(
      viewId: mpvViewId,
      frame: .zero,
      plugin: plugin
    )
    return platformView.view()
  }
}

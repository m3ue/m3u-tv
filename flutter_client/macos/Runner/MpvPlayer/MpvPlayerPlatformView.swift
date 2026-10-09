// AppKitView factory backing `m3u_tv/mac_mpv_view`. Creates the NSView mpv
// draws directly into (via the `wid` option in MpvPlayerCore.attach), and
// registers the resulting core with MpvPlayerPlugin so the method/event
// channel can find it by `viewId`.

import FlutterMacOS
import AppKit

final class MpvPlayerNSView: NSView {
  override var isFlipped: Bool { true }

  /// Fired when the view joins or leaves a window, or its backing scale
  /// changes (window dragged to a display with a different scale). The core
  /// re-syncs the metal layer and re-binds its window observers here, since
  /// the view has no window yet when it is created with `frame: .zero`.
  var onWindowOrScaleChange: (() -> Void)?

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    onWindowOrScaleChange?()
  }

  override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    onWindowOrScaleChange?()
  }
}

final class MpvPlayerPlatformViewFactory: NSObject, FlutterPlatformViewFactory {
  private let plugin: MpvPlayerPlugin

  init(plugin: MpvPlayerPlugin) {
    self.plugin = plugin
    super.init()
  }

  func createArgsCodec() -> (FlutterMessageCodec & NSObjectProtocol)? {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(withViewIdentifier viewId: Int64, arguments args: Any?) -> NSView {
    let params = args as? [String: Any]
    let mpvViewId = (params?["viewId"] as? NSNumber)?.intValue ?? Int(viewId)
    let nsView = MpvPlayerNSView(frame: .zero)
    nsView.wantsLayer = true
    plugin.attachCore(viewId: mpvViewId, to: nsView)
    return nsView
  }
}

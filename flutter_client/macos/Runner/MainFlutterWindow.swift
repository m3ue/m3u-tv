import Cocoa
import FlutterMacOS

private final class DesktopLibmpvBackend {
  static func register(with controller: FlutterViewController, window: NSWindow) {
    let channel = FlutterMethodChannel(
      name: "m3u_tv/desktop_libmpv",
      binaryMessenger: controller.engine.binaryMessenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "probe":
        result(probe(window: window))
      case "load":
        let libmpv = Bundle.main.privateFrameworksURL?
          .appendingPathComponent("libmpv.2.dylib")
        let available = libmpv.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        result([
          "ok": available,
          "handle": 1,
          "error": available ? "" : "libmpv.2.dylib or MPVKit framework not bundled",
        ])
      default:
        result(nil)
      }
    }
  }

  private static func probe(window: NSWindow) -> [String: Any] {
    window.contentView?.wantsLayer = true
    let available = Bundle.main.privateFrameworksURL.map { frameworksURL in
      FileManager.default.fileExists(atPath: frameworksURL.appendingPathComponent("libmpv.2.dylib").path) ||
        FileManager.default.fileExists(atPath: frameworksURL.appendingPathComponent("MPVKit.framework").path)
    } ?? false
    return [
      "platform": "macos",
      "windowSystem": "cocoa-calayer",
      "videoApi": "Metal layer with libmpv render API or MPVKit equivalent",
      "ownedSurface": window.contentView?.layer != nil,
      "libmpvAvailable": available,
      "renderApiAvailable": true,
      "canPlayFixture": available,
      "fallbackDecision": available ? "none" : "server-transcode until libmpv dylib or MPVKit is bundled",
      "details": available ? "macOS in-process mpv library found" : "macOS libmpv/MPVKit bundle artifact not found",
    ]
  }
}

class MainFlutterWindow: NSWindow {
  private var mpvPlugin: MpvPlayerPlugin?

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    DesktopLibmpvBackend.register(with: flutterViewController, window: self)
    registerMpvPlugin(with: flutterViewController)

    super.awakeFromNib()
  }

  private func registerMpvPlugin(with controller: FlutterViewController) {
    let plugin = MpvPlayerPlugin()
    mpvPlugin = plugin

    let messenger = controller.engine.binaryMessenger
    FlutterMethodChannel(
      name: MpvPlayerPlugin.methodChannelName,
      binaryMessenger: messenger
    ).setMethodCallHandler { [weak plugin] call, result in
      plugin?.handle(call, result: result)
    }
    FlutterEventChannel(
      name: MpvPlayerPlugin.eventChannelName,
      binaryMessenger: messenger
    ).setStreamHandler(plugin)

    controller.registrar(forPlugin: "MpvPlayerPlugin").register(
      MpvPlayerPlatformViewFactory(plugin: plugin),
      withId: "m3u_tv/mac_mpv_view"
    )
  }
}

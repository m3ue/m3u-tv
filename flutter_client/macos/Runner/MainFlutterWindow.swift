import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    // Native libmpv playback backend (desktop_libmpv_backend.mm), the macOS
    // counterpart of desktop_libmpv_backend_register() on Linux and
    // RegisterDesktopLibmpvBackend() on Windows.
    DesktopLibmpvBackend.register(with: flutterViewController)

    super.awakeFromNib()
  }
}

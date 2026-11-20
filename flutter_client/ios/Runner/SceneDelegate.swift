import Flutter
import UIKit

/// Opts out of the iOS 27.1 vertical bar (iPhone Duo: folded, or unfolded in
/// landscape). UIKit moves native nav/tab bars and the status bar into a side
/// column and reserves a full-height leading/trailing safe-area inset for it,
/// but the whole UI is drawn by Flutter with horizontal bars (bottom nav,
/// player controls), so the column only ever held the status bar and left a
/// strip of every screen empty. Disabled, the status bar goes back to the top
/// and the side inset goes away. Guarded on the 27.1 UIKit module so older
/// Xcode toolchains (CI's default) still compile.
///
/// Where the system would use a vertical bar, the status bar it moves back to
/// the top is a tall band across every screen, so it stays hidden there (a
/// pull down still shows it). Everywhere else (other iPhones, the unfolded
/// Duo in portrait, pre-27.1) the status bar is left alone.
///
/// Item detail screens also ask, over `m3u_tv/display_regions` (see
/// `lib/shared/immersive_top.dart`), for the camera's occlusion regions so
/// their header can sit just clear of the camera instead of below the band.
final class RunnerFlutterViewController: FlutterViewController {
    static let displayRegionsChannelName = "m3u_tv/display_regions"

    private var displayRegionsChannel: FlutterMethodChannel?
    private var regionsRequested = false
    private var appliedStatusBarHidden = false
    private var lastReportedDisplayRegions: NSDictionary?

#if canImport(UIKit, _version: 9127.1)
    @available(iOS 27.1, *)
    override var preferredVerticalBarBehavior: UIVerticalBarBehavior {
        .disabled
    }
#endif

    override var prefersStatusBarHidden: Bool {
        super.prefersStatusBarHidden || systemPrefersVerticalBar
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let channel = FlutterMethodChannel(
            name: Self.displayRegionsChannelName,
            binaryMessenger: AppDelegate.sharedEngine.binaryMessenger
        )
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self, call.method == "setImmersiveTop" else {
                result(FlutterMethodNotImplemented)
                return
            }
            self.regionsRequested = (call.arguments as? Bool) ?? false
            let regions = self.displayRegions()
            self.lastReportedDisplayRegions = regions
            result(regions)
        }
        displayRegionsChannel = channel
    }

    /// Folding, unfolding and rotating all re-lay out the view; the vertical
    /// bar trait and the occlusion frames can change with each.
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        applyStatusBarVisibility()
        guard regionsRequested else { return }
        let regions = displayRegions()
        if regions != lastReportedDisplayRegions {
            lastReportedDisplayRegions = regions
            displayRegionsChannel?.invokeMethod("changed", arguments: regions)
        }
    }

    /// Read at the scene and window too, not only here: this controller opts
    /// out of the vertical bar, which leaves its own trait unspecified while
    /// the scene still reports the edge the system would use.
    private var systemPrefersVerticalBar: Bool {
#if canImport(UIKit, _version: 9127.1)
        if #available(iOS 27.1, *) {
            let traits = [
                view.window?.windowScene?.traitCollection,
                view.window?.traitCollection,
                traitCollection,
            ]
            return traits
                .compactMap { $0?.verticalBarEdge }
                .contains { $0 != .unspecified }
        }
#endif
        return false
    }

    private func applyStatusBarVisibility() {
        let hidden = systemPrefersVerticalBar
        guard hidden != appliedStatusBarHidden else { return }
        appliedStatusBarHidden = hidden
        setNeedsStatusBarAppearanceUpdate()
    }

    /// `statusBarHidden` says whether the header may use the top band;
    /// `occlusions` are `[x, y, width, height]` in points (Flutter logical
    /// pixels, as the Flutter view fills the window), margins included.
    private func displayRegions() -> NSDictionary {
        var occlusions: [[Double]] = []
#if canImport(UIKit, _version: 9127.1)
        if #available(iOS 27.1, *) {
            occlusions = view.reservedRegions(kind: .occlusion).map { region in
                let frame = region.frame
                return [frame.minX, frame.minY, frame.width, frame.height]
                    .map { Double($0) }
            }
        }
#endif
        return [
            "statusBarHidden": systemPrefersVerticalBar,
            "occlusions": occlusions,
        ] as NSDictionary
    }
}

/// The phone's window. Shows Flutter on the shared engine (see
/// `AppDelegate.sharedEngine`) instead of the implicit engine the Main
/// storyboard would create, so the CarPlay screen and the phone drive the
/// same app. Then hands the connection to FlutterSceneDelegate, which
/// forwards it and the scene's later life-cycle events (URLs, foreground,
/// background) to plugins.
class SceneDelegate: FlutterSceneDelegate {
    override func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        if let windowScene = scene as? UIWindowScene {
            let controller = RunnerFlutterViewController(
                engine: AppDelegate.sharedEngine,
                nibName: nil,
                bundle: nil
            )
            _ = controller.loadDefaultSplashScreenView()
            let window = UIWindow(windowScene: windowScene)
            window.rootViewController = controller
            self.window = window
            window.makeKeyAndVisible()
        }
        super.scene(scene, willConnectTo: session, options: connectionOptions)
    }

    /// The engine outlives this window (CarPlay may still be using it); let
    /// go of the view controller so a later window can attach a new one.
    override func sceneDidDisconnect(_ scene: UIScene) {
        super.sceneDidDisconnect(scene)
        window?.rootViewController = nil
        window = nil
    }
}

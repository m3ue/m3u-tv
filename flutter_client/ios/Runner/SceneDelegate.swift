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
final class RunnerFlutterViewController: FlutterViewController {
#if canImport(UIKit, _version: 9127.1)
    @available(iOS 27.1, *)
    override var preferredVerticalBarBehavior: UIVerticalBarBehavior {
        .disabled
    }
#endif
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

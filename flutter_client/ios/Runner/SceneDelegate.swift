import Flutter
import UIKit

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
            let controller = FlutterViewController(
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

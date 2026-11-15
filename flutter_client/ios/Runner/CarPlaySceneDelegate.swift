import CarPlay
import Flutter
import UIKit

/// The CarPlay screen's scene delegate. Starts the shared Flutter engine
/// first (the car can open the app with no phone window, which is otherwise
/// what starts it), then forwards everything to flutter_carplay's own scene
/// delegate, which builds the templates Dart sends it. Its class isn't
/// public, so it's looked up by its Objective-C name.
final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
    private lazy var carPlay: (UIResponder & CPTemplateApplicationSceneDelegate)? = {
        guard let type = NSClassFromString("FlutterCarPlaySceneDelegate") as? UIResponder.Type else {
            NSLog("[CarPlaySceneDelegate] flutter_carplay's scene delegate is missing")
            return nil
        }
        return type.init() as? UIResponder & CPTemplateApplicationSceneDelegate
    }()

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        _ = AppDelegate.sharedEngine
        carPlay?.scene?(scene, willConnectTo: session, options: connectionOptions)
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didConnect interfaceController: CPInterfaceController
    ) {
        _ = AppDelegate.sharedEngine
        carPlay?.templateApplicationScene?(templateApplicationScene, didConnect: interfaceController)
    }

    func templateApplicationScene(
        _ templateApplicationScene: CPTemplateApplicationScene,
        didDisconnectInterfaceController interfaceController: CPInterfaceController
    ) {
        carPlay?.templateApplicationScene?(
            templateApplicationScene,
            didDisconnectInterfaceController: interfaceController
        )
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        carPlay?.sceneDidBecomeActive?(scene)
    }

    func sceneWillResignActive(_ scene: UIScene) {
        carPlay?.sceneWillResignActive?(scene)
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        carPlay?.sceneDidEnterBackground?(scene)
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        carPlay?.sceneWillEnterForeground?(scene)
    }
}

import AVFoundation
import Flutter
import UIKit

@main
class AppDelegate: FlutterAppDelegate {
    private var avKitPlugin: AvKitPlaybackPlugin?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let flutterVC = FlutterViewController(project: nil, nibName: nil, bundle: nil)
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = flutterVC
        window.makeKeyAndVisible()
        self.window = window

        // Register all plugins against the FlutterViewController's engine so
        // Dart platform-channel calls (path_provider, secure_storage, etc.)
        // reach the same engine that is actually running the Dart code.
        GeneratedPluginRegistrant.register(with: flutterVC.pluginRegistry())
        registerAvKitPlugin(with: flutterVC)

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    private func registerAvKitPlugin(with controller: FlutterViewController) {
        guard let registrar = controller.pluginRegistry().registrar(forPlugin: "AvKitPlaybackPlugin") else { return }
        let plugin = AvKitPlaybackPlugin(textureRegistry: registrar.textures())
        avKitPlugin = plugin

        FlutterMethodChannel(
            name: AvKitPlaybackPlugin.methodChannelName,
            binaryMessenger: registrar.messenger()
        ).setMethodCallHandler { [weak plugin] call, result in
            plugin?.handle(call, result: result)
        }

        FlutterEventChannel(
            name: AvKitPlaybackPlugin.eventChannelName,
            binaryMessenger: registrar.messenger()
        ).setStreamHandler(plugin)
    }
}

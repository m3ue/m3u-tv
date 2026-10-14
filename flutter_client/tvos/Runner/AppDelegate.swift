import AVFoundation
import Flutter
import UIKit

@main
class AppDelegate: FlutterAppDelegate {
    private var avKitPlugin: AvKitPlaybackPlugin?
    private var mpvPlugin: MpvPlayerPlugin?

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
        registerMpvPlugin(with: flutterVC)
        registerExternalUrlChannel(with: flutterVC)

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    /// `url_launcher` isn't registered on tvOS, so trailer links (see
    /// lib/shared/trailer_button.dart) open other apps through this channel.
    /// Replies `{opened, canOpen}`: `opened` is true only when the system
    /// actually handed the URL to an app; `canOpen` is `canOpenURL` (only
    /// meaningful for schemes listed in LSApplicationQueriesSchemes).
    private func registerExternalUrlChannel(with controller: FlutterViewController) {
        guard let registrar = controller.pluginRegistry().registrar(forPlugin: "ExternalUrlChannel") else { return }
        FlutterMethodChannel(
            name: "m3u_tv/external_url",
            binaryMessenger: registrar.messenger()
        ).setMethodCallHandler { call, result in
            guard call.method == "open" else {
                result(FlutterMethodNotImplemented)
                return
            }
            guard let args = call.arguments as? [String: Any],
                  let raw = args["url"] as? String,
                  let url = URL(string: raw) else {
                result(["opened": false, "canOpen": false])
                return
            }
            let canOpen = UIApplication.shared.canOpenURL(url)
            UIApplication.shared.open(url, options: [:]) { opened in
                result(["opened": opened, "canOpen": canOpen])
            }
        }
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

    private func registerMpvPlugin(with controller: FlutterViewController) {
        guard let registrar = controller.pluginRegistry().registrar(forPlugin: "MpvPlayerPlugin") else { return }
        let plugin = MpvPlayerPlugin()
        mpvPlugin = plugin

        FlutterMethodChannel(
            name: MpvPlayerPlugin.methodChannelName,
            binaryMessenger: registrar.messenger()
        ).setMethodCallHandler { [weak plugin] call, result in
            plugin?.handle(call, result: result)
        }

        FlutterEventChannel(
            name: MpvPlayerPlugin.eventChannelName,
            binaryMessenger: registrar.messenger()
        ).setStreamHandler(plugin)

        registrar.register(
            MpvPlayerPlatformViewFactory(plugin: plugin),
            withId: "m3u_tv/apple_mpv_view"
        )
    }
}

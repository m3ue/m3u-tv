import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
    private var avKitPlugin: AvKitPlaybackPlugin?
    private var mpvPlugin: MpvPlayerPlugin?

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // UIScene lifecycle (required for apps built with the tvOS 27 SDK): the
    // scene builds its window from Main.storyboard, whose FlutterViewController
    // creates the implicit engine, so plugins register here, not against a
    // window/view controller made in application(_:didFinishLaunchingWithOptions:).
    func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
        GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
        registerAvKitPlugin(with: engineBridge.pluginRegistry)
        registerMpvPlugin(with: engineBridge.pluginRegistry)
        registerExternalUrlChannel(with: engineBridge.pluginRegistry)
    }

    /// `url_launcher` isn't registered on tvOS, so trailer links (see
    /// lib/shared/trailer_button.dart) open other apps through this channel.
    /// Replies `{opened, canOpen}`: `opened` is true only when the system
    /// actually handed the URL to an app; `canOpen` is `canOpenURL` (only
    /// meaningful for schemes listed in LSApplicationQueriesSchemes).
    private func registerExternalUrlChannel(with registry: FlutterPluginRegistry) {
        guard let registrar = registry.registrar(forPlugin: "ExternalUrlChannel") else { return }
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

    private func registerAvKitPlugin(with registry: FlutterPluginRegistry) {
        guard let registrar = registry.registrar(forPlugin: "AvKitPlaybackPlugin") else { return }
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

    private func registerMpvPlugin(with registry: FlutterPluginRegistry) {
        guard let registrar = registry.registrar(forPlugin: "MpvPlayerPlugin") else { return }
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

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

    func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
        GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
        registerAvKitPlugin(engineBridge: engineBridge)
        registerMpvPlugin(engineBridge: engineBridge)
    }

    private func registerMpvPlugin(engineBridge: FlutterImplicitEngineBridge) {
        guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "MpvPlayerPlugin") else { return }
        let messenger = registrar.messenger()

        let plugin = MpvPlayerPlugin()
        mpvPlugin = plugin

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

        registrar.register(
            MpvPlayerPlatformViewFactory(plugin: plugin),
            withId: "m3u_tv/apple_mpv_view"
        )
    }

    private func registerAvKitPlugin(engineBridge: FlutterImplicitEngineBridge) {
        guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AvKitPlaybackPlugin") else { return }
        let messenger = registrar.messenger()
        let textureRegistry = registrar.textures()

        let plugin = AvKitPlaybackPlugin(textureRegistry: textureRegistry)
        avKitPlugin = plugin

        let methodChannel = FlutterMethodChannel(
            name: AvKitPlaybackPlugin.methodChannelName,
            binaryMessenger: messenger
        )
        methodChannel.setMethodCallHandler { [weak plugin] (call: FlutterMethodCall, result: @escaping FlutterResult) in
            plugin?.handle(call, result: result)
        }

        let eventChannel = FlutterEventChannel(
            name: AvKitPlaybackPlugin.eventChannelName,
            binaryMessenger: messenger
        )
        eventChannel.setStreamHandler(plugin)
    }
}

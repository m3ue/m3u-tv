package dev.sparkison.tv

import android.app.UiModeManager
import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Build
import android.window.OnBackInvokedCallback
import android.window.OnBackInvokedDispatcher
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var media3Plugin: Media3PlaybackPlugin? = null
    private var deviceInfoChannel: MethodChannel? = null
    private var navigationChannel: MethodChannel? = null
    private var backCallback: OnBackInvokedCallback? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        media3Plugin = Media3PlaybackPlugin(this, flutterEngine)
        deviceInfoChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DEVICE_INFO_CHANNEL).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "isTelevision" -> result.success(isTelevisionDevice())
                    else -> result.notImplemented()
                }
            }
        }
        navigationChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NAVIGATION_CHANNEL)
        registerSystemBackCallback()
    }

    @Deprecated("Deprecated in Java")
    override fun onBackPressed() {
        dispatchSystemBackToFlutter()
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        unregisterSystemBackCallback()
        media3Plugin?.dispose()
        media3Plugin = null
        deviceInfoChannel?.setMethodCallHandler(null)
        deviceInfoChannel = null
        navigationChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun dispatchSystemBackToFlutter() {
        navigationChannel?.invokeMethod("systemBack", null)
    }

    private fun registerSystemBackCallback() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU || backCallback != null) return
        backCallback = OnBackInvokedCallback { dispatchSystemBackToFlutter() }
        onBackInvokedDispatcher.registerOnBackInvokedCallback(
            OnBackInvokedDispatcher.PRIORITY_DEFAULT,
            backCallback!!,
        )
    }

    private fun unregisterSystemBackCallback() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return
        backCallback?.let(onBackInvokedDispatcher::unregisterOnBackInvokedCallback)
        backCallback = null
    }

    private fun isTelevisionDevice(): Boolean {
        val uiModeManager = getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager
        val uiModeType = uiModeManager?.currentModeType
        return uiModeType == Configuration.UI_MODE_TYPE_TELEVISION ||
            packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK) ||
            packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK_ONLY)
    }

    companion object {
        private const val DEVICE_INFO_CHANNEL = "m3u_tv/device_info"
        private const val NAVIGATION_CHANNEL = "m3u_tv/navigation"
    }
}

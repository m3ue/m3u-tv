package com.m3ue.m3utv

import android.app.UiModeManager
import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var media3Plugin: Media3PlaybackPlugin? = null
    private var deviceInfoChannel: MethodChannel? = null

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
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        media3Plugin?.dispose()
        media3Plugin = null
        deviceInfoChannel?.setMethodCallHandler(null)
        deviceInfoChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
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
    }
}

package dev.sparkison.tv

import android.app.UiModeManager
import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Color
import android.os.Build
import android.util.DisplayMetrics
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var media3Plugin: Media3PlaybackPlugin? = null
    private var deviceInfoChannel: MethodChannel? = null
    private var systemUiChannel: MethodChannel? = null

    override fun attachBaseContext(newBase: Context) {
        val uiModeManager = newBase.getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager
        val isTV = uiModeManager?.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION ||
            newBase.packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK)

        val override = if (isTV) {
            val res = newBase.resources.configuration
            // Recover physical pixel width from dp + current density (safe in attachBaseContext).
            val physicalWidth = maxOf(
                (res.screenWidthDp * res.densityDpi / 160f).toInt(),
                (res.screenHeightDp * res.densityDpi / 160f).toInt(),
            )
            // Target 1920 logical pixels wide (standard 1080p TV layout target).
            // For 1080p physical this gives 1:1 (160dpi); for 4K it gives 2:1 (320dpi).
            val targetDensityDpi = if (physicalWidth > 0) {
                ((physicalWidth / 1920f) * 160).toInt().coerceIn(160, 640)
            } else {
                DisplayMetrics.DENSITY_TV
            }
            val config = Configuration(res)
            config.densityDpi = targetDensityDpi
            newBase.createConfigurationContext(config)
        } else {
            newBase
        }
        super.attachBaseContext(override)
    }

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
        systemUiChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SYSTEM_UI_CHANNEL).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "browsing", "player" -> {
                        applySystemUiPolicy(call.method)
                        result.success(null)
                    }
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
        systemUiChannel?.setMethodCallHandler(null)
        systemUiChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun applySystemUiPolicy(route: String) {
        WindowCompat.setDecorFitsSystemWindows(window, false)
        window.statusBarColor = Color.TRANSPARENT
        window.navigationBarColor = Color.TRANSPARENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.isStatusBarContrastEnforced = false
            window.isNavigationBarContrastEnforced = false
        }

        val insetsController = WindowInsetsControllerCompat(window, window.decorView)
        val systemBars = WindowInsetsCompat.Type.systemBars()
        if (route == "player") {
            insetsController.systemBarsBehavior =
                WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            insetsController.hide(systemBars)
        } else {
            insetsController.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_DEFAULT
            insetsController.show(systemBars)
        }
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
        private const val SYSTEM_UI_CHANNEL = "m3u_tv/system_ui"
    }
}

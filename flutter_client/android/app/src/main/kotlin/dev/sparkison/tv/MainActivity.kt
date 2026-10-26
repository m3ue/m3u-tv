package dev.sparkison.tv

import android.app.ActivityManager
import android.app.PictureInPictureParams
import android.app.UiModeManager
import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.os.Process
import android.util.DisplayMetrics
import android.util.Log
import android.util.Rational
import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputConnection
import android.widget.FrameLayout
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import dev.sparkison.tv.mpv.MpvPlayerPlatformViewFactory
import dev.sparkison.tv.mpv.MpvPlayerPlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterShellArgs
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var media3Plugin: Media3PlaybackPlugin? = null
    private var mpvPlugin: MpvPlayerPlugin? = null
    private var deviceInfoChannel: MethodChannel? = null
    private var systemUiChannel: MethodChannel? = null
    private var textInputChannel: MethodChannel? = null
    private var nativeLogChannel: NativeLogChannel? = null

    // Mirrors the Dart-side player route (set via applySystemUiPolicy) so
    // onUserLeaveHint knows whether leaving the app should enter PiP.
    private var isPlayerRouteActive = false

    // Set from Dart (TextInputReportingBinding) while a Flutter text field
    // holds the text input connection; read by TextEditorProxyView.
    private var flutterTextInputActive = false

    // What getFlutterShellArgs picked, for the Logs & Diagnostics header.
    private var rendererDescription = "unknown"

    // The real display density, before the TV override below. The system
    // draws the launch splash at this density, so LaunchSplash (Dart) needs it
    // to take over at the same on-screen logo size.
    private var launchDensity = 1f

    override fun attachBaseContext(newBase: Context) {
        launchDensity = newBase.resources.displayMetrics.density
        // UiModeManager.getCurrentModeType() calls getDisplayId() internally on Android 17+,
        // which NPEs here because the display isn't attached until after attachBaseContext returns.
        val isTV = newBase.packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK)

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

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Applied again per-route once Dart boots (applySystemUiPolicy), but
        // decorFitsSystemWindows must be set before the first frame too, or
        // Android 15's mandatory edge-to-edge enforcement letterboxes the
        // launch theme behind the (still opaque) system bars for one frame.
        applySystemUiPolicy("browsing")
        if (isTelevisionDevice()) installTextEditorProxy()
    }

    // Google TV Streamer, Chromecast with Google TV and other Android TV builds
    // enable config_preventImeStartupUnlessTextEditor (#309): the system answers
    // every startInput whose focused view does not report onCheckIsTextEditor()
    // with NO_EDITOR and unbinds the keyboard. FlutterView never reports it, so
    // the engine's restartInput unbinds Gboard, the showSoftInput that follows
    // draws it again without an input session, and D-pad presses and typed
    // text never reach it (flutter/flutter#177360). Ported from Plezy.
    //
    // This 1x1 view lives inside FlutterView and holds Android focus in its
    // place (FOCUS_AFTER_DESCENDANTS routes the engine's requestFocus here too).
    // It reports text-editor status from the Dart-side flag, hands the IMM
    // Flutter's own InputConnection, and vouches for FlutterView so the
    // engine's showSoftInput/restartInput(flutterView) still pass the IMM's
    // served-view check. Keys are unaffected: FlutterView.dispatchKeyEvent runs
    // before descending to the focused child.
    private inner class TextEditorProxyView(
        context: Context,
        private val flutterView: View,
    ) : View(context) {
        init {
            isFocusable = true
            isFocusableInTouchMode = true
            importantForAccessibility = IMPORTANT_FOR_ACCESSIBILITY_NO
        }

        override fun onCheckIsTextEditor(): Boolean = flutterTextInputActive

        override fun onCreateInputConnection(outAttrs: EditorInfo): InputConnection? =
            flutterView.onCreateInputConnection(outAttrs)

        override fun checkInputConnectionProxy(view: View): Boolean = view === flutterView
    }

    private fun installTextEditorProxy() {
        val flutterView = findViewById<View>(FLUTTER_VIEW_ID) as? ViewGroup ?: return
        flutterView.descendantFocusability = ViewGroup.FOCUS_AFTER_DESCENDANTS
        val proxy = TextEditorProxyView(this, flutterView)
        flutterView.addView(proxy, FrameLayout.LayoutParams(1, 1))
        if (flutterView.isFocused) proxy.requestFocus()
    }

    override fun getFlutterShellArgs(): FlutterShellArgs {
        val args = super.getFlutterShellArgs()
        val vulkan11 = 0x401000 // FEATURE_VULKAN_HARDWARE_VERSION encodes 1.1.0 as 0x401000
        // Feature flag only, not UiModeManager - see attachBaseContext.
        val isAndroidTv = packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK)
        val renderer = FlutterRendererPolicy.select(
            manufacturer = Build.MANUFACTURER,
            isAndroidTv = isAndroidTv,
            sdkInt = Build.VERSION.SDK_INT,
            supportsVulkan11 = packageManager.hasSystemFeature(PackageManager.FEATURE_VULKAN_HARDWARE_VERSION, vulkan11),
            is64Bit = Process.is64Bit(),
        )
        renderer.shellArgument?.let { args.add(it) }
        val memoryArgs = FlutterRendererPolicy.engineMemoryArgs(
            DeviceMemoryClass.isLowRam(this),
            DeviceMemoryClass.totalMemBytes(this),
        )
        memoryArgs.forEach { args.add(it) }
        rendererDescription = "${renderer.diagnosticName} $memoryArgs"
        Log.i(TAG, "Flutter renderer: $rendererDescription")
        return args
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Shared across both playback plugins -- see FrameRateManager's class
        // doc for why a single Window-scoped instance, not one per plugin.
        val nativeLog = NativeLogChannel(flutterEngine.dartExecutor.binaryMessenger)
        nativeLogChannel = nativeLog
        val frameRateManager = FrameRateManager(this) { message -> nativeLog.log("FrameRateManager", message) }
        val media3 = Media3PlaybackPlugin(this, flutterEngine, frameRateManager)
        media3Plugin = media3
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "m3u_tv/android_exo_view",
            Media3PlatformViewFactory(media3),
        )
        val mpv = MpvPlayerPlugin(this, flutterEngine, frameRateManager)
        mpvPlugin = mpv
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "m3u_tv/android_mpv_view",
            MpvPlayerPlatformViewFactory(mpv),
        )
        deviceInfoChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DEVICE_INFO_CHANNEL).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "isTelevision" -> result.success(isTelevisionDevice())
                    "getPerformanceSignals" -> result.success(performanceSignals())
                    "getRenderer" -> result.success(rendererDescription)
                    "getLaunchDensity" -> result.success(launchDensity.toDouble())
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
        textInputChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, TEXT_INPUT_CHANNEL).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "setActive" -> {
                        flutterTextInputActive = call.arguments as? Boolean ?: false
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
        mpvPlugin?.dispose()
        mpvPlugin = null
        deviceInfoChannel?.setMethodCallHandler(null)
        deviceInfoChannel = null
        systemUiChannel?.setMethodCallHandler(null)
        systemUiChannel = null
        textInputChannel?.setMethodCallHandler(null)
        textInputChannel = null
        nativeLogChannel?.dispose()
        nativeLogChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    private fun applySystemUiPolicy(route: String) {
        isPlayerRouteActive = route == "player"
        WindowCompat.setDecorFitsSystemWindows(window, false)
        // Android 15+ (API 35) enforces edge-to-edge unconditionally and
        // deprecates these setters/flags in favor of just leaving the system
        // bars to draw over content; only needed below that for a transparent
        // bar instead of the platform's default scrim.
        if (Build.VERSION.SDK_INT < 35) {
            window.statusBarColor = Color.TRANSPARENT
            window.navigationBarColor = Color.TRANSPARENT
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                window.isStatusBarContrastEnforced = false
                window.isNavigationBarContrastEnforced = false
            }
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

    // Leaving the app (Home/recents/back-to-launcher) while a video is open
    // drops into PiP instead of stopping playback. Not called on TV launcher
    // navigation triggered by the remote's dedicated Home key in the same
    // way as touch devices, but still fires for back/recents there.
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (!isPlayerRouteActive) return
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        if (!packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)) return
        val params = PictureInPictureParams.Builder()
            .setAspectRatio(Rational(16, 9))
            .build()
        try {
            enterPictureInPictureMode(params)
        } catch (e: IllegalStateException) {
            // Device/OEM refused (e.g. already in a transition) -- fall
            // through to the normal background/stop behavior.
            Log.w(TAG, "enterPictureInPictureMode failed", e)
        }
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration,
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        systemUiChannel?.invokeMethod("pipModeChanged", isInPictureInPictureMode)
    }

    /// Hardware signals the Dart-side [DevicePerformance] uses to pick the
    /// reduced tier: a 32-bit process (cheap TV sticks run 32-bit userspace),
    /// the platform low-RAM flag, and total physical memory.
    private fun performanceSignals(): Map<String, Any> {
        val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
        val memInfo = ActivityManager.MemoryInfo().also { activityManager?.getMemoryInfo(it) }
        val is64Bit = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Process.is64Bit()
        } else {
            Build.SUPPORTED_64_BIT_ABIS.isNotEmpty()
        }
        return mapOf(
            "is64Bit" to is64Bit,
            "isLowRamDevice" to (activityManager?.isLowRamDevice ?: false),
            "totalMemBytes" to memInfo.totalMem,
        )
    }

    private fun isTelevisionDevice(): Boolean {
        val uiModeManager = getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager
        val uiModeType = uiModeManager?.currentModeType
        return uiModeType == Configuration.UI_MODE_TYPE_TELEVISION ||
            packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK) ||
            packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK_ONLY)
    }

    companion object {
        private const val TAG = "MainActivity"
        private const val DEVICE_INFO_CHANNEL = "m3u_tv/device_info"
        private const val SYSTEM_UI_CHANNEL = "m3u_tv/system_ui"
        private const val TEXT_INPUT_CHANNEL = "m3u_tv/text_input"
    }
}

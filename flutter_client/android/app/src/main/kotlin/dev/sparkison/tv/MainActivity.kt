package dev.sparkison.tv

import android.app.PictureInPictureParams
import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Color
import android.os.Build
import android.os.Bundle
import android.util.DisplayMetrics
import android.util.Log
import android.util.Rational
import android.view.KeyEvent
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
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var media3Plugin: Media3PlaybackPlugin? = null
    private var mpvPlugin: MpvPlayerPlugin? = null
    private var systemUiChannel: MethodChannel? = null
    private var textInputChannel: MethodChannel? = null

    // Mirrors the Dart-side player route (set via applySystemUiPolicy) so
    // onUserLeaveHint knows whether leaving the app should enter PiP.
    private var isPlayerRouteActive = false

    // Set from Dart (TextInputReportingBinding) while a Flutter text field
    // holds the text input connection; read by TextEditorProxyView.
    private var flutterTextInputActive = false

    override fun attachBaseContext(newBase: Context) {
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

    override fun dispatchKeyEvent(event: KeyEvent): Boolean =
        super.dispatchKeyEvent(event.withoutModifierScanCode())

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

    // The shared engine (see AppFlutterEngine): Android Auto may have
    // started it already, and keeps it while connected. It's created with
    // the per-device shell args there, so getFlutterShellArgs never applies.
    override fun provideFlutterEngine(context: Context): FlutterEngine =
        AppFlutterEngine.attachActivity(this)

    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun onDestroy() {
        super.onDestroy()
        if (!isChangingConfigurations) AppFlutterEngine.detachActivity()
    }

    override fun onResume() {
        super.onResume()
        isInForeground = true
        CarMediaService.phoneCameToForeground()
    }

    override fun onPause() {
        isInForeground = false
        super.onPause()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Shared across both playback plugins -- see FrameRateManager's class
        // doc for why a single Window-scoped instance, not one per plugin.
        val nativeLog = AppFlutterEngine.nativeLog
        val frameRateManager = FrameRateManager(this) { message ->
            nativeLog?.log("FrameRateManager", message) ?: Log.i("FrameRateManager", message)
        }
        val media3 = Media3PlaybackPlugin(this, flutterEngine, frameRateManager)
        media3Plugin = media3
        currentMedia3Plugin = media3
        // Ignored after the first activity on this engine (it can outlive
        // one, see AppFlutterEngine); the factories ask for the current plugin.
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "m3u_tv/android_exo_view",
            Media3PlatformViewFactory { currentMedia3Plugin },
        )
        val mpv = MpvPlayerPlugin(this, flutterEngine, frameRateManager)
        mpvPlugin = mpv
        currentMpvPlugin = mpv
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "m3u_tv/android_mpv_view",
            MpvPlayerPlatformViewFactory { currentMpvPlugin },
        )
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
        if (currentMedia3Plugin === media3Plugin) currentMedia3Plugin = null
        if (currentMpvPlugin === mpvPlugin) currentMpvPlugin = null
        media3Plugin?.dispose()
        media3Plugin = null
        mpvPlugin?.dispose()
        mpvPlugin = null
        systemUiChannel?.setMethodCallHandler(null)
        systemUiChannel = null
        textInputChannel?.setMethodCallHandler(null)
        textInputChannel = null
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

    private fun isTelevisionDevice(): Boolean = AppFlutterEngine.isTelevisionDevice(this)

    companion object {
        private const val TAG = "MainActivity"

        /** Whether the app is in front, for Android Auto (CarMediaService). Main thread. */
        var isInForeground = false
            private set

        // The attached activity's player plugins, for the engine's view
        // factories. Main thread only.
        private var currentMedia3Plugin: Media3PlaybackPlugin? = null
        private var currentMpvPlugin: MpvPlayerPlugin? = null
        private const val SYSTEM_UI_CHANNEL = "m3u_tv/system_ui"
        private const val TEXT_INPUT_CHANNEL = "m3u_tv/text_input"
    }
}

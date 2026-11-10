package dev.sparkison.tv

import android.app.ActivityManager
import android.app.UiModeManager
import android.content.Context
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Build
import android.os.Process
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/**
 * The app's one Flutter engine, shared by [MainActivity] and
 * [CarMediaService]. Android Auto can start the app with no activity, and
 * both must see the same app state (one catalog, one set of stores), so
 * whichever starts first creates it and the other attaches.
 *
 * With no car connected nothing changes: the activity creates the engine and
 * it is destroyed with the activity, as before. While the car is connected
 * it outlives the activity (and the reverse), and goes once neither is left.
 *
 * Channels that don't need the activity live here, so they answer in either
 * case: device info, and native log lines.
 */
internal object AppFlutterEngine {
    private const val TAG = "AppFlutterEngine"
    private const val ENGINE_ID = "m3u_tv"
    private const val DEVICE_INFO_CHANNEL = "m3u_tv/device_info"

    private var activityAttached = false
    private var carConnected = false
    private var deviceInfoChannel: MethodChannel? = null

    /** What [obtain] picked, for the Logs & Diagnostics header. */
    var rendererDescription = "unknown"
        private set

    var nativeLog: NativeLogChannel? = null
        private set

    val current: FlutterEngine?
        get() = FlutterEngineCache.getInstance().get(ENGINE_ID)

    fun attachActivity(context: Context): FlutterEngine {
        activityAttached = true
        return obtain(context)
    }

    fun detachActivity() {
        activityAttached = false
        releaseIfUnused()
    }

    fun attachCar(context: Context): FlutterEngine {
        carConnected = true
        val engine = obtain(context)
        // The activity starts Dart itself (with a deep link's initial
        // route), unless the car got here first.
        if (!engine.dartExecutor.isExecutingDart) {
            engine.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
        }
        return engine
    }

    fun detachCar() {
        carConnected = false
        releaseIfUnused()
    }

    private fun obtain(context: Context): FlutterEngine {
        current?.let { return it }
        val app = context.applicationContext
        val engine = FlutterEngine(app, shellArgs(app).toTypedArray())
        val messenger = engine.dartExecutor.binaryMessenger
        nativeLog = NativeLogChannel(messenger)
        deviceInfoChannel = MethodChannel(messenger, DEVICE_INFO_CHANNEL).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "isTelevision" -> result.success(isTelevisionDevice(app))
                    "getPerformanceSignals" -> result.success(performanceSignals(app))
                    "getRenderer" -> result.success(rendererDescription)
                    // The system draws the launch splash at the real display
                    // density, before MainActivity's TV override.
                    "getLaunchDensity" -> result.success(app.resources.displayMetrics.density.toDouble())
                    else -> result.notImplemented()
                }
            }
        }
        FlutterEngineCache.getInstance().put(ENGINE_ID, engine)
        return engine
    }

    private fun releaseIfUnused() {
        if (activityAttached || carConnected) return
        val engine = current ?: return
        FlutterEngineCache.getInstance().remove(ENGINE_ID)
        deviceInfoChannel?.setMethodCallHandler(null)
        deviceInfoChannel = null
        nativeLog?.dispose()
        nativeLog = null
        engine.destroy()
    }

    private fun shellArgs(context: Context): List<String> {
        val packageManager = context.packageManager
        val vulkan11 = 0x401000 // FEATURE_VULKAN_HARDWARE_VERSION encodes 1.1.0 as 0x401000
        // Feature flag only, not UiModeManager - see MainActivity.attachBaseContext.
        val isAndroidTv = packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK)
        val renderer = FlutterRendererPolicy.select(
            manufacturer = Build.MANUFACTURER,
            isAndroidTv = isAndroidTv,
            sdkInt = Build.VERSION.SDK_INT,
            supportsVulkan11 = packageManager.hasSystemFeature(PackageManager.FEATURE_VULKAN_HARDWARE_VERSION, vulkan11),
            is64Bit = Process.is64Bit(),
        )
        val memoryArgs = FlutterRendererPolicy.engineMemoryArgs(
            DeviceMemoryClass.isLowRam(context),
            DeviceMemoryClass.totalMemBytes(context),
        )
        rendererDescription = "${renderer.diagnosticName} $memoryArgs"
        Log.i(TAG, "Flutter renderer: $rendererDescription")
        return listOfNotNull(renderer.shellArgument) + memoryArgs
    }

    fun isTelevisionDevice(context: Context): Boolean {
        val packageManager = context.packageManager
        // Android 17+ reads the display here, which a context without one
        // (the application's, when the car started the app) can't give.
        val modeType = try {
            (context.getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager)?.currentModeType
        } catch (error: RuntimeException) {
            null
        }
        return modeType == Configuration.UI_MODE_TYPE_TELEVISION ||
            packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK) ||
            packageManager.hasSystemFeature(PackageManager.FEATURE_LEANBACK_ONLY)
    }

    /// Hardware signals the Dart-side [DevicePerformance] uses to pick the
    /// reduced tier: a 32-bit process (cheap TV sticks run 32-bit userspace),
    /// the platform low-RAM flag, and total physical memory.
    private fun performanceSignals(context: Context): Map<String, Any> {
        val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
        val memInfo = ActivityManager.MemoryInfo().also { activityManager?.getMemoryInfo(it) }
        return mapOf(
            "is64Bit" to Process.is64Bit(),
            "isLowRamDevice" to (activityManager?.isLowRamDevice ?: false),
            "totalMemBytes" to memInfo.totalMem,
        )
    }
}

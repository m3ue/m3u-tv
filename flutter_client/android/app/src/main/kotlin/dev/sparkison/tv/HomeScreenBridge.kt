package dev.sparkison.tv

import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * Talks to `android_home_screen_bridge.dart` for the Android TV home screen
 * rows ([HomeScreenRows]), on the shared engine ([AppFlutterEngine]) so it
 * answers with or without the activity:
 *
 * - Dart -> here: `publish` (write the rows, then plan the next background
 *   refresh) and `takeLaunch` (the card the app was opened from, once).
 * - here -> Dart: `collect` (the rows, for [HomeScreenRefreshWorker]) and
 *   `launch` (a card was picked while the app was running).
 */
internal class HomeScreenBridge(private val context: Context, messenger: BinaryMessenger) {
    private val channel = MethodChannel(messenger, CHANNEL)

    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "publish" -> {
                    val payload = call.arguments as? Map<*, *>
                    if (payload == null) {
                        result.success(null)
                        return@setMethodCallHandler
                    }
                    writer.execute { write(context, payload) }
                    result.success(null)
                }
                "takeLaunch" -> {
                    val launch = pendingLaunch
                    pendingLaunch = null
                    result.success(launch)
                }
                else -> result.notImplemented()
            }
        }
        current = this
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        if (current === this) current = null
    }

    /**
     * Calls Dart, retrying while it's still starting (the worker started
     * the app): an unanswered call comes back not implemented.
     */
    fun callDart(method: String, attempts: Int = DART_READY_ATTEMPTS, onResult: (Any?) -> Unit) {
        channel.invokeMethod(method, null, object : MethodChannel.Result {
            override fun success(result: Any?) = onResult(result)

            override fun error(errorCode: String, errorMessage: String?, errorDetails: Any?) {
                Log.w(TAG, "$method failed: $errorCode $errorMessage")
                onResult(null)
            }

            override fun notImplemented() {
                if (attempts <= 0) {
                    onResult(null)
                    return
                }
                handler.postDelayed({ callDart(method, attempts - 1, onResult) }, DART_RETRY_DELAY_MS)
            }
        })
    }

    companion object {
        private const val TAG = "HomeScreenBridge"
        private const val CHANNEL = "m3u_tv/home_screen"
        private const val DART_READY_ATTEMPTS = 60
        private const val DART_RETRY_DELAY_MS = 500L

        private val handler = Handler(Looper.getMainLooper())

        // One writer for every publish (the app's and the worker's), so two
        // can't interleave their row syncs: both would create a channel the
        // first time, and one's card pruning could delete the other's card.
        private val writer = Executors.newSingleThreadExecutor()

        /** The engine's bridge, while there is an engine. Main thread. */
        var current: HomeScreenBridge? = null
            private set

        // The card the app was opened from, until Dart takes it. Main thread.
        private var pendingLaunch: Map<String, Any?>? = null

        /**
         * Writes the rows and plans the next refresh, on the one writer.
         * Blocks until done, so call off the main thread.
         */
        fun publish(context: Context, payload: Map<*, *>) {
            writer.submit { write(context, payload) }.get()
        }

        private fun write(context: Context, payload: Map<*, *>) {
            if (!HomeScreenRows.isSupported(context)) return
            // Thrown on the writer thread, it would take the app down.
            try {
                HomeScreenRows.publish(context, payload)
                HomeScreenRefreshWorker.schedule(context, payload)
            } catch (error: RuntimeException) {
                Log.w(TAG, "Home screen rows not written", error)
            }
        }

        /** Hands a card's [intent] to Dart, if it is one. Main thread. */
        fun deliverLaunch(intent: Intent?) {
            val launch = HomeScreenRows.launchFrom(intent) ?: return
            pendingLaunch = launch
            // Dart takes it now if the app is up, or when the shell starts.
            current?.channel?.invokeMethod("launch", null)
        }
    }
}

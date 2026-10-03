package dev.sparkison.tv

import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel

/**
 * Forwards native log lines to Dart (issue #314), where `debugPrint` tees
 * them into `AppLogBuffer` so they reach the Logs & Diagnostics upload --
 * `android.util.Log` output only lands in logcat, which a user can't get at
 * on a TV box. Meant for decisions worth reading in a user's report (Auto
 * Frame Rate's mode choice), not general chatter: everything sent here is
 * also logged to logcat, and lines sent before Dart listens go only there.
 * Safe to call from any thread.
 */
class NativeLogChannel(messenger: BinaryMessenger) : EventChannel.StreamHandler {
    private val channel = EventChannel(messenger, CHANNEL)
    private val mainHandler = Handler(Looper.getMainLooper())
    private var sink: EventChannel.EventSink? = null

    init {
        channel.setStreamHandler(this)
    }

    fun log(tag: String, message: String) {
        Log.i(tag, message)
        val line = "[$tag] $message"
        if (Looper.myLooper() == Looper.getMainLooper()) {
            sink?.success(line)
        } else {
            mainHandler.post { sink?.success(line) }
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    fun dispose() {
        channel.setStreamHandler(null)
        sink = null
    }

    companion object {
        private const val CHANNEL = "m3u_tv/native_log"
    }
}

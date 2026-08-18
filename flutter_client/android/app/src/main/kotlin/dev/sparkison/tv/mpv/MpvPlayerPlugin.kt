package dev.sparkison.tv.mpv

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Method/event channel plugin for `m3u_tv/android_mpv` + `m3u_tv/android_mpv/events`.
 *
 * Modeled on `macos/Runner/MpvPlayer/MpvPlayerPlugin.swift`, with one added
 * constraint the Apple plugins don't have: the underlying
 * `dev.jdtech.mpv.MpvPlayer` is a process-wide singleton (see
 * `MpvPlayerCore`'s header comment), so at most one [MpvPlayerCore] is ever
 * active. `attachCore` fully disposes any previous core -- awaiting its
 * native mpv handle actually closing -- before creating and initializing
 * the next one, serialized through [mutex] so concurrent attach/dispose
 * calls (e.g. rapid channel switching recreating the platform view) can't
 * interleave and violate that constraint.
 */
class MpvPlayerPlugin(val context: Context, flutterEngine: FlutterEngine) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler, MpvPlayerCore.MpvPlayerCoreDelegate {

    private val methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
    private val eventChannel = EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val mutex = Mutex()
    private val mainHandler = Handler(Looper.getMainLooper())

    private var activeCore: MpvPlayerCore? = null
    private var activeViewId: Int? = null
    private var eventSink: EventChannel.EventSink? = null

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
    }

    /**
     * Creates the [MpvPlayerCore] for [viewId] and returns it immediately
     * (its `surfaceView` is needed synchronously by
     * [MpvPlayerPlatformView]), while disposing any previous core and
     * initializing this one's native mpv handle asynchronously in the
     * background. `load`/control method calls that arrive before
     * initialization finishes are held by [waitForCore]/the core's own
     * internal mutex until it's ready.
     */
    fun attachCore(viewId: Int, viewContext: Context): MpvPlayerCore {
        val core = MpvPlayerCore(viewId, viewContext, this)
        scope.launch {
            mutex.withLock {
                val stale = activeCore
                if (stale != null) {
                    disposeCoreAwait(stale)
                }
                activeCore = core
                activeViewId = viewId
                initializeCoreAwait(core)
            }
        }
        return core
    }

    private suspend fun disposeCoreAwait(core: MpvPlayerCore) = suspendCancellableCoroutine<Unit> { continuation ->
        core.dispose { continuation.resume(Unit, onCancellation = null) }
    }

    private suspend fun initializeCoreAwait(core: MpvPlayerCore) = suspendCancellableCoroutine<Boolean> { continuation ->
        core.initialize { ok -> continuation.resume(ok, onCancellation = null) }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *>
        val viewId = (args?.get("viewId") as? Number)?.toInt()
        if (viewId == null) {
            result.error("bad-arguments", "viewId is required", null)
            return
        }

        when (call.method) {
            "load" -> {
                waitForCore(viewId, attemptsRemaining = 100) { core ->
                    if (core == null) {
                        result.success(
                            mapOf(
                                "ok" to false,
                                "error" to "mpv core not attached",
                                "code" to "backend_unavailable",
                            ),
                        )
                        return@waitForCore
                    }
                    @Suppress("UNCHECKED_CAST")
                    val headers = (args["headers"] as? Map<Any?, Any?>)
                        ?.entries
                        ?.mapNotNull { entry ->
                            val key = entry.key as? String
                            val value = entry.value as? String
                            if (key != null && value != null) key to value else null
                        }
                        ?.toMap()
                    core.load(
                        uri = args["uri"] as? String ?: "",
                        startPositionMs = (args["startPositionMs"] as? Number)?.toInt() ?: 0,
                        userAgent = args["userAgent"] as? String,
                        headers = headers,
                        externalSubtitles = parseExternalSubtitles(args["externalSubtitles"]),
                    )
                    result.success(mapOf("ok" to true))
                }
            }
            "play" -> {
                core(viewId)?.play()
                result.success(null)
            }
            "pause" -> {
                core(viewId)?.pause()
                result.success(null)
            }
            "seek" -> {
                core(viewId)?.seek((args["positionMs"] as? Number)?.toInt() ?: 0)
                result.success(null)
            }
            "stop" -> {
                core(viewId)?.stop()
                result.success(null)
            }
            "setAudioTrack" -> {
                core(viewId)?.setAudioTrack(args["trackId"] as? String)
                result.success(null)
            }
            "setSubtitleTrack" -> {
                core(viewId)?.setSubtitleTrack(args["trackId"] as? String)
                result.success(null)
            }
            "setPlaybackSpeed" -> {
                core(viewId)?.setPlaybackSpeed((args["speed"] as? Number)?.toDouble() ?: 1.0)
                result.success(null)
            }
            "dispose" -> {
                val existing = core(viewId)
                if (existing == null) {
                    result.success(null)
                    return
                }
                scope.launch {
                    mutex.withLock {
                        disposeCoreAwait(existing)
                        if (activeViewId == viewId) {
                            activeCore = null
                            activeViewId = null
                        }
                        result.success(null)
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    // MARK: - MpvPlayerCoreDelegate

    override fun mpvPlayerCore(core: MpvPlayerCore, event: Map<String, Any?>) {
        eventSink?.success(event)
    }

    // MARK: - EventChannel.StreamHandler

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    fun dispose() {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        val stale = activeCore
        activeCore = null
        activeViewId = null
        stale?.dispose {}
    }

    // MARK: - Helpers

    private fun core(viewId: Int): MpvPlayerCore? = if (activeViewId == viewId) activeCore else null

    private fun waitForCore(viewId: Int, attemptsRemaining: Int, completion: (MpvPlayerCore?) -> Unit) {
        val existing = core(viewId)
        if (existing != null) {
            completion(existing)
            return
        }
        if (attemptsRemaining <= 0) {
            completion(null)
            return
        }
        mainHandler.postDelayed({ waitForCore(viewId, attemptsRemaining - 1, completion) }, 20)
    }

    /**
     * Parses the `externalSubtitles` list `PlaybackSource` sends over the
     * `load` method call (see `MpvNativeBackendBase.load` in
     * lib/playback/mpv_native_backend_base.dart) into the triples
     * `MpvPlayerCore.load(externalSubtitles:)` expects: (uri, title, language).
     */
    private fun parseExternalSubtitles(raw: Any?): List<Triple<String, String?, String?>> {
        val list = raw as? List<*> ?: return emptyList()
        return list.mapNotNull { entry ->
            val map = entry as? Map<*, *> ?: return@mapNotNull null
            val uri = map["uri"] as? String
            if (uri.isNullOrEmpty()) return@mapNotNull null
            Triple(uri, map["title"] as? String, map["language"] as? String)
        }
    }

    companion object {
        const val METHOD_CHANNEL = "m3u_tv/android_mpv"
        const val EVENT_CHANNEL = "m3u_tv/android_mpv/events"
    }
}

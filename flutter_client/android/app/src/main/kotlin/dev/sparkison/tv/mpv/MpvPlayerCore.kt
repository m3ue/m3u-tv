package dev.sparkison.tv.mpv

import android.content.Context
import android.view.Surface
import android.view.SurfaceHolder
import android.view.SurfaceView
import dev.jdtech.mpv.EndFileReason
import dev.jdtech.mpv.MpvEvent
import dev.jdtech.mpv.MpvException
import dev.jdtech.mpv.MpvPlayer
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/**
 * Native Android/Android TV mpv playback core.
 *
 * Modeled on `macos/Runner/MpvPlayer/MpvPlayerCore.swift` and
 * `ios/Runner/MpvPlayer/MpvPlayerCore.swift`, adapted for Android's
 * `SurfaceView`/`Surface` embedding and the `dev.jdtech.mpv` libmpv Kotlin
 * bindings (github.com/edde746/libmpv-android, itself based on
 * mpv-android/mpv-android, LGPL/GPL-2.0-or-later) instead of raw libmpv C
 * calls -- the open-source Plezy player (github.com/edde746/plezy,
 * GPL-3.0), whose Apple mpv cores this codebase's own Apple backends are
 * modeled on, uses the same `dev.jdtech.mpv` bindings for its own Android
 * core.
 *
 * Renders through `vo=gpu-next,gpu` + `gpu-context=android` +
 * `hwdec=mediacodec-copy`, handing mpv a `Surface` directly via
 * `attachSurface`/`detachSurface` so mpv owns and draws into that surface
 * itself, rather than going through a Flutter texture/SurfaceTexture
 * bridge. Subtitles are rendered natively (mpv's own libass compositing).
 *
 * Unlike the Apple/macOS cores, the underlying `dev.jdtech.mpv.MpvPlayer` is
 * a process-wide singleton (one native mpv handle via static JNI bindings) --
 * [MpvPlayerPlugin] enforces that only one [MpvPlayerCore] is ever attached
 * at a time, fully closing any previous instance before creating the next.
 */
class MpvPlayerCore(
    private val viewId: Int,
    private val context: Context,
    private val delegate: MpvPlayerCoreDelegate,
) {
    interface MpvPlayerCoreDelegate {
        fun mpvPlayerCore(core: MpvPlayerCore, event: Map<String, Any?>)
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private val mutex = Mutex()
    private var player: MpvPlayer? = null
    private var sequence = 0
    private var readyEmitted = false
    private var disposed = false

    val surfaceView: SurfaceView = SurfaceView(context)

    init {
        // A plain SurfaceView punches a hole and composites *underneath* its
        // parent's own surface by default -- since this view is nested inside
        // a Flutter AndroidView (itself backed by a surface Flutter
        // composites), without this the video surface renders but is
        // entirely obscured by Flutter's own layer, showing as black.
        surfaceView.setZOrderOnTop(true)
        surfaceView.holder.addCallback(object : SurfaceHolder.Callback {
            override fun surfaceCreated(holder: SurfaceHolder) {
                attachSurface(holder.surface)
            }

            override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {}

            override fun surfaceDestroyed(holder: SurfaceHolder) {
                detachSurface()
            }
        })
    }

    /** Creates and initializes the mpv handle. Must be called once, before [load]. */
    fun initialize(onResult: (Boolean) -> Unit) {
        scope.launch {
            mutex.withLock {
                if (player != null || disposed) {
                    onResult(player != null)
                    return@withLock
                }
                try {
                    val created = MpvPlayer.create(context.applicationContext) {
                        // gpu-next (libplacebo) is the only Android VO path that
                        // applies HDR tone-mapping/Dolby Vision RPU reshaping
                        // correctly; the `,gpu` fallback keeps a device where
                        // gpu-next cannot initialize on the legacy renderer
                        // instead of no video output at all.
                        setOption("vo", "gpu-next,gpu")
                        setOption("gpu-context", "android")
                        setOption("opengl-es", "yes")
                        setOption("hwdec", "mediacodec-copy")
                        setOption("hwdec-codecs", "all")
                        setOption("ao", "audiotrack,opensles")
                        // Pause on the last frame at EOF instead of unloading,
                        // so a seek after the video ends still works (matches
                        // the desktop/Apple cores).
                        setOption("keep-open", "yes")
                        // `fuzzy` auto-loads sidecar subtitle files (.srt/.vtt)
                        // next to a local/network URI whose filename fuzzily
                        // matches, in addition to explicit sub-add calls below.
                        setOption("sub-auto", "fuzzy")
                        // No ytdl_hook use in this app -- avoid the on_load hook
                        // cost and, on a failed open, a yt-dlp spawn with the
                        // stream's access token in its argv.
                        setOption("ytdl", "no")
                    }
                    player = created
                    collectEvents(created)
                    if (surfaceView.holder.surface?.isValid == true) {
                        attachSurfaceLocked(created, surfaceView.holder.surface)
                    }
                    onResult(true)
                } catch (error: Exception) {
                    emitError("mpv_create failed: ${error.message}", "backend_unavailable")
                    onResult(false)
                }
            }
        }
    }

    private fun attachSurface(surface: Surface) {
        scope.launch {
            mutex.withLock {
                val current = player ?: return@withLock
                attachSurfaceLocked(current, surface)
            }
        }
    }

    private fun attachSurfaceLocked(player: MpvPlayer, surface: Surface) {
        try {
            player.attachSurface(surface)
        } catch (error: Exception) {
            emitError("attachSurface failed: ${error.message}", "android-mpv-error")
        }
    }

    private fun detachSurface() {
        scope.launch {
            mutex.withLock {
                val current = player ?: return@withLock
                try {
                    current.detachSurface()
                } catch (_: Exception) {
                    // Surface already gone -- nothing to detach.
                }
            }
        }
    }

    fun load(
        uri: String,
        startPositionMs: Int,
        userAgent: String?,
        headers: Map<String, String>?,
        externalSubtitles: List<Triple<String, String?, String?>>,
    ) {
        scope.launch {
            mutex.withLock {
                val current = player ?: return@withLock
                readyEmitted = false
                try {
                    if (!userAgent.isNullOrEmpty()) {
                        current.setProperty("user-agent", userAgent)
                    }
                    if (!headers.isNullOrEmpty()) {
                        val headerString = headers.entries.joinToString(",") { "${it.key}: ${it.value}" }
                        current.setProperty("http-header-fields", headerString)
                    }

                    val args = mutableListOf("loadfile", uri, "replace")
                    if (startPositionMs > 0) {
                        args.add("0")
                        args.add("start=${startPositionMs / 1000}")
                    }
                    current.command(*args.toTypedArray())

                    // Queued right after loadfile -- mpv processes commands in
                    // order, so each sidecar subtitle is attached to the file
                    // that was just queued rather than whatever was previously
                    // playing.
                    for ((subtitleUri, title, language) in externalSubtitles) {
                        val subArgs = mutableListOf("sub-add", subtitleUri, "auto")
                        if (!title.isNullOrEmpty()) {
                            subArgs.add(title)
                            if (!language.isNullOrEmpty()) subArgs.add(language)
                        }
                        current.command(*subArgs.toTypedArray())
                    }
                } catch (error: Exception) {
                    emitError("load failed: ${error.message}", "android-mpv-load-failed")
                }
            }
        }
    }

    fun play() = setProperty("pause", "no")

    fun pause() = setProperty("pause", "yes")

    fun seek(positionMs: Int) = command("seek", (positionMs / 1000.0).toString(), "absolute")

    fun stop() = command("stop")

    fun setAudioTrack(trackId: String?) = setProperty("aid", trackId ?: "no")

    fun setSubtitleTrack(trackId: String?) = setProperty("sid", trackId ?: "no")

    fun setPlaybackSpeed(speed: Double) = setProperty("speed", speed.toString())

    private fun setProperty(name: String, value: String) {
        scope.launch {
            mutex.withLock {
                try {
                    player?.setProperty(name, value)
                } catch (_: Exception) {
                    // Property write raced a teardown -- nothing to recover.
                }
            }
        }
    }

    private fun command(vararg args: String) {
        scope.launch {
            mutex.withLock {
                try {
                    player?.command(*args)
                } catch (_: Exception) {
                    // Command raced a teardown -- nothing to recover.
                }
            }
        }
    }

    /** [onComplete] fires only once the native mpv handle has actually closed. */
    fun dispose(onComplete: () -> Unit) {
        scope.launch {
            mutex.withLock {
                if (disposed) {
                    onComplete()
                    return@withLock
                }
                disposed = true
                val current = player
                player = null
                try {
                    current?.detachSurface()
                    // close() is a synchronous, blocking AutoCloseable
                    // teardown -- unlike command/setProperty/create, it is
                    // not `suspend`, so calling it directly on this scope's
                    // Dispatchers.Main would block the main thread for as
                    // long as native mpv teardown takes. If that teardown
                    // itself needs the main looper free to finish (e.g. a
                    // pending Surface/Handler callback), this deadlocks the
                    // app -- matching an observed freeze on back-press that
                    // required a force-close. Running it on Dispatchers.IO
                    // keeps the main thread free while it completes.
                    withContext(Dispatchers.IO) { current?.close() }
                } catch (_: Exception) {
                    // Already closed/closing.
                }
                onComplete()
            }
        }
    }

    // MARK: - Event pump

    private fun collectEvents(player: MpvPlayer) {
        scope.launch(start = CoroutineStart.UNDISPATCHED) {
            player.eventFlow.collect { event ->
                when (event) {
                    is MpvEvent.StartFile -> emit("START_FILE", emptyMap())
                    is MpvEvent.FileLoaded -> {
                        readyEmitted = true
                        emit("FILE_LOADED", snapshot(player, includeTracks = true))
                    }
                    is MpvEvent.PlaybackRestart -> {
                        if (readyEmitted) emit("PLAYBACK_RESTART", snapshot(player, includeTracks = false))
                    }
                    is MpvEvent.VideoReconfig -> {
                        if (readyEmitted) emit("VIDEO_RECONFIG", snapshot(player, includeTracks = false))
                    }
                    is MpvEvent.AudioReconfig, is MpvEvent.Seek, is MpvEvent.QueueOverflow, is MpvEvent.Other -> {
                        // No Dart-side counterpart; the desktop/Apple cores
                        // don't forward these either.
                    }
                    is MpvEvent.EndFile -> {
                        if (event.reason == EndFileReason.Error) {
                            emitError("mpv end-file error", "android-mpv-error")
                        } else {
                            emit("END_FILE", emptyMap())
                        }
                    }
                    is MpvEvent.Shutdown -> emit("SHUTDOWN", emptyMap())
                }
            }
        }
    }

    private suspend fun snapshot(player: MpvPlayer, includeTracks: Boolean): Map<String, Any?> {
        val result = mutableMapOf<String, Any?>()
        runCatching { player.getDouble("time-pos") }.getOrNull()?.let {
            result["positionMs"] = (it * 1000).toInt()
        }
        runCatching { player.getDouble("duration") }.getOrNull()?.let {
            if (it > 0) result["durationMs"] = (it * 1000).toInt()
        }
        val paused = runCatching { player.getFlag("pause") }.getOrNull()
        if (paused != null) result["paused"] = paused
        runCatching { player.getFlag("core-idle") }.getOrNull()?.let {
            result["buffering"] = it && paused != true
        }
        runCatching { player.getDouble("speed") }.getOrNull()?.let { result["speed"] = it }
        runCatching { player.getDouble("video-params/aspect") }.getOrNull()?.let {
            if (it > 0) result["videoAspectRatio"] = it
        }
        stringProperty(player, "aid")?.let { result["aid"] = it }
        stringProperty(player, "sid")?.let { result["sid"] = it }

        if (includeTracks) {
            val tracks = trackList(player)
            result["audioTracks"] = tracks.filter { it["type"] == "audio" }
                .map { mapOf("id" to it["id"], "label" to it["label"], "language" to it["language"]) }
            result["subtitleTracks"] = tracks.filter { it["type"] == "sub" }
                .map { mapOf("id" to it["id"], "label" to it["label"], "language" to it["language"]) }
        }

        return result
    }

    private suspend fun stringProperty(player: MpvPlayer, name: String): String? {
        val value = runCatching { player.getString(name) }.getOrNull() ?: return null
        return if (value.isEmpty() || value == "no") null else value
    }

    private suspend fun trackList(player: MpvPlayer): List<Map<String, Any?>> {
        val count = runCatching { player.getInt("track-list/count") }.getOrNull() ?: return emptyList()
        val tracks = mutableListOf<Map<String, Any?>>()
        for (i in 0 until count) {
            val type = runCatching { player.getString("track-list/$i/type") }.getOrNull()
            if (type != "audio" && type != "sub") continue
            val id = runCatching { player.getInt("track-list/$i/id") }.getOrNull() ?: continue
            val lang = runCatching { player.getString("track-list/$i/lang") }.getOrNull()
            val title = runCatching { player.getString("track-list/$i/title") }.getOrNull()
            tracks.add(
                mapOf(
                    "id" to id.toString(),
                    "type" to type,
                    "label" to (title ?: lang ?: "Track $id"),
                    "language" to lang,
                ),
            )
        }
        return tracks
    }

    private fun emit(kind: String, extra: Map<String, Any?>) {
        sequence += 1
        val payload = mutableMapOf<String, Any?>("viewId" to viewId, "sequence" to sequence, "kind" to kind)
        payload.putAll(extra)
        delegate.mpvPlayerCore(this, payload)
    }

    private fun emitError(message: String, code: String) {
        sequence += 1
        delegate.mpvPlayerCore(
            this,
            mapOf(
                "viewId" to viewId,
                "sequence" to sequence,
                "kind" to "ERROR",
                "message" to message,
                "code" to code,
                "recoverable" to true,
            ),
        )
    }
}

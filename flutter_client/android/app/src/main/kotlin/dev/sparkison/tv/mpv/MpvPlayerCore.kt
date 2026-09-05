package dev.sparkison.tv.mpv

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.view.Surface
import android.view.SurfaceHolder
import android.view.SurfaceView
import dev.sparkison.tv.libmpv.EndFileReason
import dev.sparkison.tv.libmpv.MpvEvent
import dev.sparkison.tv.libmpv.MpvException
import dev.sparkison.tv.libmpv.MpvPlayer
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Native Android/Android TV mpv playback core.
 *
 * Modeled on `macos/Runner/MpvPlayer/MpvPlayerCore.swift` and
 * `ios/Runner/MpvPlayer/MpvPlayerCore.swift`, adapted for Android's
 * `SurfaceView`/`Surface` embedding and the `dev.sparkison.tv.libmpv` libmpv
 * Kotlin bindings instead of raw libmpv C calls -- vendored in-project under
 * `android/libmpv/` (imported from the libmpv-android fork,
 * github.com/edde746/libmpv-android, itself based on mpv-android/mpv-android,
 * LGPL/GPL-2.0-or-later) with the native `libmpv`/FFmpeg binaries supplied by
 * the pinned `mpv-build` tarballs, the same approach the open-source Plezy
 * player (github.com/edde746/plezy, GPL-3.0), whose Apple mpv cores this
 * codebase's own Apple backends are modeled on, uses for its own Android
 * core.
 *
 * Renders through `vo=gpu-next,gpu` + `gpu-context=android` +
 * `hwdec=mediacodec-copy`, handing mpv a `Surface` directly via
 * `attachSurface`/`detachSurface` so mpv owns and draws into that surface
 * itself, rather than going through a Flutter texture/SurfaceTexture
 * bridge. Subtitles are rendered natively (mpv's own libass compositing).
 *
 * Unlike the Apple/macOS cores, the underlying `dev.sparkison.tv.libmpv.MpvPlayer` is
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

    // dev.sparkison.tv.libmpv's `suspend fun command()`/`setProperty()`/etc. are not
    // real suspend functions -- they call their blocking native JNI
    // counterpart directly on whatever thread invokes them, with no internal
    // dispatcher hop (confirmed by decompiling the AAR: no Dispatchers
    // reference anywhere in their bytecode). Running this scope on
    // Dispatchers.Main, as this class previously did, meant every mpv
    // command/property/create/attach call -- including `loadfile`, which can
    // block for several seconds opening a slow live stream -- executed
    // directly on the Android UI thread, starving Choreographer (observed as
    // "Skipped N frames!" and visibly janky UI on real Android TV hardware).
    // `limitedParallelism(1)` moves all of that off the UI thread while
    // still confining it to one thread at a time, same as Main was -- other
    // fields in this class (readyEmitted, lastLogText, disposed) are read
    // and written without their own synchronization, relying on exactly that
    // single-threaded assumption; a plain multi-threaded Dispatchers.IO would
    // turn those into real data races between e.g. the event pump and a
    // concurrent load(). [emit]/[emitError] below are the only places that
    // still need to reach the *main* thread specifically (Flutter channel
    // calls require it), and they hop there explicitly via [mainHandler].
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO.limitedParallelism(1))
    private val mainHandler = Handler(Looper.getMainLooper())
    private val mutex = Mutex()
    private var player: MpvPlayer? = null
    private var sequence = 0
    private var readyEmitted = false
    private var disposed = false

    // mpv's EndFileReason enum carries no detail beyond the reason code
    // (unlike the raw C API's mpv_event_end_file, which also has an error
    // code) -- dev.sparkison.tv.libmpv's Kotlin binding doesn't expose it. Tracking
    // the most recent log line here (mirroring the Windows/Linux C++ cores'
    // own `last_log_message` pattern) is the only way to surface mpv's own
    // diagnostic text (e.g. "No format found, try lowering probescore or
    // forcing the format") instead of a generic "mpv end-file error".
    private var lastLogText: String? = null

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
                        // vo=gpu, not gpu-next -- named and root-caused via
                        // Plezy's own Android mpv core (github.com/edde746/plezy,
                        // GPL-3.0), whose `initialVideoOutput()` picks
                        // `gpu-next,gpu` only for software-decode sessions and
                        // plain `gpu` for hardware-decode ones (which this app's
                        // hwdec=mediacodec-copy below always is): gpu-next
                        // samples hardware-decoded frames as a
                        // `samplerExternalOES` that libplacebo declares in both
                        // shader stages, and the Tegra GLES linker rejects that
                        // pairing ("struct type mismatch between shaders for
                        // uniform") -- Plezy's own issue #2010, a solid blue
                        // screen with audio on Shield. On this app it manifested
                        // as a full process crash instead (harder to hit under
                        // HDR's extra shader permutations, apparently harder for
                        // the Tegra driver to fail gracefully from) -- confirmed
                        // via three rounds of real-Shield-hardware retesting,
                        // where disabling individual gpu-next HDR features
                        // (hdr-compute-peak, then tone-mapping/dither) only ever
                        // delayed the crash to the next shader compile rather
                        // than fixing it, because none of them were the actual
                        // incompatibility. gpu-next's Dolby Vision RPU reshaping
                        // benefit doesn't even apply here either way: FFmpeg's
                        // mediacodec wrapper exports no DOVI side data under
                        // hardware decode, so gpu-next couldn't reshape a
                        // hardware-decoded DV stream even without the crash.
                        // vo=gpu still tone-maps HDR-to-SDR via mpv's own
                        // (older, non-libplacebo) color management -- this is a
                        // switch to a different, Tegra-safe renderer, not a loss
                        // of HDR support.
                        setOption("vo", "gpu")
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
                    collectLogMessages(created)
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
        isLive: Boolean,
        userAgent: String?,
        headers: Map<String, String>?,
        externalSubtitles: List<Triple<String, String?, String?>>,
    ) {
        scope.launch {
            mutex.withLock {
                val current = player ?: return@withLock
                readyEmitted = false
                lastLogText = null
                try {
                    if (!userAgent.isNullOrEmpty()) {
                        current.setProperty("user-agent", userAgent)
                    }
                    if (!headers.isNullOrEmpty()) {
                        val headerString = headers.entries.joinToString(",") { "${it.key}: ${it.value}" }
                        current.setProperty("http-header-fields", headerString)
                    }
                    // Live sources get a larger demuxer probe budget -- ffmpeg's
                    // default analyzeduration/probesize can be too tight for a
                    // live MPEG-TS/HLS stream under network jitter (VPN hops,
                    // slow first-byte), especially at higher (UHD) bitrates:
                    // "No format found, try lowering probescore or forcing the
                    // format" is ffmpeg giving up before enough consistent data
                    // arrived, not a real format mismatch. Deliberately not
                    // forcing demuxer-lavf-format -- live sources vary (raw
                    // MPEG-TS vs real HLS depending on the server/proxy setup),
                    // so this only widens ffmpeg's own auto-probe window rather
                    // than assuming a container. Always set explicitly (not
                    // just when live) -- unlike the desktop backends, this mpv
                    // handle is a process-wide singleton reused across every
                    // load, so a live-set override must not leak into a
                    // subsequent VOD/Series load on the same handle; the
                    // non-live values below match ffmpeg's own stock defaults,
                    // so this is a no-op for VOD, not a behavior change.
                    current.setProperty("demuxer-lavf-analyzeduration", if (isLive) "10" else "5")
                    current.setProperty("demuxer-lavf-probesize", if (isLive) "10000000" else "5000000")

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
                    // teardown. This scope now already runs on Dispatchers.IO
                    // (see [scope]'s own doc comment), so this was never at
                    // risk of blocking the main thread/deadlocking on a
                    // pending Surface/Handler callback in the first place.
                    current?.close()
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
                            val detail = lastLogText
                            val message = if (detail.isNullOrEmpty()) {
                                "mpv end-file error"
                            } else {
                                "mpv end-file error: $detail"
                            }
                            emitError(message, "android-mpv-error")
                        } else {
                            emit("END_FILE", emptyMap())
                        }
                    }
                    is MpvEvent.Shutdown -> emit("SHUTDOWN", emptyMap())
                }
            }
        }
    }

    // Tracks the most recent mpv log line so an EndFile.Error above can
    // report *why* mpv gave up, not just that it did -- see [lastLogText].
    private fun collectLogMessages(player: MpvPlayer) {
        scope.launch(start = CoroutineStart.UNDISPATCHED) {
            player.logFlow.collect { message ->
                lastLogText = message.text.trim()
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

    // Called from whichever thread the underlying mpv event/error actually
    // arrived on -- now Dispatchers.IO for everything in this class, a real
    // thread pool rather than Main's single thread -- but Flutter method/
    // event channel calls require the main thread, so this is the one place
    // that hops there explicitly rather than relying on the caller's
    // dispatcher. [sequence] is only ever touched inside the posted block so
    // concurrent callers (e.g. the event pump and a load() error racing each
    // other) can't torn-read/torn-write it -- it's also assigned in actual
    // delivery order this way, which is what the Dart-side dedup by sequence
    // number needs, not native-side generation order.
    private fun emit(kind: String, extra: Map<String, Any?>) {
        val payload = mutableMapOf<String, Any?>("viewId" to viewId, "kind" to kind)
        payload.putAll(extra)
        mainHandler.post {
            sequence += 1
            payload["sequence"] = sequence
            delegate.mpvPlayerCore(this, payload)
        }
    }

    private fun emitError(message: String, code: String) {
        mainHandler.post {
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
}

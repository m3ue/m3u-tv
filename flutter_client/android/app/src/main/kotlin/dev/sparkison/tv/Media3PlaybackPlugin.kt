package dev.sparkison.tv

import android.content.Context
import android.media.MediaFormat
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.view.SurfaceView
import androidx.annotation.OptIn
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.ProcessLifecycleOwner
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MediaItem
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks
import androidx.media3.common.MimeTypes
import androidx.media3.exoplayer.source.UnrecognizedInputFormatException
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.common.text.CueGroup
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.video.VideoFrameMetadataListener
import androidx.media3.session.MediaSession
import androidx.media3.ui.SubtitleView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Media3/ExoPlayer-based playback plugin for Android.
 *
 * Every call after "probe" carries a Dart-assigned `playerId` string
 * (defaulting to "default" when absent, so the single-player path is
 * unaffected), and player state is keyed by it (`states[playerId]`) rather
 * than held in a single field -- this lets Multiview run several concurrent
 * ExoPlayer instances over the one channel pair without any registration
 * changes. Mirrors the tvOS AvKitPlaybackPlugin.swift multi-instance shape.
 *
 * Renders into a `SurfaceView` hosted by a Flutter `PlatformView`
 * (`m3u_tv/android_exo_view`, see Media3PlatformView.kt) rather than a
 * Flutter `SurfaceProducer` texture -- see Media3PlatformView.kt's header
 * comment for why a real window-attached surface is required for correct
 * HDR rendering. The `SurfaceView` is created by Flutter (asynchronously,
 * on its own schedule) and registered via [attachSurfaceView]; `load` calls
 * that arrive first wait for it via [waitForSurfaceView], mirroring
 * MpvPlayerPlugin.kt's `waitForCore`.
 *
 * All ExoPlayer creation/control here runs on Flutter's platform (main/UI)
 * thread, the default `MethodChannel` dispatch thread -- an attempt to move
 * this to a dedicated background thread via `ExoPlayer.Builder.setLooper`
 * (to fix a real main-thread Choreographer-skipped-frames jank on `load`)
 * caused a black screen on real Shield hardware instead (HDR display-mode
 * switching still fired, so frames were reaching SurfaceFlinger, but nothing
 * rendered) -- reverted pending a correctly-targeted fix backed by real
 * diagnostic evidence rather than another blind attempt.
 */
class Media3PlaybackPlugin(
    private val context: Context,
    flutterEngine: FlutterEngine,
    private val frameRateManager: FrameRateManager,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler, DefaultLifecycleObserver {
    private val methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
    private val eventChannel = EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
    private val mainHandler = Handler(Looper.getMainLooper())
    private var events: EventChannel.EventSink? = null
    private val states = mutableMapOf<String, PlayerState>()
    private val surfaceViews = mutableMapOf<String, SurfaceView>()
    private val subtitleViews = mutableMapOf<String, SubtitleView>()

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
        ProcessLifecycleOwner.get().lifecycle.addObserver(this)
    }

    /**
     * Creates (or returns the existing) `SurfaceView` for [playerId],
     * called synchronously by [Media3PlatformView] when Flutter creates the
     * platform view. If a player is already loaded for this id (the view
     * was torn down and recreated under a live player, e.g. a Multiview
     * tile relayout), reattaches it immediately.
     */
    fun attachSurfaceView(playerId: String, viewContext: Context): SurfaceView {
        val surfaceView = SurfaceView(viewContext)
        surfaceViews[playerId] = surfaceView
        states[playerId]?.player?.setVideoSurfaceView(surfaceView)
        return surfaceView
    }

    fun detachSurfaceView(playerId: String, surfaceView: SurfaceView) {
        if (surfaceViews[playerId] === surfaceView) {
            surfaceViews.remove(playerId)
        }
    }

    /**
     * Creates (or returns the existing) `SubtitleView` for [playerId], mirroring
     * [attachSurfaceView]'s lifecycle. ExoPlayer never renders cue text itself --
     * it only delivers [Player.Listener.onCues] callbacks -- so without this,
     * text tracks appear selectable in the menu but nothing draws on screen
     * (matches Plezy's `ExoPlayerCore`, which pairs its video `SurfaceView` with
     * a `SubtitleView` added directly above it for the same reason).
     */
    fun attachSubtitleView(playerId: String, viewContext: Context): SubtitleView {
        val subtitleView = SubtitleView(viewContext)
        subtitleViews[playerId] = subtitleView
        pushCurrentCues(playerId, subtitleView)
        return subtitleView
    }

    fun detachSubtitleView(playerId: String, subtitleView: SubtitleView) {
        if (subtitleViews[playerId] === subtitleView) {
            subtitleViews.remove(playerId)
        }
    }

    /**
     * Pushes whatever cues are already current when a `SubtitleView` attaches
     * (view recreated under a live player, e.g. a Multiview tile relayout) so
     * an in-flight cue doesn't stay blank until the next `onCues` update --
     * mirrors `PlayerView`'s own attach behavior.
     */
    private fun pushCurrentCues(playerId: String, subtitleView: SubtitleView) {
        val player = states[playerId]?.player ?: return
        if (!player.isCommandAvailable(Player.COMMAND_GET_TEXT)) return
        subtitleView.setCues(player.currentCues.cues)
    }

    private fun waitForSurfaceView(playerId: String, attemptsRemaining: Int, completion: (SurfaceView?) -> Unit) {
        val existing = surfaceViews[playerId]
        if (existing != null) {
            completion(existing)
            return
        }
        if (attemptsRemaining <= 0) {
            completion(null)
            return
        }
        mainHandler.postDelayed({ waitForSurfaceView(playerId, attemptsRemaining - 1, completion) }, 20)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        val arguments = call.arguments as? Map<String, Any?>
        val playerId = arguments?.get("playerId") as? String ?: "default"

        try {
            when (call.method) {
                "probe" -> result.success(mapOf("backend" to "media3", "inAppOnly" to true, "externalIntents" to false))
                "load" -> {
                    val loadArguments = arguments ?: emptyMap()
                    waitForSurfaceView(playerId, attemptsRemaining = 100) { surfaceView ->
                        if (surfaceView == null) {
                            result.error("android-media3-state", "No video surface attached for $playerId", null)
                            return@waitForSurfaceView
                        }
                        try {
                            load(playerId, loadArguments, surfaceView)
                            result.success(mapOf("ok" to true, "backend" to "media3"))
                        } catch (error: IllegalStateException) {
                            result.error("android-media3-state", error.message, null)
                        } catch (error: RuntimeException) {
                            result.error("android-media3-runtime", error.message, null)
                        }
                    }
                }
                "play" -> {
                    requirePlayer(playerId).play()
                    result.success(null)
                }
                "pause" -> {
                    requirePlayer(playerId).pause()
                    result.success(null)
                }
                "seek" -> {
                    requirePlayer(playerId).seekTo(call.longArgument("positionMs"))
                    result.success(null)
                }
                "setAudioTrack" -> {
                    selectTrack(playerId, C.TRACK_TYPE_AUDIO, call.optionalStringArgument("trackId"))
                    result.success(null)
                }
                "setSubtitleTrack" -> {
                    selectTrack(playerId, C.TRACK_TYPE_TEXT, call.optionalStringArgument("trackId"))
                    result.success(null)
                }
                "setPlaybackSpeed" -> {
                    val speed = call.argument<Number>("speed")?.toFloat()
                    val playbackParameters = PlaybackSpeedValidation.validateAndCreatePlaybackParameters(speed)
                    requirePlayer(playerId).playbackParameters = playbackParameters
                    result.success(null)
                }
                "setVolume" -> {
                    val volume = (call.argument<Number>("volume"))?.toFloat() ?: 1f
                    requirePlayer(playerId).volume = volume
                    result.success(null)
                }
                "stop" -> {
                    requirePlayer(playerId).stop()
                    emit(playerId, "stopped")
                    result.success(null)
                }
                "dispose" -> {
                    val preserveDisplayMode = arguments?.get("preserveDisplayMode") as? Boolean ?: false
                    releasePlayer(playerId, preserveDisplayMode)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        } catch (error: IllegalStateException) {
            result.error("android-media3-state", error.message, null)
        } catch (error: RuntimeException) {
            result.error("android-media3-runtime", error.message, null)
        }
    }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink) {
        events = sink
    }

    override fun onCancel(arguments: Any?) {
        events = null
    }

    override fun onStop(owner: LifecycleOwner) {
        for (state in states.values) {
            state.player.pause()
        }
    }

    override fun onDestroy(owner: LifecycleOwner) {
        for (playerId in states.keys.toList()) {
            releasePlayer(playerId)
        }
    }

    fun dispose() {
        ProcessLifecycleOwner.get().lifecycle.removeObserver(this)
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        for (playerId in states.keys.toList()) {
            releasePlayer(playerId)
        }
    }

    @OptIn(UnstableApi::class)
    private fun load(playerId: String, arguments: Map<String, Any?>, surfaceView: SurfaceView) {
        releasePlayer(playerId)

        val source = arguments["source"] as? Map<*, *> ?: emptyMap<String, Any?>()
        val uri = source["uri"] as? String ?: throw IllegalStateException("Missing playback source uri")
        val headers = (source["headers"] as? Map<*, *>)
            ?.mapNotNull { entry ->
                val key = entry.key as? String
                val value = entry.value as? String
                if (key != null && value != null) key to value else null
            }
            ?.toMap()
            ?: emptyMap()
        val userAgent = source["userAgent"] as? String
        val startPositionMs = (source["startPositionMs"] as? Number)?.toLong() ?: 0L
        val handleAudioFocus = arguments["handleAudioFocus"] as? Boolean ?: true
        val matchDisplayRefreshRate = source["matchDisplayRefreshRate"] as? Boolean ?: false

        val httpDataSourceFactory = DefaultHttpDataSource.Factory()
            .setDefaultRequestProperties(headers)
            .setAllowCrossProtocolRedirects(true)
        if (userAgent != null) {
            httpDataSourceFactory.setUserAgent(userAgent)
        }
        val audioAttributes = AudioAttributes.Builder()
            .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE)
            .setUsage(C.USAGE_MEDIA)
            .build()
        val player = ExoPlayer.Builder(context)
            .setMediaSourceFactory(DefaultMediaSourceFactory(context).setDataSourceFactory(httpDataSourceFactory))
            .setAudioAttributes(audioAttributes, handleAudioFocus)
            .build()
        val subtitleConfigurations = buildSubtitleConfigurations(source["externalSubtitles"])
        val state = PlayerState(
            playerId = playerId,
            player = player,
            uri = uri,
            subtitleConfigurations = subtitleConfigurations,
            matchDisplayRefreshRate = matchDisplayRefreshRate,
        )
        state.mediaSession = MediaSession.Builder(context, player).setId(playerId).build()
        states[playerId] = state

        player.setVideoSurfaceView(surfaceView)
        player.addListener(Media3Listener(playerId))
        if (matchDisplayRefreshRate) {
            frameRateManager.log("ExoPlayer load: Auto Frame Rate on")
            player.setVideoFrameMetadataListener(FrameRateProbe(playerId, player))
        }
        player.setMediaItem(buildMediaItem(uri, source, subtitleConfigurations), startPositionMs)
        emit(playerId, "buffering", uri = uri, positionMs = startPositionMs)
        player.prepare()
        player.play()
    }

    private fun requirePlayer(playerId: String): ExoPlayer =
        states[playerId]?.player ?: throw IllegalStateException("No Media3 player is loaded for $playerId")

    /**
     * [preserveDisplayMode]: true when this teardown is a mid-playback
     * backend handoff (e.g. the EAC3 mpv fallback) rather than a genuine
     * stop -- skips restoring the Auto Frame Rate switch so the backend this
     * hands off to doesn't immediately reapply it, avoiding a visible
     * restore-then-reswitch flicker. See [FrameRateManager]'s class doc.
     */
    private fun releasePlayer(playerId: String, preserveDisplayMode: Boolean = false) {
        val state = states.remove(playerId) ?: return
        state.resumeStallRunnable?.let { mainHandler.removeCallbacks(it) }
        state.mediaSession?.release()
        // Detach the surface before release() instead of letting release()
        // discover and tear it down itself: ACodec's disconnectFromSurface
        // then folds into the same synchronous call as decoder/renderer
        // teardown, and on this NVIDIA decoder that combined path is what
        // shows up as multi-second main-thread Davey frames right at
        // teardown (see Media3PlaybackPlugin's class doc for why release()
        // must stay on the main thread rather than move off it).
        state.player.clearVideoSurfaceView(surfaceViews[playerId])
        state.player.release()
        subtitleViews[playerId]?.setCues(null)
        if (!preserveDisplayMode) {
            frameRateManager.restore()
        }
        emit(playerId, "disposed")
    }

    private fun emit(
        playerId: String,
        type: String,
        uri: String? = null,
        positionMs: Long? = null,
        durationMs: Long? = null,
        videoAspectRatio: Double? = null,
        audioTracks: List<Map<String, Any?>>? = null,
        subtitleTracks: List<Map<String, Any?>>? = null,
        selectedAudioTrackId: String? = null,
        selectedSubtitleTrackId: String? = null,
        includeSelectedAudioTrackId: Boolean = false,
        includeSelectedSubtitleTrackId: Boolean = false,
        code: String? = null,
        message: String? = null,
        recoverable: Boolean? = null,
    ) {
        val event = mutableMapOf<String, Any?>("type" to type, "backend" to "androidExoPlayer", "playerId" to playerId)
        if (uri != null) event["uri"] = uri
        if (positionMs != null) event["positionMs"] = positionMs
        if (durationMs != null) event["durationMs"] = durationMs
        if (videoAspectRatio != null) event["videoAspectRatio"] = videoAspectRatio
        if (audioTracks != null) event["audioTracks"] = audioTracks
        if (subtitleTracks != null) event["subtitleTracks"] = subtitleTracks
        if (includeSelectedAudioTrackId) event["selectedAudioTrackId"] = selectedAudioTrackId
        if (includeSelectedSubtitleTrackId) event["selectedSubtitleTrackId"] = selectedSubtitleTrackId
        if (code != null) event["code"] = code
        if (message != null) event["message"] = message
        if (recoverable != null) event["recoverable"] = recoverable
        events?.success(event)
    }

    private fun selectTrack(playerId: String, trackType: Int, trackId: String?) {
        val player = requirePlayer(playerId)
        val builder = player.trackSelectionParameters.buildUpon()
            .clearOverridesOfType(trackType)
            .setTrackTypeDisabled(trackType, trackId == null)

        if (trackId != null) {
            val parsed = parseTrackId(trackId)
            val group = parsed?.let { player.currentTracks.groups.getOrNull(it.first) }
            if (group != null && group.type == trackType && parsed.second in 0 until group.length) {
                builder.setOverrideForType(
                    TrackSelectionOverride(group.mediaTrackGroup, listOf(parsed.second))
                )
            }
        }

        player.trackSelectionParameters = builder.build()
        emitTrackSnapshot(playerId, player)
    }

    private fun emitTrackSnapshot(playerId: String, player: Player) {
        emit(
            playerId = playerId,
            type = if (player.isPlaying) "playing" else "ready",
            positionMs = player.currentPosition,
            durationMs = player.duration.takeIf { it != C.TIME_UNSET && it > 0 },
            audioTracks = playbackTracks(player.currentTracks, C.TRACK_TYPE_AUDIO),
            subtitleTracks = playbackTracks(player.currentTracks, C.TRACK_TYPE_TEXT),
            selectedAudioTrackId = selectedTrackId(player.currentTracks, C.TRACK_TYPE_AUDIO),
            selectedSubtitleTrackId = selectedTrackId(player.currentTracks, C.TRACK_TYPE_TEXT),
            includeSelectedAudioTrackId = true,
            includeSelectedSubtitleTrackId = true,
        )
    }

    private fun playbackTracks(tracks: Tracks, trackType: Int): List<Map<String, Any?>> {
        val result = mutableListOf<Map<String, Any?>>()
        tracks.groups.forEachIndexed { groupIndex, group ->
            if (group.type != trackType) return@forEachIndexed
            for (trackIndex in 0 until group.length) {
                val format = group.getTrackFormat(trackIndex)
                val id = trackId(trackType, groupIndex, trackIndex)
                result.add(
                    mapOf(
                        "id" to id,
                        "label" to trackLabel(trackType, trackIndex, format.label, format.language),
                        "language" to format.language,
                    )
                )
            }
        }
        return result
    }

    private fun selectedVideoFormat(tracks: Tracks): Format? {
        for (group in tracks.groups) {
            if (group.type != C.TRACK_TYPE_VIDEO) continue
            for (trackIndex in 0 until group.length) {
                if (group.isTrackSelected(trackIndex)) return group.getTrackFormat(trackIndex)
            }
        }
        return null
    }

    /** Auto Frame Rate: asks for a display mode once per distinct rate. [source] is for the log only. */
    private fun applyFrameRate(state: PlayerState, fps: Float, source: String) {
        if (!state.matchDisplayRefreshRate || fps <= 0f || fps == state.lastAppliedFps) return
        state.lastAppliedFps = fps
        frameRateManager.applyForFrameRate(fps.toDouble(), source)
    }

    /**
     * Auto Frame Rate's rate for streams whose container doesn't declare one
     * (issue #314; see [FrameRateEstimator] for which), measured from the
     * timestamps of the frames being rendered. Installed only while matching
     * is on, one per ExoPlayer (so per load). ExoPlayer calls it on its
     * playback thread; its single result is applied on the main thread,
     * where it then detaches itself.
     */
    @OptIn(UnstableApi::class)
    private inner class FrameRateProbe(
        private val playerId: String,
        private val player: ExoPlayer,
    ) : VideoFrameMetadataListener {
        private val estimator = FrameRateEstimator()
        @Volatile private var finished = false

        override fun onVideoFrameAboutToBeRendered(
            presentationTimeUs: Long,
            releaseTimeNs: Long,
            format: Format,
            mediaFormat: MediaFormat?,
        ) {
            if (finished) return
            if (format.frameRate > 0f) {
                finish { state -> applyFrameRate(state, format.frameRate, "container") }
                return
            }
            when (val result = estimator.addFrame(presentationTimeUs)) {
                FrameRateEstimator.Result.Pending -> Unit
                is FrameRateEstimator.Result.Measured -> finish { state ->
                    applyFrameRate(state, result.fps.toFloat(), "measured over ${result.frames} frames / ${result.spanUs / 1000}ms")
                }
                FrameRateEstimator.Result.Unstable -> finish {
                    frameRateManager.log("ExoPlayer: frame timestamps never settled into a steady rate, not matching")
                }
            }
        }

        private fun finish(onMain: (PlayerState) -> Unit) {
            finished = true
            mainHandler.post {
                val state = states[playerId]?.takeIf { it.player === player } ?: return@post
                player.clearVideoFrameMetadataListener(this)
                onMain(state)
            }
        }
    }

    private fun selectedTrackId(tracks: Tracks, trackType: Int): String? {
        tracks.groups.forEachIndexed { groupIndex, group ->
            if (group.type != trackType) return@forEachIndexed
            for (trackIndex in 0 until group.length) {
                if (group.isTrackSelected(trackIndex)) {
                    return trackId(trackType, groupIndex, trackIndex)
                }
            }
        }
        return null
    }

    private fun trackId(trackType: Int, groupIndex: Int, trackIndex: Int): String {
        val prefix = if (trackType == C.TRACK_TYPE_AUDIO) "audio" else "subtitle"
        return "$prefix:$groupIndex:$trackIndex"
    }

    private fun parseTrackId(trackId: String): Pair<Int, Int>? {
        val parts = trackId.split(':')
        if (parts.size != 3) return null
        val groupIndex = parts[1].toIntOrNull() ?: return null
        val trackIndex = parts[2].toIntOrNull() ?: return null
        return groupIndex to trackIndex
    }

    private fun trackLabel(trackType: Int, index: Int, label: String?, language: String?): String {
        if (!label.isNullOrBlank()) return label
        if (!language.isNullOrBlank()) return language.uppercase()
        return if (trackType == C.TRACK_TYPE_AUDIO) "Audio ${index + 1}" else "Subtitle ${index + 1}"
    }

    // Video-stall watchdog (issue #291) -- see ResumeStallPolicy for the coverage argument.
    // Runs on the main handler, same as everything else here.

    private fun armResumeStallWatchdog(playerId: String) {
        cancelResumeStallWatchdog(playerId)
        val state = states[playerId] ?: return
        val player = state.player
        if (state.resumeStallRecoveryCount >= ResumeStallPolicy.MAX_RECOVERIES_PER_SESSION) return

        // A cold decoder (0 frames ever rendered) is startup buffering's territory, not this watchdog's.
        val baselineFrames = player.videoDecoderCounters?.renderedOutputBufferCount ?: return
        if (baselineFrames <= 0) return
        val hasVideoTrack = player.currentTracks.groups.any {
            it.type == C.TRACK_TYPE_VIDEO && it.isSelected
        }
        if (!hasVideoTrack) return

        state.resumeStallBaselineFrames = baselineFrames
        state.resumeStallBaselinePositionMs = player.currentPosition
        state.resumeStallRechecksLeft = ResumeStallPolicy.MAX_RECHECKS
        val windowMs = ResumeStallPolicy.checkWindowMs(player.videoFormat?.frameRate, player.playbackParameters.speed)
        val runnable = Runnable { checkResumeStall(playerId, windowMs) }
        state.resumeStallRunnable = runnable
        mainHandler.postDelayed(runnable, windowMs)
    }

    private fun cancelResumeStallWatchdog(playerId: String) {
        val state = states[playerId] ?: return
        state.resumeStallRunnable?.let { mainHandler.removeCallbacks(it) }
        state.resumeStallRunnable = null
    }

    private fun checkResumeStall(playerId: String, windowMs: Long) {
        val state = states[playerId] ?: return
        state.resumeStallRunnable = null
        val player = state.player
        if (!player.isPlaying || player.playbackState != Player.STATE_READY) return
        val hasVideoTrack = player.currentTracks.groups.any {
            it.type == C.TRACK_TYPE_VIDEO && it.isSelected
        }
        if (!hasVideoTrack) return
        val currentFrames = player.videoDecoderCounters?.renderedOutputBufferCount ?: return

        when (
            ResumeStallPolicy.evaluate(
                baselineFrames = state.resumeStallBaselineFrames,
                currentFrames = currentFrames,
                baselinePositionMs = state.resumeStallBaselinePositionMs,
                currentPositionMs = player.currentPosition,
                durationMs = player.duration,
                windowMs = windowMs,
            )
        ) {
            ResumeStallPolicy.Verdict.HEALTHY, ResumeStallPolicy.Verdict.SKIP_NEAR_EOF -> Unit
            ResumeStallPolicy.Verdict.RECHECK -> {
                if (state.resumeStallRechecksLeft-- > 0) {
                    val runnable = Runnable { checkResumeStall(playerId, windowMs) }
                    state.resumeStallRunnable = runnable
                    mainHandler.postDelayed(runnable, windowMs)
                }
            }
            ResumeStallPolicy.Verdict.STALLED -> recoverFromResumeStall(playerId)
        }
    }

    private fun recoverFromResumeStall(playerId: String) {
        val state = states[playerId] ?: return
        state.resumeStallRecoveryCount += 1
        val targetMs = (state.player.currentPosition - ResumeStallPolicy.SEEK_BACK_MS).coerceAtLeast(0L)
        state.player.seekTo(targetMs)
    }

    private inner class Media3Listener(private val playerId: String) : Player.Listener {
        override fun onVideoSizeChanged(videoSize: VideoSize) {
            val state = states[playerId] ?: return
            if (videoSize.width > 0 && videoSize.height > 0) {
                if (state.lastVideoWidth != videoSize.width || state.lastVideoHeight != videoSize.height) {
                    state.lastVideoWidth = videoSize.width
                    state.lastVideoHeight = videoSize.height
                    val aspectRatio = (videoSize.width * videoSize.pixelWidthHeightRatio) / videoSize.height
                    val player = state.player
                    emit(
                        playerId = playerId,
                        type = if (player.isPlaying) "playing" else "ready",
                        positionMs = player.currentPosition,
                        durationMs = player.duration.takeIf { it != C.TIME_UNSET && it > 0 },
                        videoAspectRatio = aspectRatio.toDouble(),
                    )
                }
            }
        }

        override fun onTracksChanged(tracks: Tracks) {
            val state = states[playerId] ?: return
            val player = state.player
            emitTrackSnapshot(playerId, player)

            // The selected track's own format, not player.videoFormat: that
            // is the renderer's input format, which needn't be set yet when
            // the first onTracksChanged lands. Unset (<= 0) for most
            // containers -- FrameRateProbe measures those instead.
            selectedVideoFormat(tracks)?.let { applyFrameRate(state, it.frameRate, "container") }
        }

        override fun onCues(cueGroup: CueGroup) {
            subtitleViews[playerId]?.setCues(cueGroup.cues)
        }

        override fun onPlaybackStateChanged(playbackState: Int) {
            val player = states[playerId]?.player ?: return
            val dur = player.duration.takeIf { it != C.TIME_UNSET && it > 0 }
            when (playbackState) {
                Player.STATE_BUFFERING -> emit(playerId, "buffering", positionMs = player.currentPosition)
                Player.STATE_READY -> emit(playerId, if (player.playWhenReady) "playing" else "ready", positionMs = player.currentPosition, durationMs = dur)
                Player.STATE_ENDED -> emit(playerId, "end", positionMs = player.currentPosition, durationMs = dur)
                Player.STATE_IDLE -> Unit
            }
        }

        override fun onIsPlayingChanged(isPlaying: Boolean) {
            val player = states[playerId]?.player ?: return
            val dur = player.duration.takeIf { it != C.TIME_UNSET && it > 0 }
            emit(playerId, if (isPlaying) "playing" else "ready", positionMs = player.currentPosition, durationMs = dur)
            if (isPlaying) armResumeStallWatchdog(playerId) else cancelResumeStallWatchdog(playerId)
        }

        override fun onPlayerError(error: PlaybackException) {
            val state = states[playerId]
            if (state != null && state.retryAsTs(error)) {
                emit(playerId, "buffering", uri = state.uri, positionMs = state.player.currentPosition)
                state.player.prepare()
                return
            }

            emit(
                playerId,
                "error",
                positionMs = state?.player?.currentPosition,
                code = error.errorCodeName,
                message = error.message ?: "Media3 playback failed",
                recoverable = true,
            )
        }
    }

    private data class PlayerState(
        val playerId: String,
        val player: ExoPlayer,
        val uri: String,
        val subtitleConfigurations: List<MediaItem.SubtitleConfiguration> = emptyList(),
        var mediaSession: MediaSession? = null,
        var retriedHlsAsProgressive: Boolean = false,
        var lastVideoWidth: Int = 0,
        var lastVideoHeight: Int = 0,
        val matchDisplayRefreshRate: Boolean = false,
        var lastAppliedFps: Float = 0f,
        var resumeStallRunnable: Runnable? = null,
        var resumeStallBaselineFrames: Int = 0,
        var resumeStallBaselinePositionMs: Long = 0L,
        var resumeStallRechecksLeft: Int = 0,
        var resumeStallRecoveryCount: Int = 0,
    ) {
        fun retryAsTs(error: PlaybackException): Boolean {
            if (retriedHlsAsProgressive || !error.looksLikeFormatMismatch()) {
                return false
            }

            retriedHlsAsProgressive = true
            val builder = MediaItem.Builder()
                .setUri(Uri.parse(uri))
                .setMimeType(MimeTypes.VIDEO_MP2T)
            if (subtitleConfigurations.isNotEmpty()) {
                builder.setSubtitleConfigurations(subtitleConfigurations)
            }
            player.setMediaItem(builder.build(), player.currentPosition)
            return true
        }
    }

    private fun buildMediaItem(
        uri: String,
        source: Map<*, *>,
        subtitleConfigurations: List<MediaItem.SubtitleConfiguration>,
    ): MediaItem {
        val isLive = source["isLive"] as? Boolean ?: false
        val metadata = source["metadata"] as? Map<*, *>
        val containerExtension = metadata?.get("container_extension") as? String

        // For live streams, always hint HLS first (Xtream live URLs have no extension).
        // For VOD/series, use the container extension from metadata to avoid format sniffing.
        val mimeType: String? = when {
            isLive -> MimeTypes.APPLICATION_M3U8
            containerExtension != null -> mimeTypeFromExtension(containerExtension)
            else -> null
        }

        val builder = MediaItem.Builder().setUri(Uri.parse(uri))
        if (mimeType != null) {
            builder.setMimeType(mimeType)
        }
        if (subtitleConfigurations.isNotEmpty()) {
            builder.setSubtitleConfigurations(subtitleConfigurations)
        }
        return builder.build()
    }

    private fun buildSubtitleConfigurations(raw: Any?): List<MediaItem.SubtitleConfiguration> {
        val entries = raw as? List<*> ?: return emptyList()
        return entries.mapNotNull { entry ->
            val map = entry as? Map<*, *> ?: return@mapNotNull null
            val subtitleUri = map["uri"] as? String ?: return@mapNotNull null
            val language = map["language"] as? String
            val label = map["title"] as? String
            MediaItem.SubtitleConfiguration.Builder(Uri.parse(subtitleUri))
                .setMimeType(subtitleMimeTypeFromUri(subtitleUri))
                .apply {
                    if (language != null) setLanguage(language)
                    if (label != null) setLabel(label)
                }
                .setSelectionFlags(0)
                .build()
        }
    }

    private fun subtitleMimeTypeFromUri(uri: String): String {
        val path = Uri.parse(uri).path ?: uri
        return when (path.substringAfterLast('.', "").lowercase()) {
            "vtt" -> MimeTypes.TEXT_VTT
            "ttml", "dfxp", "xml" -> MimeTypes.APPLICATION_TTML
            "ssa", "ass" -> MimeTypes.TEXT_SSA
            else -> MimeTypes.APPLICATION_SUBRIP
        }
    }

    private fun mimeTypeFromExtension(ext: String): String? = when (ext.lowercase().trimStart('.')) {
        "mp4", "m4v" -> MimeTypes.VIDEO_MP4
        "mkv" -> MimeTypes.VIDEO_MATROSKA
        "ts" -> MimeTypes.VIDEO_MP2T
        "m3u8" -> MimeTypes.APPLICATION_M3U8
        "mov" -> "video/quicktime"
        "avi" -> "video/avi"
        "flv" -> "video/x-flv"
        else -> null
    }

    private fun MethodCall.argumentsMap(): Map<String, Any?> = arguments as? Map<String, Any?> ?: emptyMap()

    private fun MethodCall.longArgument(name: String): Long = (argument<Number>(name))?.toLong() ?: 0L

    companion object {
        const val METHOD_CHANNEL = "m3u_tv/android_media3"
        const val EVENT_CHANNEL = "m3u_tv/android_media3/events"
    }
}

private fun PlaybackException.looksLikeFormatMismatch(): Boolean {
    if (cause is UnrecognizedInputFormatException) return true
    val text = listOfNotNull(message, cause?.message).joinToString("\n")
    return text.contains("Input does not start with the #EXTM3U header") ||
        text.contains("UnrecognizedInputFormatException")
}


private fun MethodCall.optionalStringArgument(name: String): String? {
    val args = arguments as? Map<*, *> ?: return null
    return args[name] as? String
}

package dev.sparkison.tv

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.MediaFormat
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.view.SurfaceView
import android.widget.FrameLayout
import androidx.annotation.OptIn
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.ProcessLifecycleOwner
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.ForwardingPlayer
import androidx.media3.common.Format
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.PlaybackParameters
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks
import androidx.media3.common.MimeTypes
import androidx.media3.exoplayer.source.UnrecognizedInputFormatException
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.Timeline
import androidx.media3.common.VideoSize
import androidx.media3.common.text.CueGroup
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.DefaultLoadControl
import androidx.media3.exoplayer.analytics.AnalyticsListener
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.exoplayer.trackselection.DefaultTrackSelector
import androidx.media3.exoplayer.video.VideoFrameMetadataListener
import androidx.media3.session.MediaSession
import androidx.media3.ui.SubtitleView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob

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
    private val nowPlayingChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NOW_PLAYING_CHANNEL)
    private val artworkLoader = LogoFramingBitmapLoader(context)
    private val mainHandler = Handler(Looper.getMainLooper())
    private var events: EventChannel.EventSink? = null
    private val states = mutableMapOf<String, PlayerState>()
    private val surfaceViews = mutableMapOf<String, SurfaceView>()
    private val subtitleViews = mutableMapOf<String, SubtitleView>()
    private val posterOverlays = mutableMapOf<String, PosterOverlay>()
    private val posterScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
        nowPlayingChannel.setMethodCallHandler { call, result ->
            when (call.method) {
                "update" -> {
                    updateNowPlaying(call.arguments as? Map<*, *> ?: emptyMap<String, Any?>())
                    result.success(null)
                }
                "clear" -> {
                    clearNowPlaying()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
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
     * Creates (or returns the existing) poster overlay for [playerId],
     * mirroring [attachSurfaceView]'s lifecycle. See `PosterLoader.kt`'s
     * header comment for why this lives in the native view hierarchy
     * instead of a Flutter-side overlay.
     */
    fun attachPosterView(playerId: String, viewContext: Context): FrameLayout {
        val overlay = PosterOverlay(viewContext, posterScope)
        posterOverlays[playerId] = overlay
        return overlay.view
    }

    fun detachPosterView(playerId: String, view: FrameLayout) {
        if (posterOverlays[playerId]?.view === view) {
            posterOverlays.remove(playerId)
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
                "addExternalSubtitle" -> {
                    addExternalSubtitle(
                        playerId,
                        call.argument<String>("uri") ?: throw IllegalArgumentException("uri required"),
                        call.optionalStringArgument("title"),
                        call.optionalStringArgument("language"),
                    )
                    result.success(null)
                }
                "setPlaybackSpeed" -> {
                    val speed = call.argument<Number>("speed")?.toFloat()
                    val playbackParameters = PlaybackSpeedValidation.validateAndCreatePlaybackParameters(speed)
                    requirePlayer(playerId).playbackParameters = playbackParameters
                    result.success(null)
                }
                "setSyncOffset" -> {
                    val factory = states[playerId]?.renderersFactory
                    val delayUs = (call.argument<Number>("milliseconds")?.toLong() ?: 0L) * 1_000L
                    when (call.argument<String>("property")) {
                        "audio-delay" -> factory?.audioDelayUs?.set(delayUs)
                        "sub-delay" -> factory?.subtitleDelayUs?.set(delayUs)
                    }
                    result.success(null)
                }
                "setAllowDisplayModeChanges" -> {
                    setAllowDisplayModeChanges(playerId, call.argument<Boolean>("allowed") ?: true)
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
            if (!state.keepPlayingInBackground) state.player.pause()
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
        nowPlayingChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        for (playerId in states.keys.toList()) {
            releasePlayer(playerId)
        }
    }

    @OptIn(UnstableApi::class)
    private fun load(playerId: String, arguments: Map<String, Any?>, surfaceView: SurfaceView) {
        // The media session outlives the player it wraps: a reload (channel
        // change, possibly from the notification with the app in the
        // background) swaps the new player in, so PlaybackService and the
        // notification carry on instead of stopping and having to restart
        // from the background, which Android 12+ doesn't allow.
        val previousSessionPlayer = states[playerId]?.sessionPlayer
        val keptSession = releasePlayer(playerId, keepSession = true)

        val source = arguments["source"] as? Map<*, *> ?: emptyMap<String, Any?>()
        val uri = source["uri"] as? String ?: throw IllegalStateException("Missing playback source uri")
        val metadata = source["metadata"] as? Map<*, *>
        // Prefers the wide backdrop over the portrait poster - same order
        // the Flutter loading overlay uses on other platforms (see
        // `player_screen.dart`'s `_loadingBackdropUrl`), so Android looks
        // identical to the rest once this overlay is in place.
        val posterUrl = (metadata?.get("backdrop_url") as? String) ?: (metadata?.get("poster_url") as? String)
        posterOverlays[playerId]?.show(posterUrl)
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
        val startFromBeginning = source["startFromBeginning"] as? Boolean ?: false
        val handleAudioFocus = arguments["handleAudioFocus"] as? Boolean ?: true
        val matchDisplayRefreshRate = source["matchDisplayRefreshRate"] as? Boolean ?: false
        val allowDisplayModeChanges = source["allowDisplayModeChanges"] as? Boolean ?: true

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
        // An HDMI renegotiation mid-playback (an Auto Frame Rate switch, or
        // an AVR link drop) briefly reports no passthrough support; the
        // selection falls off the encoded audio track, and without this flag
        // never re-picks it once capabilities return -- playback carries on
        // silent until a track is chosen by hand. androidx/media#2258; Plezy's
        // ExoPlayerCore sets the same flag for the same Shield behavior.
        val trackSelector = DefaultTrackSelector(
            context,
            DefaultTrackSelector.Parameters.Builder(context)
                .setAllowInvalidateSelectionsOnRendererCapabilitiesChange(true)
                .build(),
        )
        // DefaultRenderersFactory plus live audio/subtitle sync offsets.
        val renderersFactory = SyncOffsetRenderersFactory(context)
        val playerBuilder = ExoPlayer.Builder(context, renderersFactory)
            .setTrackSelector(trackSelector)
            .setMediaSourceFactory(
                // DefaultDataSource passes web URLs to the HTTP factory and also reads
                // the local files online subtitles are downloaded to. The extractors
                // factory adds caption tracks to OTA MPEG-2 streams whose PMT omits
                // the ATSC caption descriptor.
                DefaultMediaSourceFactory(context, AtscCaptionExtractorsFactory())
                    .setDataSourceFactory(DefaultDataSource.Factory(context, httpDataSourceFactory))
            )
            .setAudioAttributes(audioAttributes, handleAudioFocus)
        // Timeshift only: the shared-buffer/chase path is re-segmented into
        // short HLS segments, where a small cushion and a fast resume after a
        // brief upstream gap matter. Plain live and VOD keep ExoPlayer's
        // defaults.
        if ((source["uri"] as? String)?.contains("timeshift=1") == true) {
            val loadControl = DefaultLoadControl.Builder()
                .setBufferDurationsMs(
                    /* minBufferMs = */ 8000,
                    /* maxBufferMs = */ 30000,
                    /* bufferForPlaybackMs = */ 1000,
                    /* bufferForPlaybackAfterRebufferMs = */ 1200,
                )
                .setPrioritizeTimeOverSizeThresholds(true)
                .build()
            playerBuilder.setLoadControl(loadControl)
        }
        val player = playerBuilder.build()
        val subtitleConfigurations = buildSubtitleConfigurations(source["externalSubtitles"])
        val state = PlayerState(
            playerId = playerId,
            player = player,
            renderersFactory = renderersFactory,
            uri = uri,
            subtitleConfigurations = subtitleConfigurations,
            matchDisplayRefreshRate = matchDisplayRefreshRate,
            allowDisplayModeChanges = allowDisplayModeChanges,
        )
        val sessionPlayer = ChannelSkipPlayer(player) { forward ->
            nowPlayingChannel.invokeMethod(
                "command",
                mapOf("name" to if (forward) "next" else "previous"),
            )
        }
        state.sessionPlayer = sessionPlayer
        // Android Auto's own player gives way, and follows a channel change
        // here if it was showing this one.
        CarMediaService.phonePlaybackStarted(previousSessionPlayer, sessionPlayer)
        state.mediaSession = keptSession?.also { it.player = sessionPlayer }
            ?: MediaSession.Builder(context, sessionPlayer)
                .setId(playerId)
                .setSessionActivity(appLaunchIntent())
                .setBitmapLoader(artworkLoader)
                .build()
        states[playerId] = state
        // ExoPlayer treats startPosition 0 on a live item as the default live
        // edge, so "Start from beginning" can't be expressed via setMediaItem.
        // Seek to the window start once the timeline is READY (see listener).
        state.pendingStartFromBeginning = startFromBeginning
        // Track the mime we actually opened with so retryFlippedMime can
        // flip it if the probe guessed wrong (HLS body vs TS pipe).
        state.lastMimeType = (source["mimeType"] as? String)
            ?: if (uri.contains("timeshift=1")) null
            else if (source["isLive"] as? Boolean == true) MimeTypes.APPLICATION_M3U8
            else null

        player.setVideoSurfaceView(surfaceView)
        player.addListener(Media3Listener(playerId))
        // A live stream's splices jump the audio clock in normal use, and plain
        // live has nothing to resume, so the freeze watchdog only watches
        // on-demand content — plus seekable live windows (timeshift/DVR), where
        // a seek-induced discontinuity that stalls playback must be reported
        // (otherwise the player freezes with no error, e.g. second rewind).
        val seekableLive = source["seekableLive"] as? Boolean ?: false
        if (source["isLive"] as? Boolean != true || seekableLive) {
            player.addAnalyticsListener(AudioDiscontinuityListener(playerId, player))
        }
        if (matchDisplayRefreshRate && allowDisplayModeChanges) {
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
    /**
     * [keepSession]: hand the player's media session back instead of
     * releasing it, for [load] to put its new player into. Returns it.
     */
    private fun releasePlayer(
        playerId: String,
        preserveDisplayMode: Boolean = false,
        keepSession: Boolean = false,
    ): MediaSession? {
        val state = states.remove(playerId) ?: return null
        state.resumeStallRunnable?.let { mainHandler.removeCallbacks(it) }
        if (!keepSession) {
            state.sessionPlayer?.let(CarMediaService::phonePlaybackStopped)
            state.mediaSession?.let { session ->
                PlaybackService.detach(session)
                session.release()
            }
        }
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
        return if (keepSession) state.mediaSession else null
    }

    private fun appLaunchIntent(): PendingIntent = PendingIntent.getActivity(
        context,
        0,
        Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    /**
     * Dart's Now Playing update for the full-screen player (see
     * `now_playing_bridge.dart`): the title, artwork and channel buttons, for
     * Android Auto (see [CarMediaService]) and, while Background audio is on,
     * for [PlaybackService] (notification, lock screen controls, keeps playing
     * after leaving the app).
     */
    private fun updateNowPlaying(arguments: Map<*, *>) {
        val target = (arguments["playerId"] as? String)?.let { states[it] }
        for (state in states.values) {
            if (state !== target) stopBackgroundPlayback(state)
        }
        if (target == null) return
        // Kept up to date whatever the Background audio setting: Android
        // Auto shows and controls this player too (see CarMediaService).
        target.sessionPlayer?.canChangeChannel = arguments["canChangeChannel"] as? Boolean ?: false
        val artworkUri = (arguments["artworkUrl"] as? String)?.let(Uri::parse)
        // Registered before the metadata goes out, so the first load of it
        // is already framed.
        if (artworkUri != null && arguments["artworkIsLogo"] == true) {
            artworkLoader.markLogo(artworkUri)
        }
        val metadata = MediaMetadata.Builder()
            .setTitle(arguments["title"] as? String)
            .setArtist(arguments["subtitle"] as? String)
            .setArtworkUri(artworkUri)
            .build()
        if (metadata != target.nowPlayingMetadata) {
            target.nowPlayingMetadata = metadata
            val player = target.player
            // Same URI, so ExoPlayer swaps the metadata in place without
            // re-preparing the stream.
            player.currentMediaItem?.let { item ->
                player.replaceMediaItem(
                    player.currentMediaItemIndex,
                    item.buildUpon().setMediaMetadata(metadata).build(),
                )
            }
        }
        target.sessionPlayer?.let(CarMediaService::showPhonePlayer)

        val keepPlaying = arguments["keepPlayingInBackground"] as? Boolean ?: false
        if (!keepPlaying) {
            stopBackgroundPlayback(target)
            return
        }
        target.keepPlayingInBackground = true
        target.mediaSession?.let { PlaybackService.attach(context.applicationContext, it) }
    }

    private fun clearNowPlaying() {
        for (state in states.values) stopBackgroundPlayback(state)
    }

    private fun stopBackgroundPlayback(state: PlayerState) {
        if (!state.keepPlayingInBackground) return
        state.keepPlayingInBackground = false
        state.mediaSession?.let(PlaybackService::detach)
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

    /**
     * Playback duration for the UI/seek bar.
     *
     * Live HLS (plain and timeshift windows) reports `player.duration` as
     * [C.TIME_UNSET]; the real window length lives on the timeline window
     * and only appears once the playlist has been parsed — and again on every
     * playlist refresh as the window slides. Falls back to that so seekable
     * live gets a growing total instead of a permanent 0:00.
     */
    private fun effectiveDurationMs(player: Player): Long? {
        val direct = player.duration
        if (direct != C.TIME_UNSET && direct > 0) return direct
        val timeline = player.currentTimeline
        if (timeline.isEmpty) return null
        val index = player.currentMediaItemIndex
        if (index == C.INDEX_UNSET) return null
        val window = timeline.getWindow(index, Timeline.Window())
        val fromWindow = window.durationMs
        return if (fromWindow != C.TIME_UNSET && fromWindow > 0) fromWindow else null
    }

    /**
     * ExoPlayer can only take a sideloaded subtitle as part of the media item, so
     * this re-prepares at the current position. [PlayerState.subtitleConfigurations]
     * keeps it for a later retryAsTs.
     */
    private fun addExternalSubtitle(playerId: String, uri: String, title: String?, language: String?) {
        val state = states[playerId] ?: throw IllegalStateException("Unknown player: $playerId")
        val player = state.player
        val item = player.currentMediaItem ?: return
        val configuration = MediaItem.SubtitleConfiguration.Builder(Uri.parse(uri))
            .setMimeType(subtitleMimeTypeFromUri(uri))
            .setSelectionFlags(C.SELECTION_FLAG_DEFAULT)
            .apply {
                if (language != null) setLanguage(language)
                if (title != null) setLabel(title)
            }
            .build()
        state.subtitleConfigurations = state.subtitleConfigurations + configuration
        player.trackSelectionParameters = player.trackSelectionParameters.buildUpon()
            .clearOverridesOfType(C.TRACK_TYPE_TEXT)
            .setTrackTypeDisabled(C.TRACK_TYPE_TEXT, false)
            .setPreferredTextLanguage(language)
            .build()
        player.setMediaItem(
            item.buildUpon().setSubtitleConfigurations(state.subtitleConfigurations).build(),
            player.currentPosition,
        )
        player.prepare()
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
            durationMs = effectiveDurationMs(player),
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

    /**
     * Turns display mode changes on or off for the stream already playing
     * (the EPG preview going full screen, and back): off restores the mode,
     * on applies the stream's Auto Frame Rate decision straight away.
     */
    @OptIn(UnstableApi::class)
    private fun setAllowDisplayModeChanges(playerId: String, allowed: Boolean) {
        val state = states[playerId] ?: return
        if (state.allowDisplayModeChanges == allowed) return
        state.allowDisplayModeChanges = allowed
        state.lastAppliedFps = 0f
        if (!state.matchDisplayRefreshRate) return
        if (!allowed) {
            frameRateManager.restore()
            return
        }
        frameRateManager.log("ExoPlayer: Auto Frame Rate on for the playing stream")
        val fps = state.player.videoFormat?.frameRate ?: 0f
        if (fps > 0f) {
            applyFrameRate(state, fps, "container")
        } else {
            state.player.setVideoFrameMetadataListener(FrameRateProbe(playerId, state.player))
        }
    }

    /** Auto Frame Rate: asks for a display mode once per distinct rate. [source] is for the log only. */
    private fun applyFrameRate(state: PlayerState, fps: Float, source: String) {
        if (!state.matchDisplayRefreshRate || !state.allowDisplayModeChanges) return
        if (fps <= 0f || fps == state.lastAppliedFps) return
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
        // The one reliable "a decoded frame is now actually on screen"
        // signal - matches the Dart side's own `_awaitingFirstFrame` gating
        // for non-mpv backends (see player_screen.dart).
        override fun onRenderedFirstFrame() {
            posterOverlays[playerId]?.hide()
        }

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
                        durationMs = effectiveDurationMs(player),
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
            val state = states[playerId] ?: return
            val player = state.player
            if (playbackState == Player.STATE_READY && state.pendingStartFromBeginning) {
                state.pendingStartFromBeginning = false
                if (player.isCommandAvailable(Player.COMMAND_SEEK_IN_CURRENT_MEDIA_ITEM)) {
                    player.seekTo(0L)
                }
            }
            val dur = effectiveDurationMs(player)
            when (playbackState) {
                Player.STATE_BUFFERING -> emit(playerId, "buffering", positionMs = player.currentPosition)
                Player.STATE_READY -> emit(playerId, if (player.playWhenReady) "playing" else "ready", positionMs = player.currentPosition, durationMs = dur)
                Player.STATE_ENDED -> emit(playerId, "end", positionMs = player.currentPosition, durationMs = dur)
                Player.STATE_IDLE -> Unit
            }
        }

        // Live/timeshift window duration only lands on the timeline after the
        // playlist parses (and again on every refresh as the window slides).
        // Without this the seek bar total stays 0:00 — player.duration is
        // TIME_UNSET for live HLS and state-change emits often fire first.
        override fun onTimelineChanged(timeline: Timeline, reason: Int) {
            val player = states[playerId]?.player ?: return
            val dur = effectiveDurationMs(player) ?: return
            emit(
                playerId,
                if (player.isPlaying) "playing" else "ready",
                positionMs = player.currentPosition,
                durationMs = dur,
            )
        }

        override fun onIsPlayingChanged(isPlaying: Boolean) {
            val player = states[playerId]?.player ?: return
            val dur = effectiveDurationMs(player)
            emit(playerId, if (isPlaying) "playing" else "ready", positionMs = player.currentPosition, durationMs = dur)
            if (isPlaying) armResumeStallWatchdog(playerId) else cancelResumeStallWatchdog(playerId)
        }

        override fun onPlayerError(error: PlaybackException) {
            val state = states[playerId]
            if (state != null && state.retryFlippedMime(error)) {
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

    /** Reports a title ExoPlayer can't keep in time. See [AudioDiscontinuityPolicy]. */
    private inner class AudioDiscontinuityListener(
        private val playerId: String,
        private val player: ExoPlayer,
    ) : AnalyticsListener {
        private val policy = AudioDiscontinuityPolicy()
        private var stallCheck: Runnable? = null

        override fun onAudioSinkError(eventTime: AnalyticsListener.EventTime, audioSinkError: Exception) {
            if (audioSinkError !is AudioSink.UnexpectedDiscontinuityException) return
            stallCheck?.let { mainHandler.removeCallbacks(it) }
            stallCheck = null
            if (policy.record(eventTime.realtimeMs)) {
                report()
                return
            }
            val jumpPositionMs = player.currentPosition
            val check = Runnable {
                stallCheck = null
                // A released player's position can't be read, and it has nothing left to report.
                if (states[playerId]?.player !== player) return@Runnable
                if (policy.checkStalled(jumpPositionMs, player.currentPosition, player.playWhenReady)) report()
            }
            stallCheck = check
            mainHandler.postDelayed(check, AudioDiscontinuityPolicy.STALL_CHECK_MS)
        }

        private fun report() {
            emit(
                playerId,
                "error",
                positionMs = player.currentPosition,
                code = AUDIO_DISCONTINUITY_ERROR_CODE,
                message = "Repeated audio timestamp discontinuities",
                recoverable = true,
            )
        }
    }

    private data class PlayerState(
        val playerId: String,
        val player: ExoPlayer,
        val renderersFactory: SyncOffsetRenderersFactory,
        val uri: String,
        var subtitleConfigurations: List<MediaItem.SubtitleConfiguration> = emptyList(),
        var mediaSession: MediaSession? = null,
        var sessionPlayer: ChannelSkipPlayer? = null,
        // Set from Dart's Now Playing updates while Background audio is on:
        // this player keeps going in the background, hosted by PlaybackService.
        var keepPlayingInBackground: Boolean = false,
        var nowPlayingMetadata: MediaMetadata? = null,
        var retriedHlsAsProgressive: Boolean = false,
        var lastVideoWidth: Int = 0,
        var lastVideoHeight: Int = 0,
        val matchDisplayRefreshRate: Boolean = false,
        var allowDisplayModeChanges: Boolean = true,
        var lastAppliedFps: Float = 0f,
        var resumeStallRunnable: Runnable? = null,
        var resumeStallBaselineFrames: Int = 0,
        var resumeStallBaselinePositionMs: Long = 0L,
        var resumeStallRechecksLeft: Int = 0,
        var resumeStallRecoveryCount: Int = 0,
        /** Last mime we opened with, so a format-mismatch can flip it. */
        var lastMimeType: String? = null,
        /** Seek to window start once READY ("Start from beginning"). */
        var pendingStartFromBeginning: Boolean = false,
    ) {
        /**
         * Format mismatch: HLS body parsed as TS (or vice versa) — flip the
         * mime once and re-prepare. Covers timeshift=1 where the server
         * returns HLS (buffer ready) or MPEG-TS (buffer cold) and a probe
         * timeout can guess wrong.
         */
        fun retryFlippedMime(error: PlaybackException): Boolean {
            if (retriedHlsAsProgressive || !error.looksLikeFormatMismatch()) {
                return false
            }

            retriedHlsAsProgressive = true
            val current = lastMimeType ?: MimeTypes.APPLICATION_M3U8
            val flipped = if (current == MimeTypes.APPLICATION_M3U8) {
                MimeTypes.VIDEO_MP2T
            } else {
                MimeTypes.APPLICATION_M3U8
            }
            lastMimeType = flipped
            val builder = MediaItem.Builder()
                .setUri(Uri.parse(uri))
                .setMimeType(flipped)
            if (subtitleConfigurations.isNotEmpty()) {
                builder.setSubtitleConfigurations(subtitleConfigurations)
            }
            nowPlayingMetadata?.let { builder.setMediaMetadata(it) }
            player.setMediaItem(builder.build(), player.currentPosition)
            return true
        }
    }

    @OptIn(UnstableApi::class)
    private fun buildMediaItem(
        uri: String,
        source: Map<*, *>,
        subtitleConfigurations: List<MediaItem.SubtitleConfiguration>,
    ): MediaItem {
        val isLive = source["isLive"] as? Boolean ?: false
        val livePrebufferSeconds = (source["livePrebufferSeconds"] as? Number)?.toInt() ?: 1
        val metadata = source["metadata"] as? Map<*, *>
        val containerExtension = metadata?.get("container_extension") as? String
        // Dart pre-open probe result for ?timeshift=1 (HLS window vs TS pipe).
        val probedMime = source["mimeType"] as? String

        val isTimeshiftParam = uri.contains("timeshift=1")
        val mimeType: String? = when {
            probedMime != null -> probedMime
            isTimeshiftParam -> null
            isLive -> MimeTypes.APPLICATION_M3U8
            containerExtension != null -> mimeTypeFromExtension(containerExtension)
            else -> null
        }

        val builder = MediaItem.Builder().setUri(Uri.parse(uri))
        if (mimeType != null) {
            builder.setMimeType(mimeType)
        }
        // Remember for retryFlippedMime if the probe guessed wrong.
        // (Set on the state after states[playerId] = state below via load().)
        // Live prebuffer: how far behind the live edge to stay (Kodi-style
        // "buffer before playback begins"). 0 = as close to live as possible
        // (lowest delay); N seconds = play Ns behind the edge for cushion.
        // Playback speed is pinned to 1.0 — LiveConfiguration's speed chase
        // (e.g. 1.0–1.02×) caused visible micro-stutters on jittery OTA HLS.
        if (isLive) {
            // Timeshift windows are re-segmented to short (~2 s) segments; a
            // 1 s target rides the live edge and stalls at every segment
            // boundary. Keep a few seconds of cushion — latency is irrelevant
            // here because the viewer can rewind anyway.
            val prebufferSeconds =
                if (isTimeshiftParam) maxOf(livePrebufferSeconds, 4) else livePrebufferSeconds
            val targetOffsetMs = prebufferSeconds.coerceIn(0, 30) * 1000L
            builder.setLiveConfiguration(
                MediaItem.LiveConfiguration.Builder()
                    .setTargetOffsetMs(targetOffsetMs)
                    .setMinOffsetMs(0L)
                    .setMaxOffsetMs((targetOffsetMs * 3).coerceAtLeast(5000L))
                    .setMinPlaybackSpeed(1.0f)
                    .setMaxPlaybackSpeed(1.0f)
                    .build(),
            )
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
        const val NOW_PLAYING_CHANNEL = "m3u_tv/now_playing"

        /** See `looksLikeAudioTimingFailure` in decoder_failure.dart. */
        const val AUDIO_DISCONTINUITY_ERROR_CODE = "AUDIO_TIMESTAMP_DISCONTINUITY"
    }
}

/**
 * The player a [MediaSession] drives. Passes everything through to ExoPlayer,
 * except that while [canChangeChannel] is set, the notification and lock
 * screen next/previous buttons change channel (via Dart) instead of seeking
 * within the single live item.
 */
@OptIn(UnstableApi::class)
private class ChannelSkipPlayer(
    player: ExoPlayer,
    private val onChangeChannel: (forward: Boolean) -> Unit,
) : ForwardingPlayer(player) {
    var canChangeChannel = false

    override fun getAvailableCommands(): Player.Commands {
        val commands = super.getAvailableCommands()
        if (!canChangeChannel) return commands
        return commands.buildUpon()
            .add(Player.COMMAND_SEEK_TO_NEXT)
            .add(Player.COMMAND_SEEK_TO_PREVIOUS)
            .build()
    }

    override fun isCommandAvailable(command: Int): Boolean = availableCommands.contains(command)

    override fun seekToNext() {
        if (canChangeChannel) onChangeChannel(true) else super.seekToNext()
    }

    override fun seekToPrevious() {
        if (canChangeChannel) onChangeChannel(false) else super.seekToPrevious()
    }

    // A channel picked in Android Auto while this player is up arrives here
    // as an item without a stream: Dart opens it (see CarMediaService).
    override fun setMediaItems(mediaItems: MutableList<MediaItem>, resetPosition: Boolean) {
        if (!mediaItems.isCarPick()) super.setMediaItems(mediaItems, resetPosition)
    }

    override fun setMediaItems(mediaItems: MutableList<MediaItem>, startIndex: Int, startPositionMs: Long) {
        if (!mediaItems.isCarPick()) super.setMediaItems(mediaItems, startIndex, startPositionMs)
    }

    override fun setMediaItems(mediaItems: MutableList<MediaItem>) {
        if (!mediaItems.isCarPick()) super.setMediaItems(mediaItems)
    }
}

/** Items Android Auto set that Dart plays elsewhere: no stream URI. */
internal fun List<MediaItem>.isCarPick(): Boolean =
    isNotEmpty() && all { it.localConfiguration == null }

internal fun PlaybackException.looksLikeFormatMismatch(): Boolean {
    // The useful detail is often nested several causes deep (e.g. an
    // ExoPlaybackException wrapping a ParserException), so walk the whole
    // chain rather than only the top-level message.
    var current: Throwable? = this
    while (current != null) {
        if (current is UnrecognizedInputFormatException) return true
        val message = current.message
        if (message != null &&
            (message.contains("Input does not start with the #EXTM3U header") ||
                message.contains("UnrecognizedInputFormatException"))
        ) {
            return true
        }
        current = current.cause
    }
    return false
}


private fun MethodCall.optionalStringArgument(name: String): String? {
    val args = arguments as? Map<*, *> ?: return null
    return args[name] as? String
}

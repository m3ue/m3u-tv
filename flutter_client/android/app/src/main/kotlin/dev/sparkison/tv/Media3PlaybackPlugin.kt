package dev.sparkison.tv

import android.content.Context
import android.net.Uri
import android.view.Surface
import androidx.annotation.OptIn
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.ProcessLifecycleOwner
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.TrackSelectionOverride
import androidx.media3.common.Tracks
import androidx.media3.common.MimeTypes
import androidx.media3.exoplayer.source.UnrecognizedInputFormatException
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.session.MediaSession
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry

class Media3PlaybackPlugin(
    private val context: Context,
    flutterEngine: FlutterEngine,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler, DefaultLifecycleObserver {
    private val methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
    private val eventChannel = EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
    private val textures = flutterEngine.renderer
    private var events: EventChannel.EventSink? = null
    private var playerState: PlayerState? = null
    private var mediaSession: MediaSession? = null

    init {
        methodChannel.setMethodCallHandler(this)
        eventChannel.setStreamHandler(this)
        ProcessLifecycleOwner.get().lifecycle.addObserver(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "probe" -> result.success(mapOf("backend" to "media3", "inAppOnly" to true, "externalIntents" to false))
                "load" -> {
                    load(call.argumentsMap())
                    result.success(mapOf("ok" to true, "textureId" to playerState?.textureId, "backend" to "media3"))
                }
                "play" -> {
                    requirePlayer().play()
                    result.success(null)
                }
                "pause" -> {
                    requirePlayer().pause()
                    result.success(null)
                }
                "seek" -> {
                    requirePlayer().seekTo(call.longArgument("positionMs"))
                    result.success(null)
                }
                "setAudioTrack" -> {
                    selectTrack(C.TRACK_TYPE_AUDIO, call.optionalStringArgument("trackId"))
                    result.success(null)
                }
                "setSubtitleTrack" -> {
                    selectTrack(C.TRACK_TYPE_TEXT, call.optionalStringArgument("trackId"))
                    result.success(null)
                }
                "stop" -> {
                    requirePlayer().stop()
                    emit("stopped")
                    result.success(null)
                }
                "dispose" -> {
                    releasePlayer()
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
        playerState?.player?.pause()
    }

    override fun onDestroy(owner: LifecycleOwner) {
        releasePlayer()
    }

    fun dispose() {
        ProcessLifecycleOwner.get().lifecycle.removeObserver(this)
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        releasePlayer()
    }

    @OptIn(UnstableApi::class)
    private fun load(arguments: Map<String, Any?>) {
        releasePlayer()

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

        // SurfaceProducer works correctly with Flutter's Impeller renderer.
        // SurfaceTexture has a known black-screen bug with Impeller on Android.
        val surfaceProducer = textures.createSurfaceProducer()
        surfaceProducer.setSize(1920, 1080)
        val surface = surfaceProducer.getSurface()

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
            .setAudioAttributes(audioAttributes, /* handleAudioFocus= */ true)
            .build()
        val state = PlayerState(
            player = player,
            surfaceProducer = surfaceProducer,
            surface = surface,
            textureId = surfaceProducer.id(),
            uri = uri,
        )
        playerState = state
        mediaSession = MediaSession.Builder(context, player).build()

        player.setVideoSurface(surface)
        player.addListener(Media3Listener())
        player.setMediaItem(buildMediaItem(uri, source), startPositionMs)
        emit("buffering", uri = uri, positionMs = startPositionMs, textureId = state.textureId)
        player.prepare()
        player.play()
    }

    private fun requirePlayer(): ExoPlayer = playerState?.player ?: throw IllegalStateException("No Media3 player is loaded")

    private fun releasePlayer() {
        val state = playerState ?: return
        mediaSession?.release()
        mediaSession = null
        state.player.release()
        state.surface.release()
        state.surfaceProducer.release()
        playerState = null
        emit("disposed")
    }

    private fun emit(
        type: String,
        uri: String? = null,
        positionMs: Long? = null,
        durationMs: Long? = null,
        textureId: Long? = null,
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
        val event = mutableMapOf<String, Any?>("type" to type, "backend" to "androidExoPlayer")
        if (uri != null) event["uri"] = uri
        if (positionMs != null) event["positionMs"] = positionMs
        if (durationMs != null) event["durationMs"] = durationMs
        if (textureId != null) event["textureId"] = textureId
        if (audioTracks != null) event["audioTracks"] = audioTracks
        if (subtitleTracks != null) event["subtitleTracks"] = subtitleTracks
        if (includeSelectedAudioTrackId) event["selectedAudioTrackId"] = selectedAudioTrackId
        if (includeSelectedSubtitleTrackId) event["selectedSubtitleTrackId"] = selectedSubtitleTrackId
        if (code != null) event["code"] = code
        if (message != null) event["message"] = message
        if (recoverable != null) event["recoverable"] = recoverable
        events?.success(event)
    }

    private fun selectTrack(trackType: Int, trackId: String?) {
        val player = requirePlayer()
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
        emitTrackSnapshot(player)
    }

    private fun emitTrackSnapshot(player: Player) {
        emit(
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

    private inner class Media3Listener : Player.Listener {
        override fun onVideoSizeChanged(videoSize: VideoSize) {
            val state = playerState ?: return
            if (videoSize.width > 0 && videoSize.height > 0) {
                state.surfaceProducer.setSize(videoSize.width, videoSize.height)
            }
        }

        override fun onTracksChanged(tracks: Tracks) {
            val player = playerState?.player ?: return
            emitTrackSnapshot(player)
        }

        override fun onPlaybackStateChanged(playbackState: Int) {
            val player = playerState?.player ?: return
            val dur = player.duration.takeIf { it != C.TIME_UNSET && it > 0 }
            when (playbackState) {
                Player.STATE_BUFFERING -> emit("buffering", positionMs = player.currentPosition)
                Player.STATE_READY -> emit(if (player.playWhenReady) "playing" else "ready", positionMs = player.currentPosition, durationMs = dur)
                Player.STATE_ENDED -> emit("end", positionMs = player.currentPosition, durationMs = dur)
                Player.STATE_IDLE -> Unit
            }
        }

        override fun onIsPlayingChanged(isPlaying: Boolean) {
            val player = playerState?.player ?: return
            val dur = player.duration.takeIf { it != C.TIME_UNSET && it > 0 }
            emit(if (isPlaying) "playing" else "ready", positionMs = player.currentPosition, durationMs = dur)
        }

        override fun onPlayerError(error: PlaybackException) {
            val state = playerState
            if (state != null && state.retryAsTs(error)) {
                emit("buffering", uri = state.uri, positionMs = state.player.currentPosition, textureId = state.textureId)
                state.player.prepare()
                return
            }

            emit(
                "error",
                positionMs = state?.player?.currentPosition,
                code = error.errorCodeName,
                message = error.message ?: "Media3 playback failed",
                recoverable = true,
            )
        }
    }

    private data class PlayerState(
        val player: ExoPlayer,
        val surfaceProducer: TextureRegistry.SurfaceProducer,
        val surface: Surface,
        val textureId: Long,
        val uri: String,
        var retriedHlsAsProgressive: Boolean = false,
    ) {
        fun retryAsTs(error: PlaybackException): Boolean {
            if (retriedHlsAsProgressive || !error.looksLikeFormatMismatch()) {
                return false
            }

            retriedHlsAsProgressive = true
            val mediaItem = MediaItem.Builder()
                .setUri(Uri.parse(uri))
                .setMimeType(MimeTypes.VIDEO_MP2T)
                .build()
            player.setMediaItem(mediaItem, player.currentPosition)
            return true
        }
    }

    private fun buildMediaItem(uri: String, source: Map<*, *>): MediaItem {
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

        return if (mimeType != null) {
            MediaItem.Builder().setUri(Uri.parse(uri)).setMimeType(mimeType).build()
        } else {
            MediaItem.fromUri(Uri.parse(uri))
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

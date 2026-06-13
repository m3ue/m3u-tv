package com.m3ue.m3utv

import android.content.Context
import android.net.Uri
import android.view.Surface
import androidx.annotation.OptIn
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.ProcessLifecycleOwner
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
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

        val textureEntry = textures.createSurfaceTexture()
        val surface = Surface(textureEntry.surfaceTexture())
        val httpDataSourceFactory = DefaultHttpDataSource.Factory()
            .setDefaultRequestProperties(headers)
        if (userAgent != null) {
            httpDataSourceFactory.setUserAgent(userAgent)
        }
        val player = ExoPlayer.Builder(context)
            .setMediaSourceFactory(DefaultMediaSourceFactory(context).setDataSourceFactory(httpDataSourceFactory))
            .build()
        val state = PlayerState(
            player = player,
            textureEntry = textureEntry,
            surface = surface,
            textureId = textureEntry.id(),
            uri = uri,
        )
        playerState = state
        mediaSession = MediaSession.Builder(context, player).build()

        player.setVideoSurface(surface)
        player.addListener(Media3Listener())
        player.setMediaItem(MediaItem.fromUri(Uri.parse(uri)), startPositionMs)
        emit("buffering", uri = uri, positionMs = startPositionMs, textureId = state.textureId)
        player.prepare()
    }

    private fun requirePlayer(): ExoPlayer = playerState?.player ?: throw IllegalStateException("No Media3 player is loaded")

    private fun releasePlayer() {
        val state = playerState ?: return
        mediaSession?.release()
        mediaSession = null
        state.player.release()
        state.surface.release()
        state.textureEntry.release()
        playerState = null
        emit("disposed")
    }

    private fun emit(
        type: String,
        uri: String? = null,
        positionMs: Long? = null,
        textureId: Long? = null,
        code: String? = null,
        message: String? = null,
        recoverable: Boolean? = null,
    ) {
        val event = mutableMapOf<String, Any?>("type" to type, "backend" to "androidExoPlayer")
        if (uri != null) event["uri"] = uri
        if (positionMs != null) event["positionMs"] = positionMs
        if (textureId != null) event["textureId"] = textureId
        if (code != null) event["code"] = code
        if (message != null) event["message"] = message
        if (recoverable != null) event["recoverable"] = recoverable
        events?.success(event)
    }

    private inner class Media3Listener : Player.Listener {
        override fun onPlaybackStateChanged(playbackState: Int) {
            val player = playerState?.player ?: return
            when (playbackState) {
                Player.STATE_BUFFERING -> emit("buffering", positionMs = player.currentPosition)
                Player.STATE_READY -> emit(if (player.playWhenReady) "playing" else "ready", positionMs = player.currentPosition)
                Player.STATE_ENDED -> emit("end", positionMs = player.currentPosition)
                Player.STATE_IDLE -> Unit
            }
        }

        override fun onIsPlayingChanged(isPlaying: Boolean) {
            val player = playerState?.player ?: return
            emit(if (isPlaying) "playing" else "ready", positionMs = player.currentPosition)
        }

        override fun onPlayerError(error: PlaybackException) {
            val state = playerState
            if (state != null && state.retryHlsAsProgressive(error)) {
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
        val textureEntry: TextureRegistry.SurfaceTextureEntry,
        val surface: Surface,
        val textureId: Long,
        val uri: String,
        var retriedHlsAsProgressive: Boolean = false,
    ) {
        fun retryHlsAsProgressive(error: PlaybackException): Boolean {
            if (retriedHlsAsProgressive || !error.looksLikeHlsManifestMismatch()) {
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

    private fun MethodCall.argumentsMap(): Map<String, Any?> = arguments as? Map<String, Any?> ?: emptyMap()

    private fun MethodCall.longArgument(name: String): Long = (argument<Number>(name))?.toLong() ?: 0L

    companion object {
        const val METHOD_CHANNEL = "m3u_tv/android_media3"
        const val EVENT_CHANNEL = "m3u_tv/android_media3/events"
    }
}

private fun PlaybackException.looksLikeHlsManifestMismatch(): Boolean {
    val text = listOfNotNull(message, cause?.message).joinToString("\n")
    return text.contains("Input does not start with the #EXTM3U header")
}

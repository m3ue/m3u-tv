package dev.sparkison.tv

import android.app.PendingIntent
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import androidx.annotation.OptIn
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.ForwardingPlayer
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.datasource.DefaultHttpDataSource
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.session.DefaultMediaNotificationProvider
import androidx.media3.session.LibraryResult
import androidx.media3.session.MediaLibraryService
import androidx.media3.session.MediaSession
import com.google.common.collect.ImmutableList
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture
import com.google.common.util.concurrent.SettableFuture
import io.flutter.plugin.common.MethodChannel

/**
 * Android Auto: the Favorites and Live TV lists, and an audio-only player
 * for the channel picked there. The lists and each channel's stream come
 * from Dart (`android_auto_bridge.dart`), which shares the phone's app state
 * through [AppFlutterEngine]: the car can start the app with no activity.
 *
 * One playback at a time, shared with the phone, as with CarPlay:
 * - a channel picked here plays in the phone's full-screen player while the
 *   app is in front or that player is going (Background audio), and on this
 *   service's own audio-only player otherwise
 *   (the full-screen player lives in a platform view, which needs the
 *   activity);
 * - opening the app while this player is going moves the channel to the
 *   full-screen player;
 * - anything starting on the phone stops this player, and while the
 *   full-screen player is up the car shows and controls it instead.
 *
 * The own player follows the full-screen player's live rules: next/previous
 * change channel within the list it was picked from, and a long pause
 * resumes at the live edge.
 */
@OptIn(UnstableApi::class)
class CarMediaService : MediaLibraryService() {
    private val handler = Handler(Looper.getMainLooper())
    private lateinit var bridge: MethodChannel
    private lateinit var httpDataSourceFactory: DefaultHttpDataSource.Factory
    private lateinit var player: ExoPlayer
    private lateinit var artworkLoader: LogoFramingBitmapLoader
    private lateinit var carPlayer: CarPlayer
    private var session: MediaLibrarySession? = null

    // The phone's full-screen player, while the car shows it.
    private var phonePlayer: Player? = null

    // The own player's channel, once asked to move to the phone: a resume
    // can come twice in a row, and must not open it twice.
    private var handedOffMediaId: String? = null

    // Live pause: as in the full-screen player (PlayerScreen._trackLivePause).
    private var pausedAtMs: Long? = null
    private var streamReleased = false
    private var retriedAsTs = false
    private var switchGeneration = 0

    private val releasePausedStream = Runnable {
        if (pausedAtMs == null) return@Runnable
        streamReleased = true
        player.stop()
        callDart("release", emptyMap(), attempts = 0) {}
    }

    private val refreshMetadata = object : Runnable {
        override fun run() {
            handler.postDelayed(this, METADATA_REFRESH_MS)
            val current = player.currentMediaItem ?: return
            callDart("metadata", mapOf("mediaId" to current.mediaId)) { result ->
                val entry = result as? Map<*, *> ?: return@callDart
                val item = player.currentMediaItem ?: return@callDart
                if (item.mediaId != current.mediaId) return@callDart
                val metadata = metadataFor(entry, forList = false)
                if (metadata == item.mediaMetadata) return@callDart
                // Same URI, so ExoPlayer swaps the metadata in place.
                player.replaceMediaItem(
                    player.currentMediaItemIndex,
                    item.buildUpon().setMediaMetadata(metadata).build(),
                )
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        val engine = AppFlutterEngine.attachCar(this)
        bridge = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
        artworkLoader = LogoFramingBitmapLoader(this)
        httpDataSourceFactory = DefaultHttpDataSource.Factory().setAllowCrossProtocolRedirects(true)
        player = ExoPlayer.Builder(this)
            .setMediaSourceFactory(
                DefaultMediaSourceFactory(this)
                    .setDataSourceFactory(DefaultDataSource.Factory(this, httpDataSourceFactory)),
            )
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setContentType(C.AUDIO_CONTENT_TYPE_MOVIE)
                    .setUsage(C.USAGE_MEDIA)
                    .build(),
                true,
            )
            // Pauses when the car disconnects rather than carrying on out of
            // the phone's speaker.
            .setHandleAudioBecomingNoisy(true)
            .setWakeMode(C.WAKE_MODE_NETWORK)
            .build()
        player.trackSelectionParameters = player.trackSelectionParameters.buildUpon()
            .setTrackTypeDisabled(C.TRACK_TYPE_VIDEO, true)
            .build()
        player.addListener(Listener())
        setMediaNotificationProvider(
            DefaultMediaNotificationProvider.Builder(this).build().apply {
                setSmallIcon(R.drawable.ic_notification)
            },
        )
        carPlayer = CarPlayer(player)
        session = MediaLibrarySession.Builder(this, carPlayer, LibraryCallback())
            .setId(SESSION_ID)
            .setSessionActivity(appLaunchIntent())
            .setBitmapLoader(artworkLoader)
            .build()
        handler.postDelayed(refreshMetadata, METADATA_REFRESH_MS)
        instance = this
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaLibrarySession? = session

    // The phone's player has its own notification (PlaybackService).
    override fun onUpdateNotification(session: MediaSession, startInForegroundRequired: Boolean) {
        if (phonePlayer == null) super.onUpdateNotification(session, startInForegroundRequired)
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        handler.removeCallbacksAndMessages(null)
        callDart("release", emptyMap(), attempts = 0) {}
        session?.release()
        session = null
        player.release()
        AppFlutterEngine.detachCar()
        super.onDestroy()
    }

    private fun appLaunchIntent(): PendingIntent = PendingIntent.getActivity(
        this,
        0,
        Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
        PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
    )

    /**
     * Calls Dart. Dart may still be starting (the car launched the app), so
     * an unanswered call is retried for a while before giving up with null.
     */
    private fun callDart(
        method: String,
        arguments: Map<String, Any?>,
        attempts: Int = DART_READY_ATTEMPTS,
        onResult: (Any?) -> Unit,
    ) {
        bridge.invokeMethod(method, arguments, object : MethodChannel.Result {
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
                handler.postDelayed(
                    { callDart(method, arguments, attempts - 1, onResult) },
                    DART_RETRY_DELAY_MS,
                )
            }
        })
    }

    private fun <T> dartFuture(
        method: String,
        arguments: Map<String, Any?>,
        convert: (Any?) -> T,
    ): ListenableFuture<T> {
        val future = SettableFuture.create<T>()
        callDart(method, arguments) { result ->
            try {
                future.set(convert(result))
            } catch (error: RuntimeException) {
                future.setException(error)
            }
        }
        return future
    }

    /**
     * [forList]: for the car's lists, which want a square logo (see
     * LogoArtworkProvider). Now Playing gets the original, framed by the
     * session's artwork loader so the wide card doesn't crop it.
     */
    private fun metadataFor(entry: Map<*, *>, forList: Boolean): MediaMetadata {
        val playable = entry["playable"] as? Boolean ?: false
        val logoUrl = (entry["artworkUri"] as? String)?.takeIf { it.isNotEmpty() }
        val artworkUri = when {
            logoUrl == null -> null
            forList -> LogoArtworkProvider.uriFor(this, logoUrl)
            else -> Uri.parse(logoUrl).also { if (playable) artworkLoader.markLogo(it) }
        }
        return MediaMetadata.Builder()
            .setTitle(entry["title"] as? String)
            .setArtist(entry["subtitle"] as? String)
            .setArtworkUri(artworkUri)
            .setIsBrowsable(!playable)
            .setIsPlayable(playable)
            .setMediaType(
                if (playable) MediaMetadata.MEDIA_TYPE_RADIO_STATION
                else MediaMetadata.MEDIA_TYPE_FOLDER_RADIO_STATIONS,
            )
            .build()
    }

    private fun browseItem(entry: Map<*, *>, forList: Boolean = true): MediaItem? {
        val id = entry["id"] as? String ?: return null
        return MediaItem.Builder()
            .setMediaId(id)
            .setMediaMetadata(metadataFor(entry, forList))
            .build()
    }

    /** A resolved channel, ready to play: its stream's headers go on the HTTP factory. */
    private fun playableItem(entry: Map<*, *>?): MediaItem? {
        if (entry == null) return null
        val uri = entry["uri"] as? String ?: return null
        val item = browseItem(entry, forList = false) ?: return null
        val headers = (entry["headers"] as? Map<*, *>)
            ?.mapNotNull { (key, value) ->
                if (key is String && value is String) key to value else null
            }
            ?.toMap()
            ?: emptyMap()
        httpDataSourceFactory.setDefaultRequestProperties(headers)
        httpDataSourceFactory.setUserAgent((entry["userAgent"] as? String)?.takeIf { it.isNotEmpty() })
        retriedAsTs = false
        // Xtream live URLs have no extension: hint HLS, as the phone's player
        // does, and fall back to MPEG-TS if that's wrong (see Listener).
        return item.buildUpon()
            .setUri(Uri.parse(uri))
            .setMimeType(MimeTypes.APPLICATION_M3U8)
            .build()
    }

    private fun playNow(item: MediaItem) {
        handedOffMediaId = null
        clearLivePause()
        player.setMediaItem(item)
        player.prepare()
        player.play()
    }

    private fun switchChannel(step: Int) {
        val current = player.currentMediaItem ?: return
        val generation = ++switchGeneration
        callDart("neighbour", mapOf("mediaId" to current.mediaId, "step" to step)) { result ->
            if (generation != switchGeneration) return@callDart
            playableItem(result as? Map<*, *>)?.let(::playNow)
        }
    }

    /** Opens the current channel again, as a fresh connection at the live edge. */
    private fun reopenAtLiveEdge() {
        val current = player.currentMediaItem ?: return
        val generation = ++switchGeneration
        callDart("resolve", mapOf("mediaId" to current.mediaId)) { result ->
            if (generation != switchGeneration) return@callDart
            playableItem(result as? Map<*, *>)?.let(::playNow)
        }
    }

    /** Stops the own player and lets go of its stream. */
    private fun stopOwnPlayback() {
        handedOffMediaId = null
        if (player.currentMediaItem == null) return
        switchGeneration++
        clearLivePause()
        player.stop()
        player.clearMediaItems()
        callDart("release", emptyMap(), attempts = 0) {}
    }

    private fun showPhone(player: Player) {
        if (phonePlayer === player) return
        stopOwnPlayback()
        phonePlayer = player
        session?.player = player
    }

    private fun hidePhone(player: Player) {
        if (phonePlayer !== player) return
        phonePlayer = null
        session?.player = carPlayer
    }

    /** The app came to the front: the own player's channel moves to the full-screen player. */
    private fun handOffToPhone() {
        if (phonePlayer != null) return
        val current = player.currentMediaItem ?: return
        if (handedOffMediaId == current.mediaId) return
        handedOffMediaId = current.mediaId
        // The own player keeps going until the full-screen player starts
        // (phonePlaybackStarted), so the audio carries on meanwhile.
        callDart("playOnPhone", mapOf("mediaId" to current.mediaId)) {}
    }

    private fun clearLivePause() {
        pausedAtMs = null
        streamReleased = false
        handler.removeCallbacks(releasePausedStream)
    }

    private inner class Listener : Player.Listener {
        override fun onPlayWhenReadyChanged(playWhenReady: Boolean, reason: Int) {
            if (playWhenReady) {
                clearLivePause()
            } else if (pausedAtMs == null && player.currentMediaItem != null) {
                pausedAtMs = SystemClock.elapsedRealtime()
                handler.postDelayed(releasePausedStream, LIVE_PAUSE_RELEASE_MS)
            }
        }

        override fun onPlayerError(error: PlaybackException) {
            val item = player.currentMediaItem ?: return
            if (retriedAsTs || !error.looksLikeFormatMismatch()) {
                Log.w(TAG, "Playback failed", error)
                return
            }
            retriedAsTs = true
            player.setMediaItem(item.buildUpon().setMimeType(MimeTypes.VIDEO_MP2T).build())
            player.prepare()
            player.play()
        }
    }

    /** Next/previous change channel; Play after a long pause reopens at the live edge. */
    private inner class CarPlayer(player: ExoPlayer) : ForwardingPlayer(player) {
        override fun getAvailableCommands(): Player.Commands {
            val commands = super.getAvailableCommands()
            if (currentMediaItem == null) return commands
            return commands.buildUpon()
                .add(Player.COMMAND_SEEK_TO_NEXT)
                .add(Player.COMMAND_SEEK_TO_PREVIOUS)
                .add(Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM)
                .add(Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM)
                .build()
        }

        override fun isCommandAvailable(command: Int): Boolean = availableCommands.contains(command)

        override fun seekToNext() = switchChannel(1)

        override fun seekToNextMediaItem() = switchChannel(1)

        override fun seekToPrevious() = switchChannel(-1)

        override fun seekToPreviousMediaItem() = switchChannel(-1)

        // A pick that Dart is playing on the phone (see onAddMediaItems).
        override fun setMediaItems(mediaItems: MutableList<MediaItem>, resetPosition: Boolean) {
            if (!mediaItems.isCarPick()) super.setMediaItems(mediaItems, resetPosition)
        }

        override fun setMediaItems(mediaItems: MutableList<MediaItem>, startIndex: Int, startPositionMs: Long) {
            if (!mediaItems.isCarPick()) super.setMediaItems(mediaItems, startIndex, startPositionMs)
        }

        override fun setMediaItems(mediaItems: MutableList<MediaItem>) {
            if (!mediaItems.isCarPick()) super.setMediaItems(mediaItems)
        }

        // A released stream reopens on Play (below), with a new session.
        override fun prepare() {
            if (!streamReleased) super.prepare()
        }

        override fun play() {
            val pausedAt = pausedAtMs
            if (pausedAt != null &&
                (streamReleased || SystemClock.elapsedRealtime() - pausedAt >= LIVE_RESUME_AT_EDGE_MS)
            ) {
                reopenAtLiveEdge()
                return
            }
            super.play()
        }
    }

    private inner class LibraryCallback : MediaLibrarySession.Callback {
        override fun onGetLibraryRoot(
            session: MediaLibrarySession,
            browser: MediaSession.ControllerInfo,
            params: LibraryParams?,
        ): ListenableFuture<LibraryResult<MediaItem>> {
            val root = MediaItem.Builder()
                .setMediaId(ROOT_ID)
                .setMediaMetadata(
                    MediaMetadata.Builder()
                        .setIsBrowsable(true)
                        .setIsPlayable(false)
                        .setMediaType(MediaMetadata.MEDIA_TYPE_FOLDER_MIXED)
                        .build(),
                )
                .build()
            return Futures.immediateFuture(LibraryResult.ofItem(root, params))
        }

        override fun onGetChildren(
            session: MediaLibrarySession,
            browser: MediaSession.ControllerInfo,
            parentId: String,
            page: Int,
            pageSize: Int,
            params: LibraryParams?,
        ): ListenableFuture<LibraryResult<ImmutableList<MediaItem>>> =
            dartFuture("children", mapOf("mediaId" to parentId)) { result ->
                val items = (result as? List<*>).orEmpty()
                    .mapNotNull { (it as? Map<*, *>)?.let(::browseItem) }
                val from = (page * pageSize).coerceIn(0, items.size)
                val to = (from + pageSize).coerceIn(from, items.size)
                LibraryResult.ofItemList(ImmutableList.copyOf(items.subList(from, to)), params)
            }

        override fun onGetItem(
            session: MediaLibrarySession,
            browser: MediaSession.ControllerInfo,
            mediaId: String,
        ): ListenableFuture<LibraryResult<MediaItem>> =
            dartFuture("item", mapOf("mediaId" to mediaId)) { result ->
                val item = (result as? Map<*, *>)?.let(::browseItem)
                if (item != null) {
                    LibraryResult.ofItem(item, null)
                } else {
                    LibraryResult.ofError(LibraryResult.RESULT_ERROR_BAD_VALUE)
                }
            }

        // A channel picked in the car: resolved to its stream by Dart.
        override fun onAddMediaItems(
            mediaSession: MediaSession,
            controller: MediaSession.ControllerInfo,
            mediaItems: MutableList<MediaItem>,
        ): ListenableFuture<MutableList<MediaItem>> {
            val requested = mediaItems.firstOrNull()?.mediaId
                ?: return Futures.immediateFuture(mutableListOf())
            switchGeneration++
            val future = SettableFuture.create<MutableList<MediaItem>>()
            val resolveHere = {
                callDart("resolve", mapOf("mediaId" to requested)) { result ->
                    clearLivePause()
                    future.set(listOfNotNull(playableItem(result as? Map<*, *>)).toMutableList())
                }
            }
            if (!MainActivity.isInForeground && phonePlayer == null) {
                resolveHere()
                return future
            }
            // The app is in front, or its full-screen player is still going
            // (Background audio): that player plays it, and the session's
            // player ignores the stream-less item (isCarPick).
            callDart("playOnPhone", mapOf("mediaId" to requested)) { result ->
                if (result == true) {
                    future.set(mutableListOf(mediaItems.first().buildUpon().setUri(null as Uri?).build()))
                } else {
                    resolveHere()
                }
            }
            return future
        }
    }

    companion object {
        private const val TAG = "CarMediaService"

        // Main thread only.
        private var instance: CarMediaService? = null

        /**
         * Something started playing on the phone: the own player stops. When
         * it's [replacement] for [previous] (a channel change) and the car was
         * showing [previous], it shows [replacement] instead.
         */
        fun phonePlaybackStarted(previous: Player?, replacement: Player?) {
            val service = instance ?: return
            service.stopOwnPlayback()
            if (previous != null && replacement != null && service.phonePlayer === previous) {
                service.phonePlayer = replacement
                service.session?.player = replacement
            }
        }

        /** The full-screen player is playing: the car shows and controls it. */
        fun showPhonePlayer(player: Player) {
            instance?.showPhone(player)
        }

        fun phonePlaybackStopped(player: Player) {
            instance?.hidePhone(player)
        }

        fun phoneCameToForeground() {
            instance?.handOffToPhone()
        }
        private const val CHANNEL = "m3u_tv/android_auto"
        private const val SESSION_ID = "android_auto"
        private const val ROOT_ID = "root"
        private const val DART_READY_ATTEMPTS = 120
        private const val DART_RETRY_DELAY_MS = 250L
        private const val METADATA_REFRESH_MS = 60_000L
        private const val LIVE_RESUME_AT_EDGE_MS = 30_000L
        private const val LIVE_PAUSE_RELEASE_MS = 5 * 60_000L
    }
}

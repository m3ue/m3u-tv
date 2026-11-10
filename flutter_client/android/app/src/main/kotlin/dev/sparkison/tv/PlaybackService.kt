package dev.sparkison.tv

import android.content.Context
import android.content.Intent
import android.util.Log
import androidx.annotation.OptIn
import androidx.media3.common.util.UnstableApi
import androidx.media3.session.DefaultMediaNotificationProvider
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService

/**
 * Keeps the full-screen player's [MediaSession] alive while the app is in the
 * background, with the system media notification and lock screen controls.
 *
 * Only used while the viewer has "Background audio" on (phones and tablets).
 * [Media3PlaybackPlugin] owns the session and the player; this service only
 * hosts the one it was handed via [attach], and Media3 moves it in and out of
 * the foreground as playback starts and stops.
 */
class PlaybackService : MediaSessionService() {
    @OptIn(UnstableApi::class)
    override fun onCreate() {
        super.onCreate()
        setMediaNotificationProvider(
            DefaultMediaNotificationProvider.Builder(this).build().apply {
                setSmallIcon(R.drawable.ic_notification)
            },
        )
        instance = this
        activeSession?.let { addSession(it) }
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession? = activeSession

    // Swiping the app away tears down the Flutter engine and its players, so
    // there is nothing left to keep playing.
    override fun onTaskRemoved(rootIntent: Intent?) {
        activeSession?.player?.pause()
        stopSelf()
    }

    override fun onDestroy() {
        if (instance === this) instance = null
        super.onDestroy()
    }

    companion object {
        private const val TAG = "PlaybackService"
        private var instance: PlaybackService? = null
        private var activeSession: MediaSession? = null

        /** Hosts [session], replacing whichever one was hosted before. */
        fun attach(context: Context, session: MediaSession) {
            if (activeSession === session) return
            activeSession?.let { previous -> instance?.removeSession(previous) }
            activeSession = session
            val service = instance
            if (service != null) {
                service.addSession(session)
            } else {
                // Normally called while the player is on screen, where the
                // app may start the service. From the background Android 8+
                // refuses; the session then stays outside the service (no
                // notification) rather than taking the player down.
                try {
                    context.startService(Intent(context, PlaybackService::class.java))
                } catch (error: IllegalStateException) {
                    Log.w(TAG, "PlaybackService not started from the background", error)
                }
            }
        }

        /** Stops hosting [session], if it's the hosted one. */
        fun detach(session: MediaSession) {
            if (activeSession !== session) return
            activeSession = null
            instance?.let { service ->
                service.removeSession(session)
                service.stopSelf()
            }
        }
    }
}

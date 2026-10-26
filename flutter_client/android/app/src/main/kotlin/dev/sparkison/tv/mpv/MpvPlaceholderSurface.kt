package dev.sparkison.tv.mpv

import android.os.Handler
import android.os.HandlerThread
import android.view.Surface
import androidx.annotation.OptIn
import androidx.media3.common.util.EGLSurfaceTexture
import androidx.media3.common.util.UnstableApi
import kotlinx.coroutines.android.asCoroutineDispatcher
import kotlinx.coroutines.withContext

/**
 * An offscreen `Surface` mpv's `wid` can point to whenever the real
 * `SurfaceView`'s surface is torn down (screen off, a resize, entering/
 * leaving picture-in-picture) instead of being left with no surface at all.
 *
 * mpv's hardware decoder (`hwdec=mediacodec-copy`) keeps posting output
 * buffers for as long as a file is loaded, whether or not anything is
 * attached to display them. With no surface at all, those buffers are never
 * claimed back, the decoder's output pool fills up, and it stalls waiting
 * for one to free up -- observed on real hardware as a frozen picture (audio
 * unaffected, since that pipeline is independent) that never recovers even
 * once a real surface reattaches, because by then the decoder session
 * itself is wedged, not just the display path.
 *
 * `EGLSurfaceTexture` (Media3's own utility, already a transitive dependency
 * via media3-exoplayer) runs a GL consumer on its own dedicated thread that
 * continuously drains whatever is posted to it, so the decoder never backs
 * up during the gap. Ported from the open-source Plezy player
 * (github.com/edde746/plezy, GPL-3.0)'s `mpv/MpvPlaceholderSurface.kt`,
 * which this file mirrors closely -- same mechanism, same underlying utility
 * class, adapted to this app's simpler single-surface mpv core (no OSD
 * plane, no GPU VO-target switching).
 */
internal class MpvPlaceholderSurface private constructor(
    val surface: Surface,
    private val handler: Handler,
    private val texture: EGLSurfaceTexture,
) : AutoCloseable {
    companion object {
        /** The caller must retain or close the result even if initialization is canceled. */
        @OptIn(UnstableApi::class)
        suspend fun create(): MpvPlaceholderSurface {
            val thread = HandlerThread("MpvPlaceholder").apply { start() }
            val handler = Handler(thread.looper)
            val texture = EGLSurfaceTexture(handler)
            return withContext(handler.asCoroutineDispatcher("MpvPlaceholder")) {
                try {
                    texture.init(EGLSurfaceTexture.SECURE_MODE_NONE)
                    MpvPlaceholderSurface(Surface(texture.surfaceTexture), handler, texture)
                } catch (error: Throwable) {
                    try {
                        texture.release()
                    } finally {
                        thread.quitSafely()
                    }
                    throw error
                }
            }
        }
    }

    /** Call only after mpv has stopped using this surface; destruction stays on the GL thread. */
    override fun close() {
        handler.post {
            try {
                surface.release()
                texture.release()
            } finally {
                handler.looper.quitSafely()
            }
        }
    }
}

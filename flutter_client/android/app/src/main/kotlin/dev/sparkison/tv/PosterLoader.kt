package dev.sparkison.tv

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.util.Log
import android.view.View
import android.widget.FrameLayout
import android.widget.ImageView
import java.net.HttpURLConnection
import java.net.URL
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Fetches and decodes a poster/backdrop image for the native loading
 * placeholder shared by [Media3PlaybackPlugin] and `mpv.MpvPlayerCore`.
 *
 * Exists so Android can show the same full-bleed poster behind the loading
 * spinner that the Flutter side already shows on desktop/iOS/web -- those
 * platforms render through a `Texture`, a normal Flutter-composited layer a
 * widget can safely be stacked over. Android instead renders into a real,
 * window-attached `SurfaceView` (required for HDR -- see
 * `Media3PlatformView.kt`'s header comment), which a Flutter-side overlay
 * can't safely cover-and-reveal (confirmed to leave video stuck black on a
 * real device during the EAC3 decoder-fallback work). Loading the poster
 * into a plain native `ImageView` that lives in the *same* native
 * `FrameLayout` as the `SurfaceView` sidesteps that entirely: native views
 * composite correctly together (the existing `subtitleView` already proves
 * this), it's only a Flutter-drawn layer stacked over a platform view that's
 * unsafe.
 */
object PosterLoader {
    private const val TAG = "PosterLoader"
    private const val CONNECT_TIMEOUT_MS = 8_000
    private const val READ_TIMEOUT_MS = 8_000

    /** Returns null on any failure (bad URL, network error, decode failure). */
    suspend fun load(url: String): Bitmap? = withContext(Dispatchers.IO) {
        var connection: HttpURLConnection? = null
        try {
            connection = (URL(url).openConnection() as HttpURLConnection).apply {
                connectTimeout = CONNECT_TIMEOUT_MS
                readTimeout = READ_TIMEOUT_MS
                instanceFollowRedirects = true
            }
            connection.inputStream.use { stream -> BitmapFactory.decodeStream(stream) }
        } catch (error: Exception) {
            Log.w(TAG, "Failed to load poster image: $url", error)
            null
        } finally {
            connection?.disconnect()
        }
    }
}

/**
 * The poster image + dark scrim shown over a `SurfaceView` while a stream
 * loads, as one native `FrameLayout` a platform view adds alongside its
 * `SurfaceView` (added last, so it paints on top during the loading
 * window). [show] starts (and cancels any previous) async fetch for [scope];
 * [hide] is called once the first real decoded frame renders, matching the
 * Flutter side's own `_awaitingFirstFrame` gating for the same backend.
 */
class PosterOverlay(context: Context, private val scope: CoroutineScope) {
    val view: FrameLayout = FrameLayout(context)
    private val imageView: ImageView = ImageView(context).apply {
        scaleType = ImageView.ScaleType.CENTER_CROP
    }
    private val scrimView: View = View(context).apply {
        // Matches the Flutter loading overlay's `Colors.black54` scrim.
        setBackgroundColor(Color.argb(0x8A, 0, 0, 0))
    }
    private var loadJob: Job? = null

    init {
        view.addView(imageView, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
        view.addView(scrimView, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
        view.visibility = View.GONE
    }

    /** [url] null clears any art and leaves the overlay hidden (nothing to show). */
    fun show(url: String?) {
        loadJob?.cancel()
        imageView.setImageDrawable(null)
        if (url == null) {
            view.visibility = View.GONE
            return
        }
        view.visibility = View.VISIBLE
        loadJob = scope.launch {
            val bitmap = PosterLoader.load(url)
            if (isActive && bitmap != null) {
                imageView.setImageBitmap(bitmap)
            }
        }
    }

    fun hide() {
        loadJob?.cancel()
        loadJob = null
        view.visibility = View.GONE
    }
}

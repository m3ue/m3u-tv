package dev.sparkison.tv

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.net.Uri
import androidx.annotation.OptIn
import androidx.media3.common.util.BitmapLoader
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DataSourceBitmapLoader
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture
import com.google.common.util.concurrent.MoreExecutors
import java.util.Collections

/**
 * The media session's artwork loader. The system media controls crop the
 * artwork to fill their wide card, which suits a VOD backdrop but cut most
 * channel logos down to a fragment. A channel logo (registered with
 * [markLogo] by [Media3PlaybackPlugin.updateNowPlaying]) is drawn centred on
 * a wider transparent canvas instead, inside the part every crop keeps: the
 * wide card trims the top and bottom, a square one the sides. Everything
 * else loads as is. Keyed by URI rather than read from the metadata, since
 * the session may ask for artwork by URI alone.
 */
@OptIn(UnstableApi::class)
internal class LogoFramingBitmapLoader(context: Context) : BitmapLoader {
    private val delegate = DataSourceBitmapLoader(context)
    private val logoUris: MutableSet<Uri> = Collections.synchronizedSet(mutableSetOf())

    fun markLogo(uri: Uri) {
        logoUris.add(uri)
    }

    override fun supportsMimeType(mimeType: String): Boolean = delegate.supportsMimeType(mimeType)

    override fun decodeBitmap(data: ByteArray): ListenableFuture<Bitmap> = delegate.decodeBitmap(data)

    override fun loadBitmap(uri: Uri): ListenableFuture<Bitmap> {
        val loaded = delegate.loadBitmap(uri)
        if (uri !in logoUris) return loaded
        return Futures.transform(loaded, ::frameLogo, MoreExecutors.directExecutor())
    }

    companion object {
        private const val CANVAS_WIDTH = 1024
        private const val CANVAS_HEIGHT = 576

        // The logo's box within the canvas: narrow enough to survive a square
        // crop (which keeps the middle ~56% of a 16:9 canvas), short enough
        // for the ~2:1 media card (which keeps ~90% of its height).
        private const val LOGO_WIDTH_FRACTION = 0.4f
        private const val LOGO_HEIGHT_FRACTION = 0.45f

        internal fun frameLogo(logo: Bitmap): Bitmap {
            val framed = Bitmap.createBitmap(CANVAS_WIDTH, CANVAS_HEIGHT, Bitmap.Config.ARGB_8888)
            if (logo.width <= 0 || logo.height <= 0) return framed
            val boxWidth = CANVAS_WIDTH * LOGO_WIDTH_FRACTION
            val boxHeight = CANVAS_HEIGHT * LOGO_HEIGHT_FRACTION
            val scale = minOf(boxWidth / logo.width, boxHeight / logo.height)
            val width = logo.width * scale
            val height = logo.height * scale
            val left = (CANVAS_WIDTH - width) / 2f
            val top = (CANVAS_HEIGHT - height) / 2f
            Canvas(framed).drawBitmap(
                logo,
                null,
                RectF(left, top, left + width, top + height),
                Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG),
            )
            return framed
        }
    }
}

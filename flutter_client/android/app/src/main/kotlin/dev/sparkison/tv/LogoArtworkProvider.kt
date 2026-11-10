package dev.sparkison.tv

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.util.Log
import java.io.File
import java.io.FileNotFoundException
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap

/**
 * Channel logos for Android Auto's lists. Those draw every icon as a square
 * and stretch whatever they're given to fill it, which squashed wide logos;
 * they also want artwork from a `content://` URI rather than the web. This
 * serves each logo centred on a transparent square, downloaded once and
 * cached.
 *
 * Only logos [CarMediaService] has listed are served, by an opaque key, so
 * other apps can't use this to fetch arbitrary URLs. The key map lives in
 * memory: after a restart the car asks for its lists again and gets fresh
 * keys.
 */
class LogoArtworkProvider : ContentProvider() {
    override fun onCreate(): Boolean = true

    override fun getType(uri: Uri): String = "image/png"

    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        val context = context ?: throw FileNotFoundException(uri.toString())
        val key = uri.lastPathSegment?.removeSuffix(".png") ?: throw FileNotFoundException(uri.toString())
        val url = logoUrls[key] ?: throw FileNotFoundException(uri.toString())
        val file = File(File(context.cacheDir, CACHE_DIR).apply { mkdirs() }, "$key.png")
        if (!file.exists()) {
            // Called on a binder thread, so the download can block.
            val logo = download(url) ?: throw FileNotFoundException(uri.toString())
            val square = squareLogo(logo)
            val temp = File(file.parentFile, "$key.tmp")
            temp.outputStream().use { square.compress(Bitmap.CompressFormat.PNG, 100, it) }
            if (!temp.renameTo(file)) temp.delete()
        }
        return ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
    }

    private fun download(url: String): Bitmap? {
        return try {
            val connection = URL(url).openConnection() as HttpURLConnection
            connection.connectTimeout = TIMEOUT_MS
            connection.readTimeout = TIMEOUT_MS
            connection.instanceFollowRedirects = true
            try {
                if (connection.responseCode >= 400) return null
                val bytes = connection.inputStream.use { it.readBytes() }
                val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
                BitmapFactory.decodeByteArray(bytes, 0, bytes.size, bounds)
                var sample = 1
                while (bounds.outWidth / (sample * 2) >= SIZE && bounds.outHeight / (sample * 2) >= SIZE) {
                    sample *= 2
                }
                BitmapFactory.decodeByteArray(
                    bytes,
                    0,
                    bytes.size,
                    BitmapFactory.Options().apply { inSampleSize = sample },
                )
            } finally {
                connection.disconnect()
            }
        } catch (error: IOException) {
            Log.w(TAG, "Logo download failed", error)
            null
        } catch (error: IllegalArgumentException) {
            Log.w(TAG, "Bad logo URL", error)
            null
        }
    }

    override fun query(
        uri: Uri,
        projection: Array<out String>?,
        selection: String?,
        selectionArgs: Array<out String>?,
        sortOrder: String?,
    ): Cursor? = null

    override fun insert(uri: Uri, values: ContentValues?): Uri? = null

    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0

    override fun update(
        uri: Uri,
        values: ContentValues?,
        selection: String?,
        selectionArgs: Array<out String>?,
    ): Int = 0

    companion object {
        private const val TAG = "LogoArtworkProvider"
        private const val CACHE_DIR = "car_logos"
        private const val SIZE = 256
        private const val TIMEOUT_MS = 10_000

        // Keeps the logo clear of the rounded corners the car draws.
        private const val INSET_FRACTION = 0.1f

        private val logoUrls = ConcurrentHashMap<String, String>()

        /** The square version of the logo at [url], served by this provider. */
        fun uriFor(context: Context, url: String): Uri {
            val key = MessageDigest.getInstance("SHA-256")
                .digest(url.toByteArray())
                .joinToString("") { "%02x".format(it) }
                .take(32)
            logoUrls[key] = url
            return Uri.Builder()
                .scheme("content")
                .authority("${context.packageName}.logos")
                .appendPath("$key.png")
                .build()
        }

        internal fun squareLogo(logo: Bitmap): Bitmap {
            val square = Bitmap.createBitmap(SIZE, SIZE, Bitmap.Config.ARGB_8888)
            if (logo.width <= 0 || logo.height <= 0) return square
            val box = SIZE * (1 - 2 * INSET_FRACTION)
            val scale = minOf(box / logo.width, box / logo.height)
            val width = logo.width * scale
            val height = logo.height * scale
            val left = (SIZE - width) / 2f
            val top = (SIZE - height) / 2f
            Canvas(square).drawBitmap(
                logo,
                null,
                RectF(left, top, left + width, top + height),
                Paint(Paint.FILTER_BITMAP_FLAG or Paint.ANTI_ALIAS_FLAG),
            )
            return square
        }
    }
}

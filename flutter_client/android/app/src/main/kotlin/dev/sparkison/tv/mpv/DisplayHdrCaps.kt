package dev.sparkison.tv.mpv

import android.content.Context
import android.os.Build
import android.util.Log
import android.view.Display
import android.view.WindowManager

/**
 * Whether the display this app is drawing to reports HDR support at all --
 * independent of [EglHdrCaps], which asks whether *mpv's GL path* can reach
 * it. Both must say yes before [MpvPlayerCore] engages a BT.2020 PQ surface.
 *
 * Trimmed from the open-source Plezy player (github.com/edde746/plezy,
 * GPL-3.0)'s `exoplayer/DoviBridge.kt` `displaySupportsHdr`/
 * `getDisplayHdrTypes` -- just the plain HDR check, none of its Dolby Vision
 * decoder probing.
 */
internal object DisplayHdrCaps {
    private const val TAG = "DisplayHdrCaps"

    fun supportsHdr(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N) return false
        val display = currentDisplay(context) ?: return false
        val hdrTypes = runCatching { hdrTypes(display) }.getOrElse { error ->
            Log.w(TAG, "Failed to query display HDR types", error)
            return false
        }
        return hdrTypes.isNotEmpty()
    }

    private fun currentDisplay(context: Context): Display? = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
        context.display
    } else {
        @Suppress("DEPRECATION")
        (context.getSystemService(Context.WINDOW_SERVICE) as? WindowManager)?.defaultDisplay
    }

    private fun hdrTypes(display: Display): IntArray {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            runCatching { display.mode.supportedHdrTypes }
                .onSuccess { return it }
                .onFailure { Log.w(TAG, "Failed to query mode HDR types; falling back to display HDR capabilities", it) }
        }
        @Suppress("DEPRECATION")
        return display.hdrCapabilities?.supportedHdrTypes ?: IntArray(0)
    }
}

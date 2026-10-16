package dev.sparkison.tv

import android.app.ActivityManager
import android.content.Context
import android.os.Process

/** Device memory signals shared by the engine memory caps and the mpv decoder queue. */
internal object DeviceMemoryClass {
    // Nominal 2GB boxes report slightly above 2 GiB after carve-outs.
    private const val LOW_MEM_THRESHOLD_BYTES = 2252L shl 20

    // Mirrors DevicePerformance's reduced-tier triple: a 32-bit process, the
    // platform low-RAM flag, or <= ~2.2 GiB.
    fun isLowRam(context: Context): Boolean {
        val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
        return !Process.is64Bit() ||
            activityManager?.isLowRamDevice == true ||
            totalMemBytes(context) <= LOW_MEM_THRESHOLD_BYTES
    }

    fun totalMemBytes(context: Context): Long {
        val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
        return ActivityManager.MemoryInfo().also { activityManager?.getMemoryInfo(it) }.totalMem
    }
}

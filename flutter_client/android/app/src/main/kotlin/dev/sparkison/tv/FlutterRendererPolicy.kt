package dev.sparkison.tv

internal enum class FlutterRenderer(
    val diagnosticName: String,
    val shellArgument: String?,
) {
    SKIA("Skia", "--enable-impeller=false"),
    IMPELLER("Impeller", null),
}

/**
 * Picks the Flutter UI renderer before the engine starts, from device
 * signals [MainActivity] reads in `getFlutterShellArgs`.
 *
 * Matches Plezy's device list (Skia on NVIDIA, Huawei/HONOR, and weaker
 * Android TVs), where Impeller has a history of rendering regressions. Note
 * the SHIELD low-memory kills that prompted adding this were ultimately
 * unsized full-resolution poster decodes (see ResilientMediaImage), not the
 * renderer.
 *
 * Ported from the open-source Plezy player's `FlutterRendererPolicy`
 * (github.com/edde746/plezy, GPL-3.0,
 * android/.../FlutterRendererPolicy.kt), minus its e-waste device list.
 */
internal object FlutterRendererPolicy {
    private const val ANDROID_12_API = 31

    fun select(
        manufacturer: String,
        isAndroidTv: Boolean,
        sdkInt: Int,
        supportsVulkan11: Boolean,
        is64Bit: Boolean,
    ): FlutterRenderer {
        if (manufacturer.equals("NVIDIA", ignoreCase = true)) return FlutterRenderer.SKIA
        if (manufacturer.equals("Huawei", ignoreCase = true) ||
            manufacturer.equals("HONOR", ignoreCase = true)
        ) {
            return FlutterRenderer.SKIA
        }
        if (!isAndroidTv) return FlutterRenderer.IMPELLER
        if (sdkInt < ANDROID_12_API || manufacturer.equals("Amazon", ignoreCase = true) || !supportsVulkan11) {
            return FlutterRenderer.SKIA
        }
        // 32-bit Android TV SoCs are the low-memory / low-throughput class.
        if (!is64Bit) return FlutterRenderer.SKIA
        return FlutterRenderer.IMPELLER
    }

    /**
     * The Dart old-gen heap size, always passed. FlutterLoader appends its own
     * defaults after the activity's shell args and the engine keeps the last
     * value of a flag, so a cap passed here alone never applied. The
     * manifest's `OldGenHeapSize` meta-data suppresses the loader's default,
     * which makes this the value that sticks: 256 MB on low-RAM boxes, where
     * the default of half of physical RAM drives LMK kills, and that same
     * default everywhere else (Plezy f7fa32e66). Skia's resource cache has no
     * such opt-out, so Dart caps it instead (`DevicePerformance`).
     */
    fun engineMemoryArgs(isLowRamClass: Boolean, totalMemBytes: Long): List<String> {
        val oldGenMegabytes = if (isLowRamClass) LOW_RAM_OLD_GEN_MB else (totalMemBytes / 1e6 / 2).toInt()
        return listOf("--old-gen-heap-size=$oldGenMegabytes")
    }

    private const val LOW_RAM_OLD_GEN_MB = 256
}

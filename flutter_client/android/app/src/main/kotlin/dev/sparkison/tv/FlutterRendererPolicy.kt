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
     * Engine memory-pool caps for low-RAM boxes, matching Plezy. Flutter's
     * `imageCache` budget only bounds decoded bitmaps: Skia's GPU resource
     * cache is sized from the surface area (hundreds of MB on a 4K-composited
     * TV) and the Dart old gen defaults to a large fraction of physical RAM.
     */
    fun engineMemoryArgs(
        renderer: FlutterRenderer,
        isLowRamClass: Boolean,
    ): List<String> {
        if (!isLowRamClass) return emptyList()
        val args = mutableListOf<String>()
        if (renderer == FlutterRenderer.SKIA) {
            args.add("--resource-cache-max-bytes-threshold=$LOW_RAM_RESOURCE_CACHE_BYTES")
        }
        args.add("--old-gen-heap-size=256")
        return args
    }

    private const val LOW_RAM_RESOURCE_CACHE_BYTES = 48L shl 20
}

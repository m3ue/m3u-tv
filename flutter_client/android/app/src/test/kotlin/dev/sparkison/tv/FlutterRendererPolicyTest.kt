package dev.sparkison.tv

import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.JUnit4

@RunWith(JUnit4::class)
class FlutterRendererPolicyTest {

    @Test
    fun nvidiaShieldUsesSkia() {
        val renderer = select(manufacturer = "NVIDIA")
        assertEquals(FlutterRenderer.SKIA, renderer)
        assertEquals("--enable-impeller=false", renderer.shellArgument)
    }

    @Test
    fun capable64BitTvKeepsImpeller() {
        assertEquals(FlutterRenderer.IMPELLER, select())
    }

    @Test
    fun unsupportedTvsUseSkia() {
        assertEquals(FlutterRenderer.SKIA, select(sdkInt = 30))
        assertEquals(FlutterRenderer.SKIA, select(supportsVulkan11 = false))
        assertEquals(FlutterRenderer.SKIA, select(manufacturer = "Amazon"))
        assertEquals(FlutterRenderer.SKIA, select(is64Bit = false))
    }

    @Test
    fun manufacturerDenylistAppliesOffTvToo() {
        assertEquals(FlutterRenderer.SKIA, select(manufacturer = "NVIDIA", isAndroidTv = false))
        assertEquals(FlutterRenderer.SKIA, select(manufacturer = "HONOR", isAndroidTv = false))
    }

    @Test
    fun ordinaryPhonesKeepImpeller() {
        assertEquals(
            FlutterRenderer.IMPELLER,
            select(manufacturer = "Samsung", isAndroidTv = false, sdkInt = 28, supportsVulkan11 = false, is64Bit = false),
        )
    }

    @Test
    fun lowRamClassCapsTheDartHeapAt256Megabytes() {
        assertEquals(
            listOf("--old-gen-heap-size=256"),
            FlutterRendererPolicy.engineMemoryArgs(isLowRamClass = true, totalMemBytes = 2_000_000_000L),
        )
    }

    @Test
    fun devicesAboveTheLowRamClassGetFlutterLoadersHalfOfRamDefault() {
        // The manifest's OldGenHeapSize meta-data turns FlutterLoader's own
        // default off, so this is passed explicitly for every other device.
        assertEquals(
            listOf("--old-gen-heap-size=1500"),
            FlutterRendererPolicy.engineMemoryArgs(isLowRamClass = false, totalMemBytes = 3_000_000_000L),
        )
    }

    private fun select(
        manufacturer: String = "Google",
        isAndroidTv: Boolean = true,
        sdkInt: Int = 31,
        supportsVulkan11: Boolean = true,
        is64Bit: Boolean = true,
    ): FlutterRenderer = FlutterRendererPolicy.select(
        manufacturer = manufacturer,
        isAndroidTv = isAndroidTv,
        sdkInt = sdkInt,
        supportsVulkan11 = supportsVulkan11,
        is64Bit = is64Bit,
    )
}

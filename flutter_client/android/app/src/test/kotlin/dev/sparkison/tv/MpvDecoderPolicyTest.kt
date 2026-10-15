package dev.sparkison.tv

import dev.sparkison.tv.mpv.MpvDecoderPolicy
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.JUnit4

@RunWith(JUnit4::class)
class MpvDecoderPolicyTest {

    @Test
    fun asyncDecodeStartsAtAndroid12() {
        assertEquals("ndk_codec=0,priority=0", MpvDecoderPolicy.decoderOptions(sdkInt = 30))
        assertEquals("ndk_codec=0,async=1,priority=0", MpvDecoderPolicy.decoderOptions(sdkInt = 31))
        assertEquals("ndk_codec=0,async=1,priority=0", MpvDecoderPolicy.decoderOptions(sdkInt = 35))
    }

    @Test
    fun lowRamBoxesGetASmallerQueue() {
        val regular = MpvDecoderPolicy.queueOptions(isLowRam = false).toMap()
        val lowRam = MpvDecoderPolicy.queueOptions(isLowRam = true).toMap()

        assertEquals("yes", regular["vd-queue-enable"])
        assertEquals("48MiB", regular["vd-queue-max-bytes"])
        assertEquals("yes", lowRam["vd-queue-enable"])
        assertEquals("16MiB", lowRam["vd-queue-max-bytes"])
        assertEquals(regular - "vd-queue-max-bytes", lowRam - "vd-queue-max-bytes")
    }
}

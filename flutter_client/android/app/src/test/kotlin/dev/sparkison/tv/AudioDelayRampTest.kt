package dev.sparkison.tv

import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.JUnit4

@RunWith(JUnit4::class)
class AudioDelayRampTest {

    @Test
    fun noDelayNeverShiftsThePosition() {
        assertEquals(0L, AudioDelayRamp.recoveryDurationUs(0L))
        assertEquals(0L, AudioDelayRamp.offsetUs(0L, 5_000_000L, 0L))
    }

    @Test
    fun rampLastsTwiceTheDelayWithA200MsFloor() {
        assertEquals(200_000L, AudioDelayRamp.recoveryDurationUs(50_000L))
        assertEquals(1_000_000L, AudioDelayRamp.recoveryDurationUs(-500_000L))
    }

    @Test
    fun offsetRampsInAfterASeekThenHoldsTheFullDelay() {
        val ramp = AudioDelayRamp.recoveryDurationUs(500_000L)
        assertEquals(0L, AudioDelayRamp.offsetUs(500_000L, 0L, ramp))
        assertEquals(250_000L, AudioDelayRamp.offsetUs(500_000L, ramp / 2, ramp))
        assertEquals(500_000L, AudioDelayRamp.offsetUs(500_000L, ramp, ramp))
        assertEquals(500_000L, AudioDelayRamp.offsetUs(500_000L, 10 * ramp, ramp))
    }

    @Test
    fun negativeDelaysRampTheSameWay() {
        val ramp = AudioDelayRamp.recoveryDurationUs(-300_000L)
        assertEquals(-150_000L, AudioDelayRamp.offsetUs(-300_000L, ramp / 2, ramp))
        assertEquals(-300_000L, AudioDelayRamp.offsetUs(-300_000L, ramp, ramp))
    }

    @Test
    fun aDelaySetMidPlaybackAppliesAtOnce() {
        // No ramp was armed (delay was zero at the last flush): full offset.
        assertEquals(120_000L, AudioDelayRamp.offsetUs(120_000L, 40_000_000L, 0L))
    }
}

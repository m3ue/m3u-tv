package dev.sparkison.tv

import dev.sparkison.tv.DisplayModeSelector.Mode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.JUnit4

@RunWith(JUnit4::class)
class DisplayModeSelectorTest {

    private val current = Mode(modeId = 1, refreshRate = 60.0, width = 3840, height = 2160)
    private val sixty = Mode(modeId = 1, refreshRate = 60.0, width = 3840, height = 2160)
    private val fifty = Mode(modeId = 2, refreshRate = 50.0, width = 3840, height = 2160)
    private val oneTwenty = Mode(modeId = 3, refreshRate = 120.0, width = 3840, height = 2160)
    private val twentyFour = Mode(modeId = 4, refreshRate = 24.0, width = 3840, height = 2160)
    private val otherResolution1080p60 = Mode(modeId = 5, refreshRate = 60.0, width = 1920, height = 1080)

    @Test
    fun picksExactMatchOverAMultiple() {
        val candidates = listOf(sixty, twentyFour, oneTwenty)
        val result = DisplayModeSelector.bestMode(candidates, currentModeId = 1, targetFps = 24.0)
        assertEquals(twentyFour, result)
    }

    @Test
    fun picksCleanIntegerMultipleForFractionalNtscRate() {
        // 23.976fps is a clean 5:5 on a 120Hz panel (5 * 23.976 = 119.88).
        val candidates = listOf(sixty, oneTwenty)
        val result = DisplayModeSelector.bestMode(candidates, currentModeId = 1, targetFps = 23.976)
        assertEquals(oneTwenty, result)
    }

    @Test
    fun prefersLargerMultipleWhenBothMatchCleanly() {
        // 24fps: 48Hz (2x) and 120Hz (5x) are both clean multiples -- prefer the larger.
        val fortyEight = Mode(modeId = 6, refreshRate = 48.0, width = 3840, height = 2160)
        val candidates = listOf(sixty, fortyEight, oneTwenty)
        val result = DisplayModeSelector.bestMode(candidates, currentModeId = 1, targetFps = 24.0)
        assertEquals(oneTwenty, result)
    }

    @Test
    fun returnsNullWhenNoCandidateIsWithinTolerance() {
        // 23.976fps against a 50/60Hz-only set: neither is an exact match nor a clean multiple.
        val candidates = listOf(sixty, fifty)
        val result = DisplayModeSelector.bestMode(candidates, currentModeId = 1, targetFps = 23.976)
        assertNull(result)
    }

    @Test
    fun ignoresModesAtADifferentResolution() {
        val candidates = listOf(sixty, otherResolution1080p60, twentyFour)
        val result = DisplayModeSelector.bestMode(candidates, currentModeId = 1, targetFps = 24.0)
        assertEquals(twentyFour, result)
    }

    @Test
    fun returnsNullForNonPositiveTargetFps() {
        assertNull(DisplayModeSelector.bestMode(listOf(sixty, twentyFour), currentModeId = 1, targetFps = 0.0))
        assertNull(DisplayModeSelector.bestMode(listOf(sixty, twentyFour), currentModeId = 1, targetFps = -24.0))
    }

    @Test
    fun prefersTheLargerMultipleOverASmallerErrorForNtscContent() {
        // 23.976fps: 48Hz misses 2x by 0.048, 120Hz misses 5x by 0.12. 48Hz
        // judders on a 120Hz panel; 120Hz is a clean 5:5.
        val fortyEight = Mode(modeId = 6, refreshRate = 48.0, width = 3840, height = 2160)
        val candidates = listOf(sixty, fortyEight, oneTwenty)
        val result = DisplayModeSelector.bestMode(candidates, currentModeId = 1, targetFps = 23.976)
        assertEquals(oneTwenty, result)
    }

    @Test
    fun keepsTheActiveModeWhenItIsAlreadyACleanMultiple() {
        // 30fps on a panel already at 60Hz: 120Hz is a larger multiple, but
        // switching to it would only cost an HDMI renegotiation.
        val result = DisplayModeSelector.bestMode(listOf(sixty, oneTwenty), currentModeId = 1, targetFps = 30.0)
        assertEquals(sixty, result)
    }

    @Test
    fun picksTheNearerExactRateOverTheActiveMode() {
        // 59.94fps: a panel on 60.000004Hz is within tolerance, but its true
        // 59.94Hz mode is the nearer exact rate.
        val activeSixty = Mode(modeId = 1, refreshRate = 60.000004, width = 3840, height = 2160)
        val ntscSixty = Mode(modeId = 7, refreshRate = 59.94, width = 3840, height = 2160)
        val result = DisplayModeSelector.bestMode(listOf(activeSixty, ntscSixty), currentModeId = 1, targetFps = 59.94)
        assertEquals(ntscSixty, result)
    }

    @Test
    fun returnsNullWhenCurrentModeIdIsNotAmongCandidates() {
        val result = DisplayModeSelector.bestMode(listOf(sixty, twentyFour), currentModeId = 99, targetFps = 24.0)
        assertNull(result)
    }

    @Test
    fun takesFiftyHertzOverTwentyFiveForBroadcastPal() {
        val twentyFive = Mode(modeId = 8, refreshRate = 25.0, width = 3840, height = 2160)
        val result = DisplayModeSelector.bestMode(listOf(sixty, fifty, twentyFive), currentModeId = 1, targetFps = 25.0)
        assertEquals(fifty, result)
    }

    @Test
    fun takesFiftyNineNinetyFourOverTheActiveSixtyForNtscVideo() {
        // 60.000 Hz is a 2x of 29.97 within tolerance but repeats a frame every
        // ~17 s; 59.94 Hz is the precise doubled rate, and beats 29.97 Hz.
        val ntscSixty = Mode(modeId = 7, refreshRate = 59.94006, width = 3840, height = 2160)
        val ntscThirty = Mode(modeId = 9, refreshRate = 29.97003, width = 3840, height = 2160)
        val result = DisplayModeSelector.bestMode(
            listOf(sixty, ntscSixty, ntscThirty),
            currentModeId = 1,
            targetFps = 30000.0 / 1001.0,
        )
        assertEquals(ntscSixty, result)
    }

    @Test
    fun keepsAPreciseOwnRateWhenNoPreciseMultipleExists() {
        // No 59.94 mode: 29.97 Hz is precise, 60.000 Hz is not.
        val ntscThirty = Mode(modeId = 9, refreshRate = 29.97003, width = 3840, height = 2160)
        val result = DisplayModeSelector.bestMode(listOf(sixty, ntscThirty), currentModeId = 1, targetFps = 30000.0 / 1001.0)
        assertEquals(ntscThirty, result)
    }

    @Test
    fun keepsAnActiveOneTwentyForThirtyFps() {
        val activeOneTwenty = Mode(modeId = 3, refreshRate = 120.0, width = 3840, height = 2160)
        val result = DisplayModeSelector.bestMode(listOf(sixty, activeOneTwenty), currentModeId = 3, targetFps = 30.0)
        assertEquals(activeOneTwenty, result)
    }

    @Test
    fun takesSixtyOverOneTwentyFromAnotherModeForThirtyFps() {
        val thirty = Mode(modeId = 10, refreshRate = 30.0, width = 3840, height = 2160)
        val result = DisplayModeSelector.bestMode(listOf(fifty, sixty, oneTwenty, thirty), currentModeId = 2, targetFps = 30.0)
        assertEquals(sixty, result)
    }

    @Test
    fun doesNotDoubleFilmRates() {
        val fortyEight = Mode(modeId = 6, refreshRate = 48.0, width = 3840, height = 2160)
        val result = DisplayModeSelector.bestMode(listOf(sixty, fortyEight, twentyFour), currentModeId = 1, targetFps = 24.0)
        assertEquals(twentyFour, result)
    }
}

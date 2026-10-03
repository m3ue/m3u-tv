package dev.sparkison.tv

import dev.sparkison.tv.FrameRateEstimator.Result
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.JUnit4
import kotlin.random.Random

@RunWith(JUnit4::class)
class FrameRateEstimatorTest {

    private val ntscFilm = 24_000.0 / 1001
    private val ntscVideo = 30_000.0 / 1001
    private val ntscVideoDouble = 60_000.0 / 1001

    @Test
    fun measuresNtscFilmFromMillisecondMatroskaTimestamps() {
        val (result, framesFed) = measure(matroskaTimestamps(ntscFilm))
        assertEquals(ntscFilm, (result as Result.Measured).fps, 1e-9)
        // Whole-millisecond timestamps need the full span before the fit is trusted.
        assertTrue(result.spanUs >= 2_000_000L)
        assertTrue(framesFed < 60)
    }

    @Test
    fun separatesTrueTwentyFourFromNtscFilm() {
        val (result, _) = measure(matroskaTimestamps(24.0))
        assertEquals(24.0, (result as Result.Measured).fps, 1e-9)
    }

    @Test
    fun separatesNtscVideoRatesFromTheirIntegerNeighbours() {
        assertEquals(ntscVideo, (measure(matroskaTimestamps(ntscVideo)).first as Result.Measured).fps, 1e-9)
        assertEquals(30.0, (measure(matroskaTimestamps(30.0)).first as Result.Measured).fps, 1e-9)
        assertEquals(ntscVideoDouble, (measure(matroskaTimestamps(ntscVideoDouble)).first as Result.Measured).fps, 1e-9)
        assertEquals(60.0, (measure(matroskaTimestamps(60.0)).first as Result.Measured).fps, 1e-9)
    }

    @Test
    fun separatesNtscFromIntegerRatesFromAnyResumePosition() {
        // The millisecond-rounding pattern depends on where in the file playback starts.
        for (rate in listOf(ntscFilm, 24.0, ntscVideo, 30.0, ntscVideoDouble, 60.0)) {
            for (startFrame in 0L until 200_000L step 1_237L) {
                val (result, _) = measure(matroskaTimestamps(rate, startFrame = startFrame))
                assertEquals("$rate from frame $startFrame", rate, (result as Result.Measured).fps, 1e-9)
            }
        }
    }

    @Test
    fun measuresWithinAFewFramesFromPreciseMpegTsTimestamps() {
        val (result, framesFed) = measure(mpegTsTimestamps(ntscFilm))
        assertEquals(ntscFilm, (result as Result.Measured).fps, 1e-9)
        assertEquals(12, framesFed)
    }

    @Test
    fun waitsTheFullSpanWhenEveryTimestampIsAWholeMillisecond() {
        // 25fps is exactly 40ms a frame even in a 90kHz stream, so it can't be
        // told apart from Matroska's millisecond rounding.
        val (result, framesFed) = measure(mpegTsTimestamps(25.0))
        assertEquals(25.0, (result as Result.Measured).fps, 1e-9)
        assertEquals(51, framesFed)
    }

    @Test
    fun measuresTheFieldRateOfDeinterlacedOutput() {
        val (result, _) = measure(mpegTsTimestamps(50.0))
        assertEquals(50.0, (result as Result.Measured).fps, 1e-9)
    }

    @Test
    fun countsDroppedFramesWithoutRestarting() {
        val timestamps = matroskaTimestamps(ntscFilm).filterIndexed { index, _ -> index != 5 && index != 20 && index != 21 }
        val (result, framesFed) = measure(timestamps)
        assertEquals(ntscFilm, (result as Result.Measured).fps, 1e-9)
        assertEquals(framesFed + 3L, result.frames)
    }

    @Test
    fun restartsTheMeasurementAfterASeek() {
        val beforeSeek = matroskaTimestamps(ntscFilm).take(30)
        val afterSeek = matroskaTimestamps(ntscFilm, startUs = 600_000_000L)
        val (result, framesFed) = measure(beforeSeek + afterSeek)
        assertEquals(ntscFilm, (result as Result.Measured).fps, 1e-9)
        assertTrue(result.frames < framesFed)
    }

    @Test
    fun keepsAnUncommonRateUnsnapped() {
        val (result, _) = measure(mpegTsTimestamps(15.0))
        assertEquals(15.0, (result as Result.Measured).fps, 0.01)
    }

    @Test
    fun reportsUnstableForVariableFrameRate() {
        val random = Random(314)
        val timestamps = generateSequence(0L) { it + random.nextLong(20_000L, 60_000L) }.take(600)
        val (result, _) = measure(timestamps)
        assertEquals(Result.Unstable, result)
    }

    private fun measure(timestamps: Sequence<Long>): Pair<Result, Int> {
        val estimator = FrameRateEstimator()
        var framesFed = 0
        for (timestamp in timestamps) {
            framesFed++
            val result = estimator.addFrame(timestamp)
            if (result != Result.Pending) return result to framesFed
        }
        return Result.Pending to framesFed
    }

    /** Matroska's default 1ms timestamp scale rounds every frame time to a whole millisecond. */
    private fun matroskaTimestamps(fps: Double, startUs: Long = 0L, startFrame: Long = 0L): Sequence<Long> =
        generateSequence(startFrame) { it + 1 }.take(600).map { startUs + Math.round(it * 1000.0 / fps) * 1000L }

    /** 90kHz PTS ticks, converted to microseconds the way Media3's TS extractor does (truncating). */
    private fun mpegTsTimestamps(fps: Double): Sequence<Long> =
        generateSequence(0L) { it + 1 }.take(600).map { Math.round(it * 90_000.0 / fps) * 1_000_000L / 90_000L }
}

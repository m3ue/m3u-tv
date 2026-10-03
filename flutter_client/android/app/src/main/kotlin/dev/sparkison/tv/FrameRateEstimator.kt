package dev.sparkison.tv

import kotlin.math.abs
import kotlin.math.roundToLong

/**
 * Measures a video's frame rate from the presentation timestamps of the
 * frames ExoPlayer renders, so Auto Frame Rate (issue #314) still has a rate
 * to match when the container doesn't declare one. In Media3 1.10.1 only the
 * progressive-MP4 extractor sets `Format.frameRate` -- Matroska, MPEG-TS and
 * fragmented MP4 never do, which left [Media3PlaybackPlugin] with nothing to
 * match for most VOD and all live TV. Plain JVM like [DisplayModeSelector],
 * so it's unit-testable; not thread-safe (fed from ExoPlayer's playback
 * thread only).
 *
 * The rate is a least-squares fit of timestamp against frame index rather
 * than span / frame count: Matroska timestamps are whole milliseconds
 * (23.976fps alternates 41ms and 42ms), and over [MILLISECOND_SPAN_US] the
 * fit separates 23.976 from 24 (0.1% apart) with a wide margin, where the
 * span alone can be a full millisecond off. A frame the renderer dropped
 * shows up as a whole-number gap and counts as that many frames; anything
 * else (a seek, variable frame rate) restarts the measurement, and a stream
 * that keeps restarting is reported [Result.Unstable].
 */
internal class FrameRateEstimator {
    sealed interface Result {
        /** Still sampling: keep feeding frames. */
        data object Pending : Result

        /** [fps], snapped to a standard rate when one is close, fitted over [frames] frames spanning [spanUs]. */
        data class Measured(val fps: Double, val frames: Long, val spanUs: Long) : Result

        /** The timestamps never settled into a steady cadence: stop feeding frames. */
        data object Unstable : Result
    }

    private val baseline = ArrayList<Long>(BASELINE_FRAMES)
    private var frameDurationUs = 0.0
    private var restarts = 0

    // The fit window: x = frame index (dropped frames included), y = timestamp
    // relative to the window's first frame.
    private var windowStartUs = 0L
    private var lastTimestampUs = 0L
    private var frameIndex = 0L
    private var samples = 0
    private var sumX = 0.0
    private var sumY = 0.0
    private var sumXY = 0.0
    private var sumXX = 0.0
    private var millisecondTimestamps = true

    fun addFrame(presentationTimeUs: Long): Result {
        if (restarts > MAX_RESTARTS) return Result.Unstable
        if (frameDurationUs == 0.0) return collectBaseline(presentationTimeUs)
        if (!extendWindow(presentationTimeUs)) return restart(presentationTimeUs)
        return measurement()
    }

    /**
     * The first [BASELINE_FRAMES] timestamps set the nominal frame duration
     * [extendWindow] measures gaps against -- their median delta, so a
     * dropped frame among them can't skew it -- then seed the fit window.
     */
    private fun collectBaseline(presentationTimeUs: Long): Result {
        if (baseline.isNotEmpty() && presentationTimeUs <= baseline.last()) return restart(presentationTimeUs)
        baseline.add(presentationTimeUs)
        if (baseline.size < BASELINE_FRAMES) return Result.Pending

        val deltas = baseline.zipWithNext { previous, next -> next - previous }.sorted()
        val median = deltas[deltas.size / 2].toDouble()
        if (median < MIN_FRAME_DURATION_US || median > MAX_FRAME_DURATION_US) return restart(presentationTimeUs)
        frameDurationUs = median
        val seed = baseline.toList()
        baseline.clear()
        startWindow(seed.first())
        for (timestamp in seed.drop(1)) {
            if (!extendWindow(timestamp)) return restart(timestamp)
        }
        return measurement()
    }

    private fun startWindow(timestampUs: Long) {
        windowStartUs = timestampUs
        lastTimestampUs = timestampUs
        frameIndex = 0
        samples = 0
        sumX = 0.0
        sumY = 0.0
        sumXY = 0.0
        sumXX = 0.0
        millisecondTimestamps = true
        addSample()
    }

    /** Adds [timestampUs] to the fit if it lands a whole number of frames after the last one, else returns false. */
    private fun extendWindow(timestampUs: Long): Boolean {
        val delta = timestampUs - lastTimestampUs
        if (delta <= 0) return false
        val frames = (delta / frameDurationUs).roundToLong()
        if (frames !in 1L..MAX_DROPPED_GAP_FRAMES) return false
        if (abs(delta - frames * frameDurationUs) > frameDurationUs * JITTER_TOLERANCE) return false
        frameIndex += frames
        lastTimestampUs = timestampUs
        if ((timestampUs - windowStartUs) % 1000L != 0L) millisecondTimestamps = false
        addSample()
        return true
    }

    private fun addSample() {
        val x = frameIndex.toDouble()
        val y = (lastTimestampUs - windowStartUs).toDouble()
        samples++
        sumX += x
        sumY += y
        sumXY += x * y
        sumXX += x * x
    }

    private fun measurement(): Result {
        val spanUs = lastTimestampUs - windowStartUs
        if (samples < MIN_FRAMES) return Result.Pending
        if (millisecondTimestamps && spanUs < MILLISECOND_SPAN_US) return Result.Pending
        val fittedFrameDurationUs = (samples * sumXY - sumX * sumY) / (samples * sumXX - sumX * sumX)
        return Result.Measured(snap(1_000_000.0 / fittedFrameDurationUs), frameIndex + 1, spanUs)
    }

    private fun restart(timestampUs: Long): Result {
        restarts++
        if (restarts > MAX_RESTARTS) return Result.Unstable
        frameDurationUs = 0.0
        baseline.clear()
        baseline.add(timestampUs)
        return Result.Pending
    }

    companion object {
        /** Timestamps (so one fewer delta) the nominal frame duration is taken from. */
        private const val BASELINE_FRAMES = 9

        /** Fewest frames a measurement is fitted over. */
        private const val MIN_FRAMES = 12

        /**
         * Span the fit needs when every timestamp is a whole millisecond (Matroska,
         * or a rate whose frame duration happens to be one, like 25fps): long
         * enough that the rounding can't blur rates 0.1% apart.
         */
        private const val MILLISECOND_SPAN_US = 2_000_000L

        /** Longest run of dropped frames still counted rather than treated as a seek. */
        private const val MAX_DROPPED_GAP_FRAMES = 4L

        /** How far, as a fraction of a frame, a timestamp may land off the cadence. */
        private const val JITTER_TOLERANCE = 0.25

        private const val MAX_RESTARTS = 5
        private const val MIN_FRAME_DURATION_US = 1_000_000.0 / 240
        private const val MAX_FRAME_DURATION_US = 1_000_000.0 / 10

        /** Relative distance within which a measured rate snaps to a standard one. */
        private const val SNAP_TOLERANCE = 0.0025

        private val STANDARD_RATES = doubleArrayOf(
            24_000.0 / 1001, 24.0, 25.0, 30_000.0 / 1001, 30.0, 48_000.0 / 1001, 48.0,
            50.0, 60_000.0 / 1001, 60.0, 100.0, 120_000.0 / 1001, 120.0,
        )

        private fun snap(fps: Double): Double {
            val nearest = STANDARD_RATES.minBy { abs(it - fps) }
            return if (abs(nearest - fps) <= nearest * SNAP_TOLERANCE) nearest else fps
        }
    }
}

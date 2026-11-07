package dev.sparkison.tv

import kotlin.math.abs

/**
 * Decides when audio timestamp jumps mean a title can't play on ExoPlayer.
 *
 * ExoPlayer treats `AudioSink.UnexpectedDiscontinuityException` as non-fatal, so on a file whose
 * audio timing it can't follow it never reports an error, but playback stops. How many jumps come
 * first varies: on SHIELD one AVI gave 4 at one position and exactly 3 at another, then silence
 * with the player frozen. So a short run counts, and so does any jump that playback doesn't get
 * past. One jump in a badly muxed file that keeps playing counts for neither. Fires once per
 * instance, as the player is replaced when it does.
 */
internal class AudioDiscontinuityPolicy(
    private val threshold: Int = DEFAULT_THRESHOLD,
    private val windowMs: Long = DEFAULT_WINDOW_MS,
) {
    private val recent = ArrayDeque<Long>()
    private var fired = false

    /** Records a jump at [nowMs]. True the one time the run becomes long enough to act on. */
    fun record(nowMs: Long): Boolean {
        if (fired) return false
        recent.addLast(nowMs)
        while (nowMs - recent.first() > windowMs) recent.removeFirst()
        fired = recent.size >= threshold
        return fired
    }

    /**
     * Whether playback is stuck [STALL_CHECK_MS] after a jump left it at [jumpPositionMs]. Absolute,
     * as a viewer seeking back is playback moving too. A paused player isn't stuck.
     */
    fun checkStalled(jumpPositionMs: Long, positionMs: Long, playWhenReady: Boolean): Boolean {
        if (fired || !playWhenReady) return false
        fired = abs(positionMs - jumpPositionMs) < MIN_PROGRESS_MS
        return fired
    }

    companion object {
        const val DEFAULT_THRESHOLD = 3
        const val DEFAULT_WINDOW_MS = 10_000L
        const val STALL_CHECK_MS = 5_000L
        const val MIN_PROGRESS_MS = 1_000L
    }
}

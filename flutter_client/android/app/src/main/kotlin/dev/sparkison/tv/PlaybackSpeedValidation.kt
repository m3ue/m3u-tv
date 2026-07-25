package dev.sparkison.tv

import androidx.media3.common.PlaybackParameters

/**
 * Validation seam for playback speed. Tested independently of Android framework classes.
 */
internal object PlaybackSpeedValidation {

    /**
     * Validates a speed value and returns a PlaybackParameters if valid.
     * Throws IllegalArgumentException for null, zero, negative, NaN, or infinite speeds.
     */
    fun validateAndCreatePlaybackParameters(speed: Float?): PlaybackParameters {
        if (speed == null || !speed.isFinite() || speed <= 0f) {
            throw IllegalArgumentException("Playback speed must be finite and greater than zero")
        }
        return PlaybackParameters(speed)
    }
}
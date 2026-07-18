package dev.sparkison.tv

import androidx.media3.common.PlaybackParameters
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertThrows
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.JUnit4

@RunWith(JUnit4::class)
class PlaybackSpeedValidationTest {

    @Test
    fun validSpeedCreatesPlaybackParametersWithCorrectSpeed() {
        val result = PlaybackSpeedValidation.validateAndCreatePlaybackParameters(1.5f)
        assertNotNull(result)
        assertEquals(1.5f, result.speed, 0.001f)
    }

    @Test
    fun speedOf1CreatesPlaybackParameters() {
        val result = PlaybackSpeedValidation.validateAndCreatePlaybackParameters(1.0f)
        assertNotNull(result)
        assertEquals(1.0f, result.speed, 0.001f)
    }

    @Test
    fun speedGreaterThan1CreatesPlaybackParameters() {
        val result = PlaybackSpeedValidation.validateAndCreatePlaybackParameters(2.0f)
        assertNotNull(result)
        assertEquals(2.0f, result.speed, 0.001f)
    }

    @Test
    fun zeroSpeedThrowsIllegalArgumentException() {
        val exception = assertThrows(IllegalArgumentException::class.java) {
            PlaybackSpeedValidation.validateAndCreatePlaybackParameters(0.0f)
        }
        assertEquals("Playback speed must be finite and greater than zero", exception.message)
    }

    @Test
    fun negativeSpeedThrowsIllegalArgumentException() {
        val exception = assertThrows(IllegalArgumentException::class.java) {
            PlaybackSpeedValidation.validateAndCreatePlaybackParameters(-1.0f)
        }
        assertEquals("Playback speed must be finite and greater than zero", exception.message)
    }

    @Test
    fun nanSpeedThrowsIllegalArgumentException() {
        val exception = assertThrows(IllegalArgumentException::class.java) {
            PlaybackSpeedValidation.validateAndCreatePlaybackParameters(Float.NaN)
        }
        assertEquals("Playback speed must be finite and greater than zero", exception.message)
    }

    @Test
    fun positiveInfinitySpeedThrowsIllegalArgumentException() {
        val exception = assertThrows(IllegalArgumentException::class.java) {
            PlaybackSpeedValidation.validateAndCreatePlaybackParameters(Float.POSITIVE_INFINITY)
        }
        assertEquals("Playback speed must be finite and greater than zero", exception.message)
    }

    @Test
    fun negativeInfinitySpeedThrowsIllegalArgumentException() {
        val exception = assertThrows(IllegalArgumentException::class.java) {
            PlaybackSpeedValidation.validateAndCreatePlaybackParameters(Float.NEGATIVE_INFINITY)
        }
        assertEquals("Playback speed must be finite and greater than zero", exception.message)
    }

    @Test
    fun nullSpeedThrowsIllegalArgumentException() {
        val exception = assertThrows(IllegalArgumentException::class.java) {
            PlaybackSpeedValidation.validateAndCreatePlaybackParameters(null)
        }
        assertEquals("Playback speed must be finite and greater than zero", exception.message)
    }
}
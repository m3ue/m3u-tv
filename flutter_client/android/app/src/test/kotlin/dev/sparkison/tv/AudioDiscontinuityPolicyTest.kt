package dev.sparkison.tv

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.JUnit4

@RunWith(JUnit4::class)
class AudioDiscontinuityPolicyTest {

    @Test
    fun firesOnTheObservedRunsOfJumps() {
        // SHIELD log, resuming at about 271 s: 3 jumps within 184 ms, then silence.
        val policy = AudioDiscontinuityPolicy()
        assertFalse(policy.record(0L))
        assertFalse(policy.record(0L))
        assertTrue(policy.record(184L))
    }

    @Test
    fun occasionalJumpsNeverFire() {
        val policy = AudioDiscontinuityPolicy()
        repeat(50) { assertFalse(policy.record(it * 6_000L)) }
    }

    @Test
    fun jumpsOutsideTheWindowDoNotCount() {
        val policy = AudioDiscontinuityPolicy()
        assertFalse(policy.record(0L))
        assertFalse(policy.record(1_000L))
        assertFalse(policy.record(20_000L))
        assertFalse(policy.record(21_000L))
        assertTrue(policy.record(22_000L))
    }

    @Test
    fun aJumpPlaybackDoesNotGetPastIsAStall() {
        val policy = AudioDiscontinuityPolicy()
        policy.record(0L)
        assertTrue(policy.checkStalled(jumpPositionMs = 271_000L, positionMs = 271_200L, playWhenReady = true))
    }

    @Test
    fun playbackThatKeepsMovingIsNotAStall() {
        val policy = AudioDiscontinuityPolicy()
        policy.record(0L)
        assertFalse(policy.checkStalled(jumpPositionMs = 271_000L, positionMs = 276_000L, playWhenReady = true))
    }

    @Test
    fun seekingBackIsNotAStall() {
        val policy = AudioDiscontinuityPolicy()
        policy.record(0L)
        assertFalse(policy.checkStalled(jumpPositionMs = 271_000L, positionMs = 100_000L, playWhenReady = true))
    }

    @Test
    fun aPausedPlayerIsNotAStall() {
        val policy = AudioDiscontinuityPolicy()
        policy.record(0L)
        assertFalse(policy.checkStalled(jumpPositionMs = 271_000L, positionMs = 271_000L, playWhenReady = false))
    }

    @Test
    fun aStallFiresOnlyOnce() {
        val policy = AudioDiscontinuityPolicy()
        assertTrue(policy.checkStalled(jumpPositionMs = 0L, positionMs = 0L, playWhenReady = true))
        assertFalse(policy.checkStalled(jumpPositionMs = 0L, positionMs = 0L, playWhenReady = true))
        assertFalse(policy.record(100L))
    }

    @Test
    fun firesOnlyOnce() {
        val policy = AudioDiscontinuityPolicy()
        val results = List(10) { policy.record(it * 100L) }
        assertEquals(1, results.count { it })
    }
}

package dev.sparkison.tv

import androidx.media3.extractor.ts.TsExtractor
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.runners.JUnit4

@RunWith(JUnit4::class)
class AtscCaptionPolicyTest {

    @Test
    fun mpeg2VideoGetsCaptionFallback() {
        assertTrue(AtscCaptionPolicy.usesCaptionFallback(TsExtractor.TS_STREAM_TYPE_H262))
        assertTrue(AtscCaptionPolicy.usesCaptionFallback(TsExtractor.TS_STREAM_TYPE_DC2_H262))
    }

    @Test
    fun otherStreamTypesKeepMedia3Defaults() {
        assertFalse(AtscCaptionPolicy.usesCaptionFallback(TsExtractor.TS_STREAM_TYPE_H264))
        assertFalse(AtscCaptionPolicy.usesCaptionFallback(TsExtractor.TS_STREAM_TYPE_H265))
        assertFalse(AtscCaptionPolicy.usesCaptionFallback(TsExtractor.TS_STREAM_TYPE_AC3))
    }
}

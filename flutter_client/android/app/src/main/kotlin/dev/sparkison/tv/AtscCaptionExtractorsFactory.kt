package dev.sparkison.tv

import android.net.Uri
import android.util.SparseArray
import androidx.annotation.OptIn
import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.TimestampAdjuster
import androidx.media3.common.util.UnstableApi
import androidx.media3.extractor.DefaultExtractorsFactory
import androidx.media3.extractor.Extractor
import androidx.media3.extractor.ExtractorsFactory
import androidx.media3.extractor.text.DefaultSubtitleParserFactory
import androidx.media3.extractor.text.SubtitleParser
import androidx.media3.extractor.ts.DefaultTsPayloadReaderFactory
import androidx.media3.extractor.ts.TsExtractor
import androidx.media3.extractor.ts.TsPayloadReader

/**
 * [DefaultExtractorsFactory] with one change: MPEG-2 video PIDs in a transport
 * stream get a fallback list of in-band closed-caption formats.
 *
 * Media3 only creates CEA-608/708 tracks for a video PID when the PMT carries
 * the ATSC caption service descriptor (tag 0x86); without it the fallback list
 * is empty and no caption track exists, even though A/53 caption data is in
 * every frame. Some OTA broadcasters omit that descriptor, so their channels
 * never show captions.
 *
 * The fallback is deliberately limited to MPEG-2 video (ATSC 1.0 broadcast).
 * `DefaultExtractorsFactory.setTsSubtitleFormats` would apply it to H.264/HEVC
 * too, which adds caption tracks to every IPTV TS stream whether or not it
 * carries captions. When the 0x86 descriptor is present it still wins, so
 * channels that already showed captions are unchanged.
 *
 * Every other extractor, and the TsExtractor settings, are exactly what
 * [DefaultExtractorsFactory] would build (Media3 1.10.1); the subtitle parser
 * and text transcoding settings that DefaultMediaSourceFactory pushes in are
 * forwarded to both.
 */
@OptIn(UnstableApi::class)
class AtscCaptionExtractorsFactory : ExtractorsFactory {
    private val delegate = DefaultExtractorsFactory()
    private var subtitleParserFactory: SubtitleParser.Factory = DefaultSubtitleParserFactory()
    private var textTrackTranscodingEnabled = true

    @Synchronized
    override fun experimentalSetTextTrackTranscodingEnabled(
        textTrackTranscodingEnabled: Boolean,
    ): ExtractorsFactory {
        this.textTrackTranscodingEnabled = textTrackTranscodingEnabled
        delegate.experimentalSetTextTrackTranscodingEnabled(textTrackTranscodingEnabled)
        return this
    }

    @Synchronized
    override fun setSubtitleParserFactory(
        subtitleParserFactory: SubtitleParser.Factory,
    ): ExtractorsFactory {
        this.subtitleParserFactory = subtitleParserFactory
        delegate.setSubtitleParserFactory(subtitleParserFactory)
        return this
    }

    @Synchronized
    override fun experimentalSetCodecsToParseWithinGopSampleDependencies(
        codecsToParseWithinGopSampleDependencies: Int,
    ): ExtractorsFactory {
        delegate.experimentalSetCodecsToParseWithinGopSampleDependencies(
            codecsToParseWithinGopSampleDependencies,
        )
        return this
    }

    @Synchronized
    override fun createExtractors(): Array<Extractor> =
        replaceTsExtractors(delegate.createExtractors())

    @Synchronized
    override fun createExtractors(
        uri: Uri,
        responseHeaders: Map<String, List<String>>,
    ): Array<Extractor> = replaceTsExtractors(delegate.createExtractors(uri, responseHeaders))

    private fun replaceTsExtractors(extractors: Array<Extractor>): Array<Extractor> =
        Array(extractors.size) { index ->
            val extractor = extractors[index]
            if (extractor is TsExtractor) buildTsExtractor() else extractor
        }

    // Mirrors DefaultExtractorsFactory's TsExtractor construction with its
    // default mode, flags and timestamp search size.
    private fun buildTsExtractor(): TsExtractor = TsExtractor(
        TsExtractor.MODE_SINGLE_PMT,
        if (textTrackTranscodingEnabled) 0 else TsExtractor.FLAG_EMIT_RAW_SUBTITLE_DATA,
        subtitleParserFactory,
        TimestampAdjuster(0),
        AtscCaptionPayloadReaderFactory(),
        TsExtractor.DEFAULT_TIMESTAMP_SEARCH_BYTES,
    )
}

/**
 * Hands MPEG-2 video PIDs to a [DefaultTsPayloadReaderFactory] that has the
 * ATSC caption fallback formats, and every other PID to a plain one.
 */
@OptIn(UnstableApi::class)
private class AtscCaptionPayloadReaderFactory : TsPayloadReader.Factory {
    private val plain = DefaultTsPayloadReaderFactory(0)
    private val withCaptionFallback = DefaultTsPayloadReaderFactory(0, ATSC_CAPTION_FALLBACK_FORMATS)

    override fun createInitialPayloadReaders(): SparseArray<TsPayloadReader> =
        plain.createInitialPayloadReaders()

    override fun createPayloadReader(
        streamType: Int,
        esInfo: TsPayloadReader.EsInfo,
    ): TsPayloadReader? = if (AtscCaptionPolicy.usesCaptionFallback(streamType)) {
        withCaptionFallback.createPayloadReader(streamType, esInfo)
    } else {
        plain.createPayloadReader(streamType, esInfo)
    }
}

internal object AtscCaptionPolicy {
    /** ATSC 1.0 broadcast video; H.264/HEVC TS streams keep Media3's defaults. */
    @OptIn(UnstableApi::class)
    fun usesCaptionFallback(streamType: Int): Boolean =
        streamType == TsExtractor.TS_STREAM_TYPE_H262 ||
            streamType == TsExtractor.TS_STREAM_TYPE_DC2_H262
}

// CC1 and CEA-708 service 1 are the primary caption services every ATSC
// station carries. Labeled so the track picker can tell them apart; no
// language, because the stream does not declare one.
@OptIn(UnstableApi::class)
private val ATSC_CAPTION_FALLBACK_FORMATS: List<Format> = listOf(
    Format.Builder()
        .setSampleMimeType(MimeTypes.APPLICATION_CEA608)
        .setAccessibilityChannel(1)
        .setLabel("CC1")
        .build(),
    Format.Builder()
        .setSampleMimeType(MimeTypes.APPLICATION_CEA708)
        .setAccessibilityChannel(1)
        .setLabel("CC (708)")
        .build(),
)

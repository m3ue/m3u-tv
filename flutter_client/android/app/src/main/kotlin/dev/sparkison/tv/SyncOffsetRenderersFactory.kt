package dev.sparkison.tv

import android.content.Context
import android.os.Looper
import androidx.annotation.OptIn
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.Renderer
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.audio.ForwardingAudioSink
import androidx.media3.exoplayer.text.TextOutput
import java.nio.ByteBuffer
import java.util.concurrent.atomic.AtomicLong
import kotlin.math.abs

/**
 * ExoPlayer's renderers, as [DefaultRenderersFactory] builds them, plus live
 * audio and subtitle sync offsets (the player's "Audio sync" / "Subtitle
 * sync"). Ported from Plezy's PlezyRenderersFactory (github.com/edde746/plezy,
 * GPL-3.0): ExoPlayer has no audio-delay setting, so the audio sink reports
 * its position shifted by the offset and the video renderer, which follows
 * that clock, does the rest. With both offsets at zero nothing changes.
 *
 * Positive values play the audio or subtitles later, the same as mpv's
 * `audio-delay`/`sub-delay`.
 */
@OptIn(UnstableApi::class)
class SyncOffsetRenderersFactory(context: Context) : DefaultRenderersFactory(context) {
    val audioDelayUs = AtomicLong(0L)
    val subtitleDelayUs = AtomicLong(0L)

    override fun buildAudioSink(
        context: Context,
        enableFloatOutput: Boolean,
        enableAudioOutputPlaybackParams: Boolean,
    ): AudioSink? {
        val sink = super.buildAudioSink(context, enableFloatOutput, enableAudioOutputPlaybackParams)
            ?: return null
        return AudioDelaySink(sink, audioDelayUs)
    }

    override fun buildTextRenderers(
        context: Context,
        output: TextOutput,
        outputLooper: Looper,
        extensionRendererMode: Int,
        out: ArrayList<Renderer>,
    ) {
        val firstTextRenderer = out.size
        super.buildTextRenderers(context, output, outputLooper, extensionRendererMode, out)
        for (index in firstTextRenderer until out.size) {
            out[index] = SubtitleDelayRenderer(out[index], subtitleDelayUs)
        }
    }
}

/**
 * The offset to add to the audio position, ramped in over [recoveryDurationUs]
 * after a seek or flush so the video renderer isn't asked to drop (or hold)
 * the whole offset's worth of frames at once. Plezy's numbers.
 */
internal object AudioDelayRamp {
    fun recoveryDurationUs(delayUs: Long): Long =
        if (delayUs == 0L) 0L else maxOf(200_000L, 2L * abs(delayUs))

    fun offsetUs(delayUs: Long, elapsedUs: Long, recoveryDurationUs: Long): Long {
        if (delayUs == 0L) return 0L
        if (recoveryDurationUs <= 0L || elapsedUs >= recoveryDurationUs) return delayUs
        if (elapsedUs <= 0L) return 0L
        return (delayUs * elapsedUs) / recoveryDurationUs
    }
}

@OptIn(UnstableApi::class)
internal class AudioDelaySink(
    sink: AudioSink,
    private val audioDelayUs: AtomicLong,
) : ForwardingAudioSink(sink) {
    private var startMediaTimeUs = Long.MIN_VALUE
    private var recoveryDurationUs = 0L

    override fun handleBuffer(
        buffer: ByteBuffer,
        presentationTimeUs: Long,
        encodedAccessUnitCount: Int,
    ): Boolean {
        if (startMediaTimeUs == Long.MIN_VALUE) {
            startMediaTimeUs = presentationTimeUs
            recoveryDurationUs = AudioDelayRamp.recoveryDurationUs(audioDelayUs.get())
        }
        return super.handleBuffer(buffer, presentationTimeUs, encodedAccessUnitCount)
    }

    override fun getCurrentPositionUs(sourceEnded: Boolean): Long {
        val positionUs = super.getCurrentPositionUs(sourceEnded)
        if (positionUs == AudioSink.CURRENT_POSITION_NOT_SET || startMediaTimeUs == Long.MIN_VALUE) {
            return positionUs
        }
        return positionUs + AudioDelayRamp.offsetUs(
            audioDelayUs.get(),
            positionUs - startMediaTimeUs,
            recoveryDurationUs,
        )
    }

    override fun flush() {
        startMediaTimeUs = Long.MIN_VALUE
        recoveryDurationUs = 0L
        super.flush()
    }

    override fun reset() {
        startMediaTimeUs = Long.MIN_VALUE
        recoveryDurationUs = 0L
        super.reset()
    }
}

/**
 * A text renderer that runs [delayUs] behind the playback position, so a
 * positive delay shows each subtitle later (Plezy's SubtitleDelayRenderer).
 */
@OptIn(UnstableApi::class)
internal class SubtitleDelayRenderer(
    private val delegate: Renderer,
    private val delayUs: AtomicLong,
) : Renderer by delegate {
    override fun render(positionUs: Long, elapsedRealtimeUs: Long) {
        delegate.render(positionUs - delayUs.get(), elapsedRealtimeUs)
    }
}

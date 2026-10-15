package dev.sparkison.tv.mpv

/**
 * How mpv drives the hardware decoder on the mediacodec-copy path. Ported
 * from Plezy's `initialDecoderEntries` / `DECODER_QUEUE_OPTIONS`
 * (github.com/edde746/plezy, GPL-3.0, 91b1e3b21 and #2361).
 */
internal object MpvDecoderPolicy {
    private const val ANDROID_12_API = 31

    /**
     * FFmpeg's MediaCodec decoder options (`vd-lavc-o`).
     *
     * `ndk_codec=0`: the Java MediaCodec wrapper, the one Media3 drives and
     * the one [dev.sparkison.tv.libmpv.MediaCodecCallbackBridge] serves. It is
     * also what FFmpeg picks when a JavaVM is registered, so this pins rather
     * than changes the wrapper.
     *
     * `async=1` from API 31: the codec reports free input slots and finished
     * frames on its own thread instead of being polled. Synchronous, a decoder
     * that falls behind on a heavy scene holds mpv's playloop inside the
     * decode call, and that thread also feeds the audio device and hands
     * frames to the vo, so audio underruns and late frames follow.
     * Asynchronous, the decoder answers EAGAIN and playback carries on. The
     * threshold is Media3's: `DefaultMediaCodecAdapterFactory` trusts
     * asynchronous MediaCodec by default from API 31 only, for the same
     * device-quirk history.
     *
     * `priority=0`: realtime, which Media3 also declares on every video codec.
     */
    fun decoderOptions(sdkInt: Int): String = buildList {
        add("ndk_codec=0")
        if (sdkInt >= ANDROID_12_API) add("async=1")
        add("priority=0")
    }.joinToString(",")

    /**
     * mpv's decoder thread and frame queue. A MediaCodec decoder is a pipeline
     * with a declared output delay (Tensor's AV1 block declares 12 frames), and
     * mpv's playloop decodes on demand with only a two-frame lookahead, so
     * frames from a deep pipeline reach the vo after their display time. A
     * decoder thread with up to half a second queued ahead hides that the way
     * Media3 does by keeping the codec's output pool in flight.
     *
     * mediacodec-copy frames are system-memory copies, so the byte cap is what
     * bounds the queue here: 48 MiB holds about two 4K 10-bit frames or a
     * dozen 1080p ones. Low-RAM boxes get 16 MiB, about five 1080p frames.
     */
    fun queueOptions(isLowRam: Boolean): List<Pair<String, String>> = listOf(
        "vd-queue-enable" to "yes",
        "vd-queue-max-samples" to "12",
        "vd-queue-max-secs" to "0.5",
        "vd-queue-max-bytes" to if (isLowRam) "16MiB" else "48MiB",
    )
}

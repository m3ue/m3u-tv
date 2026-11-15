/// Detects whether a native Android error code names a decoder/codec
/// failure (missing or non-functional `MediaCodec`, e.g. no on-device EAC3
/// decoder) rather than a network/IO failure.
///
/// ExoPlayer's `PlaybackException.errorCodeName` already distinguishes these
/// cases -- `Media3PlaybackPlugin.kt`'s `onPlayerError` forwards it verbatim
/// as `PlaybackError.code`. A decoder failure can't be fixed by retrying the
/// same backend (the device still won't have the decoder), so the
/// orchestrator uses this to switch to the next backend (mpv) instead.
bool looksLikeDecoderFailure(String? code) {
  if (code == null) return false;
  const decoderErrorCodes = <String>{
    'ERROR_CODE_DECODER_INIT_FAILED',
    'ERROR_CODE_DECODER_QUERY_FAILED',
    'ERROR_CODE_DECODING_FAILED',
    'ERROR_CODE_DECODING_FORMAT_EXCEEDS_CAPABILITIES',
    'ERROR_CODE_DECODING_FORMAT_UNSUPPORTED',
  };
  return decoderErrorCodes.contains(code);
}

/// Whether [code] is `Media3PlaybackPlugin.kt`'s report of a title whose audio
/// timing ExoPlayer can't follow. ExoPlayer itself treats this as non-fatal, so
/// unlike a decoder failure it isn't worth ending playback over if there's
/// nowhere left to go.
bool looksLikeAudioTimingFailure(String? code) =>
    code == 'AUDIO_TIMESTAMP_DISCONTINUITY';

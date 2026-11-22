// MKV playback for the web build (WebVideoBackend), without server transcoding.
//
// Browsers don't play Matroska, but most MKVs carry codecs they do play
// (H.264/HEVC/AV1/VP9 video, AAC/Opus/FLAC audio). Mediabunny reads the MKV
// over HTTP Range requests and this module copies its packets, untouched,
// into fragmented MP4 that a MediaSource SourceBuffer accepts. AC-3/E-AC-3,
// DTS and TrueHD audio, which most browsers' MSE rejects, is converted to
// AAC instead: decoded and re-encoded by Mediabunny's FFmpeg-based
// WebAssembly extensions, each loaded the first time a file needs it. They don't use WebCodecs, so this works
// on plain-HTTP installs too (WebCodecs needs a secure context). The
// MediaSource gets the file's full duration up front, so the scrubber works
// across the whole movie: a seek outside what's buffered starts a new copy
// session at the nearest preceding keyframe (found through the MKV's Cues),
// and Mediabunny's fragmented MP4 keeps absolute timestamps, so the new
// session's media lands at the right place on the timeline.
//
// Exposes `window.M3uMkvPlayer.open(video, url, startSeconds, onError)`,
// resolving to `{ duration, videoCodec, audioCodec, destroy() }`, or to
// `{ error: { code, message }, destroy() }` where `code` is
// `unsupported_video`, `unsupported_audio`, `no_video`, `unreadable` (the
// server sent no MKV data, e.g. a broken provider link) or null (anything
// else). It never rejects, so Dart reads failures as a plain field. An
// optional fifth `options` argument takes `{ audio: false }` to play the
// video track alone (diagnostics: checks the copy/seek path on files whose
// audio the browser can't play).

// 'mediabunny' resolves through index.html's import map, so the audio
// extensions (which import it by that bare name) share this instance.
import {
  ALL_FORMATS,
  EncodedAudioPacketSource,
  EncodedPacketSink,
  EncodedVideoPacketSource,
  Input,
  Mp4OutputFormat,
  NullTarget,
  Output,
  UnsupportedInputFormatError,
  UrlSource,
  AudioSampleSink,
  AudioSampleSource,
} from 'mediabunny';

// The SourceBuffer budget. Chromium caps a video SourceBuffer at roughly
// 150 MB, so the copy keeps about this much buffered: read-ahead and
// keep-behind windows are sized from the file's measured bytes per media
// second, up to these limits (a typical 1080p file gets the full 60 s ahead;
// a high-bitrate 4K remux gets less).
const BUFFER_BUDGET_BYTES = 90 * 1024 * 1024;
const MAX_READ_AHEAD_SECONDS = 60;
const MIN_READ_AHEAD_SECONDS = 8;
const MAX_KEEP_BEHIND_SECONDS = 30;
const MIN_KEEP_BEHIND_SECONDS = 3;
// Media copied before the byte rate is trusted for sizing the windows.
const BYTE_RATE_WARMUP_SECONDS = 4;
// A seek this close past the copy position is left to the running session.
const SEEK_CONTINUE_WINDOW_SECONDS = 15;

// Audio the browser can't play that we convert to AAC (codec -> its decoder
// extension), and the most channels the conversion keeps (wider layouts,
// e.g. 7.1, are folded down to 5.1). FFmpeg decodes the core channels of
// TrueHD/DTS-HD, so Atmos and DTS:X object data isn't kept.
const AUDIO_DECODERS = {
  ac3: { module: './js/mediabunny-ac3.min.mjs', register: 'registerAc3Decoder' },
  eac3: { module: './js/mediabunny-ac3.min.mjs', register: 'registerAc3Decoder' },
  dts: { module: './js/mediabunny-dts.min.mjs', register: 'registerDtsDecoder' },
  truehd: {
    module: './js/mediabunny-truehd.min.mjs',
    register: 'registerTrueHdDecoder',
  },
};
const MAX_CONVERTED_CHANNELS = 6;
const AAC_CODEC_STRING = 'mp4a.40.2';
const CONVERTED_AAC_BITRATE_PER_CHANNEL = 96_000;

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

// Extension module path -> its load, so each registers once per page.
const extensionLoads = new Map();

function loadExtension(module, register) {
  let load = extensionLoads.get(module);
  if (!load) {
    load = import(module)
      .then((extension) => extension[register]())
      .catch((error) => {
        extensionLoads.delete(module);
        throw error;
      });
    extensionLoads.set(module, load);
  }
  return load;
}

/** Loads [codec]'s decoder and the AAC encoder. */
function loadAudioConversion(codec) {
  const decoder = AUDIO_DECODERS[codec];
  return Promise.all([
    loadExtension(decoder.module, decoder.register),
    loadExtension('./js/mediabunny-aac-encoder.min.mjs', 'registerAacEncoder'),
  ]);
}

function codedError(code, message) {
  return Object.assign(new Error(message), { code });
}

function mseSupports(kind, codecString) {
  return (
    !!codecString &&
    MediaSource.isTypeSupported(`${kind}/mp4; codecs="${codecString}"`)
  );
}

class MkvPlayer {
  constructor(video, url, onError, options = {}) {
    this.video = video;
    this.includeAudio = options.audio !== false;
    this.url = url;
    this.onError = onError;
    this.destroyed = false;
    this.session = null;
    this.queue = [];
    this.queueRunning = false;
    this.sourceBuffer = null;
    this.mimeType = null;
    // Shrinks after a QuotaExceededError, so the next windows stay smaller.
    this.budgetBytes = BUFFER_BUDGET_BYTES;
    this.bytesPerSecond = null;
    this.onSeeking = () => this._handleSeeking();
  }

  async open(startSeconds) {
    this.input = new Input({
      source: new UrlSource(this.url, {
        requestInit: { credentials: 'same-origin' },
      }),
      formats: ALL_FORMATS,
    });

    try {
      this.videoTrack = await this.input.getPrimaryVideoTrack();
    } catch (error) {
      if (error instanceof UnsupportedInputFormatError) {
        throw codedError('unreadable', error.message);
      }
      throw error;
    }
    if (!this.videoTrack) throw codedError('no_video', 'No video track');
    const videoCodecString = await this.videoTrack.getCodecParameterString();
    if (!mseSupports('video', videoCodecString)) {
      throw codedError(
        'unsupported_video',
        this.videoTrack.codec ?? videoCodecString ?? 'unknown',
      );
    }

    // Take the file's primary audio track (else the first) as-is when the
    // browser plays it, or converted to AAC when it's AC-3/E-AC-3/DTS/TrueHD; other
    // tracks are only tried after that, so a playable commentary or
    // second-language track never silently replaces the main one. With
    // audio tracks but none usable, fail rather than play silently.
    const audioTracks = this.includeAudio
      ? await this.input.getAudioTracks()
      : [];
    const primaryAudio = this.includeAudio
      ? await this.input.getPrimaryAudioTrack()
      : null;
    const ordered = primaryAudio
      ? [primaryAudio, ...audioTracks.filter((t) => t !== primaryAudio)]
      : audioTracks;
    this.audioTrack = null;
    this.convertAudio = false;
    for (const track of ordered) {
      if (mseSupports('audio', await track.getCodecParameterString())) {
        this.audioTrack = track;
        break;
      }
      if (
        Object.hasOwn(AUDIO_DECODERS, track.codec) &&
        mseSupports('audio', AAC_CODEC_STRING)
      ) {
        this.audioTrack = track;
        this.convertAudio = true;
        break;
      }
    }
    if (!this.audioTrack && audioTracks.length > 0) {
      const codecs = [...new Set(audioTracks.map((t) => t.codec ?? 'unknown'))];
      throw codedError('unsupported_audio', codecs.join(', '));
    }
    if (this.convertAudio) await loadAudioConversion(this.audioTrack.codec);

    this.duration =
      (await this.input.getDurationFromMetadata()) ??
      (await this.input.computeDuration());

    this.mediaSource = new MediaSource();
    this.objectUrl = URL.createObjectURL(this.mediaSource);
    const opened = new Promise((resolve) =>
      this.mediaSource.addEventListener('sourceopen', resolve, { once: true }),
    );
    this.video.src = this.objectUrl;
    await opened;
    if (this.destroyed) return this._handle();
    this.mediaSource.duration = this.duration;
    this.video.addEventListener('seeking', this.onSeeking);

    this._startSession(Math.max(0, startSeconds || 0));
    return this._handle();
  }

  _handle() {
    return {
      duration: this.duration,
      videoCodec: this.videoTrack?.codec ?? null,
      audioCodec: this.audioTrack?.codec ?? null,
      audioConverted: this.convertAudio,
      destroy: () => this.destroy(),
    };
  }

  // --- Copy sessions -------------------------------------------------------

  _startSession(fromSeconds) {
    const session = {
      cancelled: false,
      startSeconds: fromSeconds,
      copiedUntil: fromSeconds,
      output: null,
    };
    this.session = session;
    this._runSession(session).catch((error) => {
      if (session.cancelled || this.destroyed) return;
      this._fail(error);
    });
  }

  async _runSession(session) {
    const videoSink = new EncodedPacketSink(this.videoTrack);
    const keyPacket =
      (await videoSink.getKeyPacket(session.startSeconds, {
        verifyKeyPackets: true,
      })) ?? (await videoSink.getFirstKeyPacket());
    if (!keyPacket || session.cancelled) return;
    session.startSeconds = keyPacket.timestamp;
    session.copiedUntil = keyPacket.timestamp;

    const audioFeed = this.audioTrack
      ? await this._openAudioFeed(keyPacket.timestamp)
      : null;
    if (session.cancelled) {
      await audioFeed?.dispose();
      return;
    }

    const output = new Output({
      format: new Mp4OutputFormat({
        fastStart: 'fragmented',
        minimumFragmentDuration: 1,
        onFtyp: (data) => this._enqueueAppend(session, data),
        onMoov: (data) => this._enqueueAppend(session, data),
        onMoof: (data) => this._enqueueAppend(session, data),
        onMdat: (data) => this._enqueueAppend(session, data),
      }),
      target: new NullTarget(),
    });
    session.output = output;
    const videoSource = new EncodedVideoPacketSource(this.videoTrack.codec);
    output.addVideoTrack(videoSource);
    if (audioFeed) output.addAudioTrack(audioFeed.source);
    // The muxer emits ftyp during start(), so the queue may already be waiting
    // on the MIME type before start() returns.
    let resolveMimeType;
    session.mimeType = new Promise((resolve) => {
      resolveMimeType = resolve;
    });
    await output.start();
    resolveMimeType(output.getMimeType());

    const videoConfig = await this.videoTrack.getDecoderConfig();
    const videoPackets = videoSink.packets(keyPacket);
    let nextVideo = await videoPackets.next();
    let videoMeta = { decoderConfig: videoConfig };

    // Interleave both tracks by timestamp so fragments stay balanced.
    try {
      while (!session.cancelled && (!nextVideo.done || audioFeed?.hasNext())) {
        const takeVideo =
          !audioFeed?.hasNext() ||
          (!nextVideo.done &&
            nextVideo.value.timestamp <= audioFeed.nextTimestamp());
        const timestamp = takeVideo
          ? nextVideo.value.timestamp
          : audioFeed.nextTimestamp();
        await this._waitForRoom(session, timestamp);
        if (session.cancelled) break;
        if (takeVideo) {
          await videoSource.add(nextVideo.value, videoMeta ?? undefined);
          videoMeta = null;
          nextVideo = await videoPackets.next();
        } else {
          await audioFeed.addNext();
        }
        session.copiedUntil = Math.max(session.copiedUntil, timestamp);
      }
    } finally {
      await audioFeed?.dispose();
    }

    if (session.cancelled) return;
    await output.finalize();
    session.finished = true;
    this._enqueue(session, { type: 'end' });
  }

  /**
   * The audio half of a session, from [startSeconds]: the track's own
   * packets when the browser plays its codec, else decoded AC-3/E-AC-3/DTS/TrueHD
   * samples re-encoded to AAC. Either way `nextTimestamp()` peeks the next
   * item and `addNext()` hands it to `source` (the output's audio track).
   */
  async _openAudioFeed(startSeconds) {
    if (!this.convertAudio) {
      const sink = new EncodedPacketSink(this.audioTrack);
      const first =
        (await sink.getPacket(startSeconds)) ?? (await sink.getFirstPacket());
      const source = new EncodedAudioPacketSource(this.audioTrack.codec);
      const packets = first ? sink.packets(first) : null;
      let next = packets ? await packets.next() : { done: true };
      let meta = { decoderConfig: await this.audioTrack.getDecoderConfig() };
      return {
        source,
        hasNext: () => !next.done,
        nextTimestamp: () => next.value.timestamp,
        addNext: async () => {
          await source.add(next.value, meta ?? undefined);
          meta = null;
          next = await packets.next();
        },
        dispose: async () => {
          await packets?.return();
        },
      };
    }

    const channels = await this.audioTrack.getNumberOfChannels();
    const outputChannels = Math.min(channels, MAX_CONVERTED_CHANNELS);
    const source = new AudioSampleSource({
      codec: 'aac',
      bitrate: outputChannels * CONVERTED_AAC_BITRATE_PER_CHANNEL,
      transform:
        outputChannels < channels
          ? { numberOfChannels: outputChannels }
          : undefined,
    });
    const samples = new AudioSampleSink(this.audioTrack).samples(startSeconds);
    let next = await samples.next();
    return {
      source,
      hasNext: () => !next.done,
      nextTimestamp: () => next.value.timestamp,
      addNext: async () => {
        const sample = next.value;
        try {
          await source.add(sample);
        } finally {
          sample.close();
        }
        next = await samples.next();
      },
      dispose: async () => {
        if (!next.done) next.value.close();
        await samples.return();
      },
    };
  }

  async _waitForRoom(session, timestamp) {
    while (
      !session.cancelled &&
      !this.destroyed &&
      timestamp - this.video.currentTime > this._readAheadSeconds()
    ) {
      await sleep(500);
    }
  }

  _handleSeeking() {
    if (this.destroyed) return;
    const target = this.video.currentTime;
    if (this._isBuffered(target)) return;
    const session = this.session;
    if (
      session &&
      !session.cancelled &&
      !session.finished &&
      target >= session.startSeconds &&
      target <= session.copiedUntil + SEEK_CONTINUE_WINDOW_SECONDS
    ) {
      return;
    }
    this._restartAt(target);
  }

  async _restartAt(seconds) {
    const previous = this.session;
    if (previous) {
      previous.cancelled = true;
      previous.output?.cancel().catch(() => {});
    }
    this.queue = [];
    const restartToken = {};
    this.restartToken = restartToken;
    await this._whenIdle();
    if (this.destroyed || this.restartToken !== restartToken) return;
    const sourceBuffer = this.sourceBuffer;
    if (sourceBuffer) {
      try {
        // Drop any half-parsed fragment from the cancelled session, then the
        // media it buffered: the new session starts with a fresh init segment.
        if (this.mediaSource.readyState === 'open') sourceBuffer.abort();
        if (sourceBuffer.buffered.length > 0) {
          sourceBuffer.remove(0, Infinity);
          await this._whenIdle();
        }
      } catch (error) {
        this._fail(error);
        return;
      }
    }
    if (this.destroyed || this.restartToken !== restartToken) return;
    this._startSession(seconds);
  }

  _isBuffered(seconds) {
    const ranges = this.video.buffered;
    for (let i = 0; i < ranges.length; i++) {
      if (seconds >= ranges.start(i) && seconds < ranges.end(i) - 0.25) {
        return true;
      }
    }
    return false;
  }

  // --- SourceBuffer queue --------------------------------------------------

  _readAheadSeconds() {
    return this._windowSeconds(0.75, MIN_READ_AHEAD_SECONDS, MAX_READ_AHEAD_SECONDS);
  }

  _keepBehindSeconds() {
    return this._windowSeconds(0.25, MIN_KEEP_BEHIND_SECONDS, MAX_KEEP_BEHIND_SECONDS);
  }

  _windowSeconds(shareOfBudget, min, max) {
    if (!this.bytesPerSecond) return max;
    const seconds = (this.budgetBytes * shareOfBudget) / this.bytesPerSecond;
    return Math.min(max, Math.max(min, seconds));
  }

  _recordCopiedBytes(session, byteLength) {
    session.bytes = (session.bytes ?? 0) + byteLength;
    const seconds = session.copiedUntil - session.startSeconds;
    if (seconds >= BYTE_RATE_WARMUP_SECONDS) {
      this.bytesPerSecond = session.bytes / seconds;
    }
  }

  _enqueueAppend(session, data) {
    this._recordCopiedBytes(session, data.byteLength);
    this._enqueue(session, { type: 'append', data: data.slice() });
  }

  _enqueue(session, operation) {
    if (session.cancelled || this.destroyed) return;
    this.queue.push({ session, ...operation });
    this._drainQueue();
  }

  async _drainQueue() {
    if (this.queueRunning) return;
    this.queueRunning = true;
    try {
      while (this.queue.length > 0 && !this.destroyed) {
        const operation = this.queue.shift();
        if (operation.session.cancelled) continue;
        if (operation.type === 'end') {
          await this._whenIdle();
          if (this.mediaSource.readyState === 'open') {
            this.mediaSource.endOfStream();
          }
          continue;
        }
        await this._ensureSourceBuffer(operation.session);
        if (operation.session.cancelled) continue;
        await this._append(operation.data, operation.session);
        await this._evictBehindPlayhead();
      }
    } catch (error) {
      if (!this.destroyed) this._fail(error);
    } finally {
      this.queueRunning = false;
    }
  }

  async _ensureSourceBuffer(session) {
    if (this.sourceBuffer) return;
    this.mimeType = await session.mimeType;
    this.sourceBuffer = this.mediaSource.addSourceBuffer(this.mimeType);
  }

  /**
   * Appends [data], riding out a full SourceBuffer: evict what's behind the
   * playhead, shrink the budget so the copy reads less far ahead from now
   * on, and wait for playback to consume buffered media before retrying.
   * Fails only when there's next to nothing ahead left to consume, i.e. the
   * fragment can't fit at all.
   */
  async _append(data, session) {
    while (true) {
      await this._whenIdle();
      // A seek may have cancelled this fragment's session while it waited; its
      // media would land as an orphaned range away from the new playhead.
      if (session.cancelled || this.destroyed) return;
      try {
        this.sourceBuffer.appendBuffer(data);
        await this._whenIdle();
        return;
      } catch (error) {
        if (error?.name !== 'QuotaExceededError') throw error;
      }
      this.budgetBytes = Math.max(
        BUFFER_BUDGET_BYTES / 4,
        this.budgetBytes * 0.75,
      );
      await this._evictBehindPlayhead(MIN_KEEP_BEHIND_SECONDS);
      if (this._secondsBufferedAhead() < MIN_KEEP_BEHIND_SECONDS) {
        throw new Error(
          'The video bitrate is too high for this browser to buffer.',
        );
      }
      while (
        !session.cancelled &&
        !this.destroyed &&
        this._secondsBufferedAhead() > this._readAheadSeconds() / 2
      ) {
        await sleep(500);
      }
      if (session.cancelled || this.destroyed) return;
      await this._evictBehindPlayhead(MIN_KEEP_BEHIND_SECONDS);
    }
  }

  _secondsBufferedAhead() {
    const ranges = this.video.buffered;
    const now = this.video.currentTime;
    for (let i = 0; i < ranges.length; i++) {
      if (now >= ranges.start(i) - 0.5 && now < ranges.end(i)) {
        return ranges.end(i) - now;
      }
    }
    return 0;
  }

  /**
   * Frees buffer the playhead no longer needs: everything more than
   * [keepSeconds] behind it, plus every range it isn't in. Scrubbing leaves
   * such ranges behind (the media around each earlier seek target), and
   * trimming only the front of the buffer would let them pile up until the
   * SourceBuffer is full.
   */
  async _evictBehindPlayhead(keepSeconds = this._keepBehindSeconds()) {
    const sourceBuffer = this.sourceBuffer;
    if (!sourceBuffer) return;
    const now = this.video.currentTime;
    const removals = [];
    const ranges = sourceBuffer.buffered;
    for (let i = 0; i < ranges.length; i++) {
      const start = ranges.start(i);
      const end = ranges.end(i);
      const holdsPlayhead = now >= start - 0.5 && now < end;
      if (!holdsPlayhead) {
        removals.push([start, end]);
      } else if (now - keepSeconds > start + 1) {
        removals.push([start, now - keepSeconds]);
      }
    }
    for (const [start, end] of removals) {
      await this._whenIdle();
      sourceBuffer.remove(start, end);
    }
    await this._whenIdle();
  }

  _whenIdle() {
    const sourceBuffer = this.sourceBuffer;
    if (!sourceBuffer || !sourceBuffer.updating) return Promise.resolve();
    return new Promise((resolve) =>
      sourceBuffer.addEventListener('updateend', resolve, { once: true }),
    );
  }

  // --- Lifecycle -------------------------------------------------------------

  _fail(error) {
    if (this.destroyed) return;
    try {
      this.onError?.(String(error?.message ?? error));
    } catch (_) {
      // The callback belongs to Dart; never let it break teardown.
    }
  }

  destroy() {
    if (this.destroyed) return;
    this.destroyed = true;
    if (this.session) {
      this.session.cancelled = true;
      this.session.output?.cancel().catch(() => {});
    }
    this.queue = [];
    this.video.removeEventListener('seeking', this.onSeeking);
    try {
      this.input?.dispose();
    } catch (_) {
      // Already disposed.
    }
    if (this.objectUrl) {
      this.video.removeAttribute('src');
      this.video.load();
      URL.revokeObjectURL(this.objectUrl);
    }
  }
}

window.M3uMkvPlayer = {
  async open(video, url, startSeconds, onError, options) {
    const player = new MkvPlayer(video, url, onError, options);
    try {
      return await player.open(startSeconds);
    } catch (error) {
      player.destroy();
      return {
        error: {
          code: error?.code ?? null,
          message: String(error?.message ?? error),
        },
        destroy: () => {},
      };
    }
  },
};

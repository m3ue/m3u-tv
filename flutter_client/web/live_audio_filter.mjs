// Live MPEG-TS with AC-3/E-AC-3 audio for the web build (WebVideoBackend).
//
// Most browsers' MSE rejects AC-3, and mpegts.js hands it over untouched. This
// is an mpegts.js custom loader that rewrites the stream on its way in: the
// AC-3 track's frames are decoded and re-encoded to AAC (Mediabunny's
// FFmpeg-based WebAssembly coders, which work on plain-HTTP installs too) and
// the program map is changed to match. Every other packet passes through
// as it is, so mpegts.js keeps handling buffering and timestamp breaks.
//
// Exposes `window.M3uLiveAudioFilter.loader`, for mpegts.js's `customLoader`
// (which needs `enableWorker: false`).

import { EncodedPacket } from 'mediabunny';
import { decoders, encoders } from './mediabunny_coders.mjs';

const PACKET_SIZE = 188;
const SYNC_BYTE = 0x47;
const STREAM_TYPE_AAC = 0x0f;
const STREAM_TYPE_AC3 = 0x81;
const STREAM_TYPE_EAC3 = 0x87;
// mpegts.js plays the first of these it finds in the program map.
const AUDIO_STREAM_TYPES = new Set([
  0x03, 0x04, STREAM_TYPE_AAC, 0x11, STREAM_TYPE_AC3, STREAM_TYPE_EAC3,
]);
const AAC_BITRATE_PER_CHANNEL = 96_000;
const MAX_CHANNELS = 6;
const CLOCK = 90_000;
const PTS_WRAP = 2 ** 33;
// How far a frame may be from where the last one ended before the encoder is
// restarted at the new time (an ad break, a failover, lost packets).
const MAX_DRIFT = CLOCK / 10;

let codersLoad = null;

function loadCoders() {
  codersLoad ??= Promise.all([
    import('./js/mediabunny-ac3.min.mjs').then((m) => m.registerAc3Decoder()),
    import('./js/mediabunny-aac-encoder.min.mjs').then((m) =>
      m.registerAacEncoder(),
    ),
  ]).catch((error) => {
    codersLoad = null;
    throw error;
  });
  return codersLoad;
}

function concat(a, b) {
  if (a.length === 0) return b;
  const joined = new Uint8Array(a.length + b.length);
  joined.set(a);
  joined.set(b, a.length);
  return joined;
}

function crc32(bytes) {
  let crc = 0xffffffff;
  for (const byte of bytes) {
    crc ^= byte << 24;
    for (let bit = 0; bit < 8; bit++) {
      crc = crc & 0x80000000 ? (crc << 1) ^ 0x04c11db7 : crc << 1;
    }
  }
  return crc >>> 0;
}

// --- AC-3 / E-AC-3 frames ----------------------------------------------------

const AC3_SAMPLE_RATES = [48000, 44100, 32000];
const AC3_BITRATES = [
  32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384, 448, 512,
  576, 640,
];

/** The frame header at [offset], or null when there isn't a valid one. */
function parseFrameHeader(data, offset) {
  if (data[offset] !== 0x0b || data[offset + 1] !== 0x77) return null;
  const bitStreamId = data[offset + 5] >> 3;
  const rateCode = data[offset + 4] >> 6;
  if (bitStreamId <= 10) {
    const sizeCode = data[offset + 4] & 0x3f;
    const bitrate = AC3_BITRATES[sizeCode >> 1];
    const sampleRate = AC3_SAMPLE_RATES[rateCode];
    if (!bitrate || !sampleRate) return null;
    let words;
    if (sampleRate === 48000) words = bitrate * 2;
    else if (sampleRate === 32000) words = bitrate * 3;
    else words = Math.floor((bitrate * 320) / 147) + (sizeCode & 1);
    return { codec: 'ac3', size: words * 2, sampleRate, primary: true };
  }
  if (bitStreamId > 16) return null;
  const size =
    ((((data[offset + 2] & 0x07) << 8) | data[offset + 3]) + 1) * 2;
  const sampleRate =
    rateCode === 3
      ? AC3_SAMPLE_RATES[(data[offset + 4] >> 4) & 3] / 2
      : AC3_SAMPLE_RATES[rateCode];
  if (!sampleRate) return null;
  return {
    codec: 'eac3',
    size,
    sampleRate,
    // Extra substreams (7.1 extensions, second programs) are dropped.
    primary:
      data[offset + 2] >> 6 !== 1 && ((data[offset + 2] >> 3) & 0x07) === 0,
  };
}

/** Turns AC-3/E-AC-3 frames into ADTS AAC frames with 90 kHz timestamps. */
class AudioConverter {
  constructor(onFrame) {
    this.onFrame = onFrame;
    this.decoder = null;
    this.encoder = null;
  }

  /** [pts] is null for a frame that continues the previous one. */
  async convert(frame, header, pts) {
    await loadCoders();
    if (this.decoderCodec !== header.codec + header.sampleRate) {
      await this._closeDecoder();
      const Decoder = decoders.find((d) => d.supports(header.codec, {}));
      this.decoder = new Decoder();
      this.decoder.codec = header.codec;
      this.decoder.config = {
        codec: header.codec === 'ac3' ? 'ac-3' : 'ec-3',
        sampleRate: header.sampleRate,
        numberOfChannels: 2,
      };
      this.decoder.onSample = (sample) => {
        this.sample = sample;
      };
      await this.decoder.init();
      this.decoderCodec = header.codec + header.sampleRate;
    }
    this.sample = null;
    try {
      await this.decoder.decode(new EncodedPacket(frame, 'key', 0, 0));
    } catch (_) {
      // A damaged frame (packet loss) is skipped, not fatal.
      return;
    }
    const sample = this.sample;
    this.sample = null;
    if (!sample) return;
    try {
      await this._encode(sample, pts);
    } finally {
      sample.close();
    }
  }

  async _encode(sample, pts) {
    const { numberOfChannels, numberOfFrames, sampleRate } = sample;
    if (numberOfChannels > MAX_CHANNELS) {
      throw new Error(`Unsupported channel count ${numberOfChannels}`);
    }
    const expected =
      this.encoder &&
      this.startPts + (this.framesIn * CLOCK) / this.encoder.config.sampleRate;
    let drift = 0;
    if (this.encoder && pts !== null) {
      drift = (pts - (expected % PTS_WRAP) + PTS_WRAP) % PTS_WRAP;
      if (drift > PTS_WRAP / 2) drift -= PTS_WRAP;
    }
    if (
      !this.encoder ||
      this.encoder.config.sampleRate !== sampleRate ||
      this.encoder.config.numberOfChannels !== numberOfChannels ||
      Math.abs(drift) > MAX_DRIFT
    ) {
      const start = pts ?? expected;
      if (start == null) return;
      await this._closeEncoder();
      await this._openEncoder(sampleRate, numberOfChannels, start);
    }
    await this.encoder.encode(sample);
    this.framesIn += numberOfFrames;
  }

  async _openEncoder(sampleRate, numberOfChannels, startPts) {
    const config = {
      codec: 'mp4a.40.2',
      sampleRate,
      numberOfChannels,
      bitrate: numberOfChannels * AAC_BITRATE_PER_CHANNEL,
      aac: { format: 'adts' },
    };
    const Encoder = encoders.find((e) => e.supports('aac', config));
    if (!Encoder) throw new Error(`Can't encode ${sampleRate} Hz audio`);
    const encoder = new Encoder();
    encoder.codec = 'aac';
    encoder.config = config;
    encoder.onPacket = (packet) => {
      const pts = Math.round(startPts + packet.timestamp * CLOCK);
      this.onFrame(packet.data, (pts + PTS_WRAP) % PTS_WRAP);
    };
    await encoder.init();
    this.encoder = encoder;
    this.startPts = startPts;
    this.framesIn = 0;
  }

  async _closeEncoder() {
    const encoder = this.encoder;
    this.encoder = null;
    await encoder?.close();
  }

  async _closeDecoder() {
    const decoder = this.decoder;
    this.decoder = null;
    this.decoderCodec = null;
    await decoder?.close();
  }

  async close() {
    await this._closeEncoder();
    await this._closeDecoder();
  }
}

// --- MPEG-TS -----------------------------------------------------------------

class TsAudioFilter {
  constructor() {
    this.pending = new Uint8Array(0);
    this.pmtPid = null;
    this.section = null;
    this.audioPid = null;
    this.pmtCounter = 0;
    this.audioCounter = 0;
    this.output = [];
    this.frames = [];
    this._resetAudio();
    this.converter = new AudioConverter((data, pts) =>
      this._writeAudio(data, pts),
    );
  }

  /** The rewritten packets for [chunk] (whole packets only). */
  async push(chunk) {
    const data = concat(this.pending, chunk);
    let offset = 0;
    while (offset + PACKET_SIZE <= data.length) {
      if (
        data[offset] !== SYNC_BYTE ||
        (offset + PACKET_SIZE < data.length &&
          data[offset + PACKET_SIZE] !== SYNC_BYTE)
      ) {
        offset += 1;
        continue;
      }
      this._packet(data.subarray(offset, offset + PACKET_SIZE));
      offset += PACKET_SIZE;
    }
    this.pending = data.slice(offset);
    for (const { data: frame, header, pts } of this.frames.splice(0)) {
      await this.converter.convert(frame, header, pts);
    }
    const out = new Uint8Array(this.output.length * PACKET_SIZE);
    this.output.forEach((packet, i) => out.set(packet, i * PACKET_SIZE));
    this.output = [];
    return out;
  }

  close() {
    return this.converter.close();
  }

  _packet(packet) {
    const pid = ((packet[1] & 0x1f) << 8) | packet[2];
    if (pid !== 0 && pid !== this.pmtPid && pid !== this.audioPid) {
      this.output.push(packet);
      return;
    }
    const hasPayload = (packet[3] & 0x10) !== 0;
    const start = packet[3] & 0x20 ? 5 + packet[4] : 4;
    const unitStart = (packet[1] & 0x40) !== 0;
    const payload =
      hasPayload && start < PACKET_SIZE ? packet.subarray(start) : null;
    if (pid === 0) {
      if (payload && unitStart) this._readPat(payload.subarray(payload[0] + 1));
      this.output.push(packet);
    } else if (pid === this.pmtPid) {
      if (payload) this._collectPmt(payload, unitStart);
    } else if (payload) {
      this._collectAudio(payload, unitStart);
    }
  }

  _readPat(section) {
    if (section.length < 12 || section[0] !== 0) return;
    const end = 3 + (((section[1] & 0x0f) << 8) | section[2]) - 4;
    for (let i = 8; i + 4 <= Math.min(end, section.length); i += 4) {
      if (((section[i] << 8) | section[i + 1]) === 0) continue;
      const pid = ((section[i + 2] & 0x1f) << 8) | section[i + 3];
      if (pid !== this.pmtPid) {
        this.pmtPid = pid;
        this.section = null;
      }
      return;
    }
  }

  _collectPmt(payload, unitStart) {
    if (unitStart) this.section = payload.slice(payload[0] + 1);
    else if (this.section) this.section = concat(this.section, payload);
    if (!this.section || this.section.length < 3) return;
    const size = 3 + (((this.section[1] & 0x0f) << 8) | this.section[2]);
    if (this.section.length < size) return;
    const section = this.section.slice(0, size);
    this.section = null;
    this._writeSection(section[0] === 2 ? this._rewritePmt(section) : section);
  }

  /** Relabels the AC-3 track as AAC and drops any other audio. */
  _rewritePmt(section) {
    const end = section.length - 4;
    const infoLength = ((section[10] & 0x0f) << 8) | section[11];
    const streams = [];
    for (let i = 12 + infoLength; i + 5 <= end; ) {
      const size = 5 + (((section[i + 3] & 0x0f) << 8) | section[i + 4]);
      streams.push(section.subarray(i, i + size));
      i += size;
    }
    const audio = streams.find((s) => AUDIO_STREAM_TYPES.has(s[0]));
    const convert =
      audio &&
      (audio[0] === STREAM_TYPE_AC3 || audio[0] === STREAM_TYPE_EAC3);
    const audioPid = convert ? ((audio[1] & 0x1f) << 8) | audio[2] : null;
    if (audioPid !== this.audioPid) {
      this.audioPid = audioPid;
      this._resetAudio();
    }
    if (!convert) return section;

    const body = [...section.subarray(0, 12 + infoLength)];
    for (const stream of streams) {
      if (stream === audio) {
        body.push(STREAM_TYPE_AAC, stream[1], stream[2], 0xf0, 0);
      } else if (!AUDIO_STREAM_TYPES.has(stream[0])) {
        body.push(...stream);
      }
    }
    const length = body.length + 4 - 3;
    body[1] = (body[1] & 0xf0) | (length >> 8);
    body[2] = length & 0xff;
    const crc = crc32(body);
    body.push(crc >>> 24, (crc >>> 16) & 255, (crc >>> 8) & 255, crc & 255);
    return Uint8Array.from(body);
  }

  _writeSection(section) {
    const data = concat(Uint8Array.of(0), section);
    for (let offset = 0; offset < data.length; offset += PACKET_SIZE - 4) {
      const packet = new Uint8Array(PACKET_SIZE).fill(0xff);
      packet[0] = SYNC_BYTE;
      packet[1] = (offset === 0 ? 0x40 : 0) | (this.pmtPid >> 8);
      packet[2] = this.pmtPid & 0xff;
      packet[3] = 0x10 | this.pmtCounter;
      this.pmtCounter = (this.pmtCounter + 1) & 0x0f;
      packet.set(data.subarray(offset, offset + PACKET_SIZE - 4), 4);
      this.output.push(packet);
    }
  }

  _resetAudio() {
    this.elementary = new Uint8Array(0);
    this.nextPts = null;
    this.ptsOffset = 0;
  }

  _collectAudio(payload, unitStart) {
    let data = payload;
    if (unitStart) {
      // A private_stream_1 or audio PES header.
      if (data[0] !== 0 || data[1] !== 0 || data[2] !== 1) return;
      const headerSize = 9 + data[8];
      if (data[7] & 0x80) {
        this.nextPts =
          ((data[9] >> 1) & 0x07) * 2 ** 30 +
          (data[10] << 22) +
          ((data[11] >> 1) << 15) +
          (data[12] << 7) +
          (data[13] >> 1);
        // It belongs to the first frame that starts in this PES.
        this.ptsOffset = this.elementary.length;
      }
      data = data.subarray(headerSize);
    }
    this.elementary = concat(this.elementary, data);
    this._readFrames();
  }

  _readFrames() {
    const data = this.elementary;
    let offset = 0;
    while (offset + 8 <= data.length) {
      const header = parseFrameHeader(data, offset);
      if (!header) {
        offset += 1;
        continue;
      }
      if (offset + header.size > data.length) break;
      let pts = null;
      if (this.nextPts !== null && offset >= this.ptsOffset) {
        pts = this.nextPts;
        this.nextPts = null;
      }
      if (header.primary) {
        this.frames.push({
          data: data.slice(offset, offset + header.size),
          header,
          pts,
        });
      }
      offset += header.size;
    }
    this.elementary = data.slice(offset);
    this.ptsOffset = Math.max(0, this.ptsOffset - offset);
  }

  _writeAudio(frame, pts) {
    if (this.audioPid === null) return;
    const size = frame.length + 8;
    const pes = new Uint8Array(14 + frame.length);
    pes.set([
      0, 0, 1, 0xc0, size >> 8, size & 0xff, 0x80, 0x80, 5,
      0x21 | (Math.floor(pts / 2 ** 30) << 1),
      Math.floor(pts / 2 ** 22) & 0xff,
      (Math.floor(pts / 2 ** 14) & 0xfe) | 1,
      Math.floor(pts / 2 ** 7) & 0xff,
      ((pts % 128) << 1) | 1,
    ]);
    pes.set(frame, 14);
    for (let offset = 0; offset < pes.length; ) {
      const size = Math.min(PACKET_SIZE - 4, pes.length - offset);
      const stuffing = PACKET_SIZE - 4 - size;
      const packet = new Uint8Array(PACKET_SIZE).fill(0xff);
      packet[0] = SYNC_BYTE;
      packet[1] = (offset === 0 ? 0x40 : 0) | (this.audioPid >> 8);
      packet[2] = this.audioPid & 0xff;
      packet[3] = (stuffing > 0 ? 0x30 : 0x10) | this.audioCounter;
      this.audioCounter = (this.audioCounter + 1) & 0x0f;
      if (stuffing > 0) {
        packet[4] = stuffing - 1;
        if (stuffing > 1) packet[5] = 0;
      }
      packet.set(pes.subarray(offset, offset + size), PACKET_SIZE - size);
      this.output.push(packet);
      offset += size;
    }
  }
}

// --- mpegts.js loader --------------------------------------------------------

/** Built on first use: mpegts.js is loaded on demand too. */
function createLoaderClass() {
  const { BaseLoader, LoaderErrors, LoaderStatus } = window.mpegts;

  return class LiveAudioLoader extends BaseLoader {
    constructor() {
      super('m3u-live-audio');
      this._needStash = true;
    }

    open(dataSource) {
      this._status = LoaderStatus.kConnecting;
      this._abort = new AbortController();
      this._run(dataSource, this._abort.signal);
    }

    abort() {
      this._abort?.abort();
      this._status = LoaderStatus.kComplete;
    }

    destroy() {
      this._abort?.abort();
      super.destroy();
    }

    async _run(dataSource, signal) {
      const filter = new TsAudioFilter();
      try {
        const response = await fetch(dataSource.url, {
          signal,
          credentials: 'same-origin',
          cache: 'no-store',
        });
        if (!response.ok) {
          response.body?.cancel();
          this._fail(LoaderErrors.HTTP_STATUS_CODE_INVALID, {
            code: response.status,
            msg: response.statusText,
          });
          return;
        }
        this._status = LoaderStatus.kBuffering;
        const reader = response.body.getReader();
        let position = 0;
        while (true) {
          const { done, value } = await reader.read();
          if (signal.aborted) return;
          if (done) break;
          const data = await filter.push(value);
          if (signal.aborted) return;
          if (data.length === 0) continue;
          const start = position;
          position += data.length;
          this._onDataArrival?.(data.buffer, start, position);
        }
        this._status = LoaderStatus.kComplete;
        this._onComplete?.(0, position - 1);
      } catch (error) {
        if (signal.aborted) return;
        this._fail(LoaderErrors.EXCEPTION, {
          code: -1,
          msg: String(error?.message ?? error),
        });
      } finally {
        if (!signal.aborted) this._abort.abort();
        filter.close().catch(() => {});
      }
    }

    _fail(type, info) {
      this._status = LoaderStatus.kError;
      this._onError?.(type, info);
    }
  };
}

let loaderClass = null;

window.M3uLiveAudioFilter = {
  get loader() {
    loaderClass ??= createLoaderClass();
    return loaderClass;
  },
};

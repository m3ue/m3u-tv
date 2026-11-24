// What the @mediabunny/* audio extensions import as 'mediabunny' (see the
// scopes in index.html's import map): Mediabunny itself, plus a record of the
// coder classes they register. Mediabunny only runs them behind a whole file
// demux/mux, whose read-ahead is far too slow to start for a live stream, so
// live_audio_filter.mjs drives the same classes one frame at a time.
import {
  registerDecoder as baseRegisterDecoder,
  registerEncoder as baseRegisterEncoder,
} from './js/mediabunny.min.mjs';

export * from './js/mediabunny.min.mjs';

export const decoders = [];
export const encoders = [];

export function registerDecoder(decoder) {
  decoders.push(decoder);
  baseRegisterDecoder(decoder);
}

export function registerEncoder(encoder) {
  encoders.push(encoder);
  baseRegisterEncoder(encoder);
}

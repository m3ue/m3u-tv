#!/bin/bash
# Downloads the prebuilt files the web build needs into web/, where
# `flutter build web` / `flutter run -d chrome` pick them up:
#
#   web/drift_worker.js - drift's web worker, from the drift release
#   web/sqlite3.wasm    - sqlite3 compiled to WebAssembly, from the sqlite3 release
#   web/js/hls.min.js   - hls.js, for WebVideoBackend's HLS playback
#   web/js/mpegts.min.js - mpegts.js, for WebVideoBackend's raw MPEG-TS playback
#   web/js/mediabunny.min.mjs - Mediabunny, for web/mkv_player.mjs's MKV playback
#   web/js/mediabunny-ac3.min.mjs - Mediabunny's AC-3/E-AC-3 decoder (FFmpeg, WASM)
#   web/js/mediabunny-aac-encoder.min.mjs - Mediabunny's AAC encoder (FFmpeg, WASM)
#   web/js/licenses/ffmpeg/ - FFmpeg's LGPL license files for the two above
#
# drift_worker.js/sqlite3.wasm must match the drift and sqlite3 package
# versions the app is built with, so those two are read from pubspec.lock
# rather than pinned here: a mismatched worker or module fails only at
# runtime, in the browser. hls.js/mpegts.js/Mediabunny aren't Dart packages,
# so their versions are pinned directly below -- bump them here when
# upgrading (and update the *_SHA256 pins alongside MEDIABUNNY_VERSION; the
# @mediabunny/* extensions are released in lockstep with the core package).
# None of these files are committed (see .gitignore). Re-run after bumping
# drift, sqlite3, or the pinned JS versions; it is a no-op while
# web/.web_assets already records the versions last fetched.
#
# Usage: scripts/fetch-web-assets.sh   (from flutter_client/)

set -euo pipefail

cd "$(dirname "$0")/.."

HLS_JS_VERSION="1.7.3"
MPEGTS_JS_VERSION="1.8.2"
MEDIABUNNY_VERSION="1.65.2"
MEDIABUNNY_SHA256="08149edcc8cf980da65d94a0a54a8fc0fa85a65f89b66f55c906f33618363919"
MEDIABUNNY_AC3_SHA256="ebb5b643b73b610215cb2456a719ef4fc842e2a6036a96707806632f98096e9d"
MEDIABUNNY_AAC_ENCODER_SHA256="f7ef810c56d7f018929ed0954cdb82670bf2ad0bb988e75bc1a2f3d8bc23495f"

locked_version() {
  awk -v pkg="  $1:" '$0 == pkg { found = 1 } found && /^    version:/ { gsub(/"/, "", $2); print $2; exit }' pubspec.lock
}

DRIFT_VERSION="$(locked_version drift)"
SQLITE3_VERSION="$(locked_version sqlite3)"
if [ -z "$DRIFT_VERSION" ] || [ -z "$SQLITE3_VERSION" ]; then
  echo "ERROR: could not read the drift/sqlite3 versions from pubspec.lock (run flutter pub get)." >&2
  exit 1
fi

STAMP="web/.web_assets"
WANTED="drift=$DRIFT_VERSION sqlite3=$SQLITE3_VERSION hls.js=$HLS_JS_VERSION mpegts.js=$MPEGTS_JS_VERSION mediabunny=$MEDIABUNNY_VERSION mediabunny-audio=ac3,aac-encoder"
if [ -f "$STAMP" ] && [ "$(cat "$STAMP")" = "$WANTED" ] &&
  [ -s web/drift_worker.js ] && [ -s web/sqlite3.wasm ] &&
  [ -s web/js/hls.min.js ] && [ -s web/js/mpegts.min.js ] &&
  [ -s web/js/mediabunny.min.mjs ] && [ -s web/js/mediabunny-ac3.min.mjs ] &&
  [ -s web/js/mediabunny-aac-encoder.min.mjs ]; then
  echo "Web assets already match pubspec.lock / pinned versions ($WANTED)."
  exit 0
fi

mkdir -p web/js

download() {
  local url="$1" dest="$2"
  echo "Fetching $url"
  curl --fail --location --silent --show-error --retry 3 --retry-all-errors \
    --output "$dest.tmp" "$url"
  mv "$dest.tmp" "$dest"
}

download "https://github.com/simolus3/drift/releases/download/drift-$DRIFT_VERSION/drift_worker.js" web/drift_worker.js
download "https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-$SQLITE3_VERSION/sqlite3.wasm" web/sqlite3.wasm
download "https://cdn.jsdelivr.net/npm/hls.js@$HLS_JS_VERSION/dist/hls.min.js" web/js/hls.min.js
download "https://cdn.jsdelivr.net/npm/mpegts.js@$MPEGTS_JS_VERSION/dist/mpegts.min.js" web/js/mpegts.min.js
download "https://cdn.jsdelivr.net/npm/mediabunny@$MEDIABUNNY_VERSION/dist/bundles/mediabunny.min.mjs" web/js/mediabunny.min.mjs
download "https://cdn.jsdelivr.net/npm/@mediabunny/ac3@$MEDIABUNNY_VERSION/dist/bundles/mediabunny-ac3.min.mjs" web/js/mediabunny-ac3.min.mjs
download "https://cdn.jsdelivr.net/npm/@mediabunny/aac-encoder@$MEDIABUNNY_VERSION/dist/bundles/mediabunny-aac-encoder.min.mjs" web/js/mediabunny-aac-encoder.min.mjs
mkdir -p web/js/licenses/ffmpeg
download "https://cdn.jsdelivr.net/npm/@mediabunny/ac3@$MEDIABUNNY_VERSION/licenses/ffmpeg/COPYING.LGPLv2.1" web/js/licenses/ffmpeg/COPYING.LGPLv2.1
download "https://cdn.jsdelivr.net/npm/@mediabunny/ac3@$MEDIABUNNY_VERSION/licenses/ffmpeg/LICENSE.md" web/js/licenses/ffmpeg/LICENSE.md

# A CDN error page or truncated body still downloads "successfully".
if [ "$(head -c 4 web/sqlite3.wasm | od -An -tx1 | tr -d ' \n')" != "0061736d" ]; then
  echo "ERROR: web/sqlite3.wasm is not a WebAssembly module." >&2
  exit 1
fi
if head -c 512 web/drift_worker.js | grep -qi '<html'; then
  echo "ERROR: web/drift_worker.js is an HTML page, not the worker script." >&2
  exit 1
fi
if head -c 512 web/js/hls.min.js | grep -qi '<html'; then
  echo "ERROR: web/js/hls.min.js is an HTML page, not the hls.js bundle." >&2
  exit 1
fi
if head -c 512 web/js/mpegts.min.js | grep -qi '<html'; then
  echo "ERROR: web/js/mpegts.min.js is an HTML page, not the mpegts.js bundle." >&2
  exit 1
fi

verify_sha256() {
  local file="$1" expected="$2" actual
  actual="$(shasum -a 256 "$file" | awk '{print $1}')"
  if [ "$actual" != "$expected" ]; then
    rm -f "$file"
    echo "ERROR: $file sha256 $actual does not match the pinned $expected." >&2
    exit 1
  fi
}
verify_sha256 web/js/mediabunny.min.mjs "$MEDIABUNNY_SHA256"
verify_sha256 web/js/mediabunny-ac3.min.mjs "$MEDIABUNNY_AC3_SHA256"
verify_sha256 web/js/mediabunny-aac-encoder.min.mjs "$MEDIABUNNY_AAC_ENCODER_SHA256"

echo "$WANTED" > "$STAMP"
echo "Web assets ready ($WANTED)."

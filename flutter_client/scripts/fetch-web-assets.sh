#!/bin/bash
# Downloads the prebuilt files the web build needs into web/, where
# `flutter build web` / `flutter run -d chrome` pick them up:
#
#   web/drift_worker.js - drift's web worker, from the drift release
#   web/sqlite3.wasm    - sqlite3 compiled to WebAssembly, from the sqlite3 release
#   web/js/hls.min.js   - hls.js, for WebVideoBackend's HLS playback
#   web/js/mpegts.min.js - mpegts.js, for WebVideoBackend's raw MPEG-TS playback
#
# drift_worker.js/sqlite3.wasm must match the drift and sqlite3 package
# versions the app is built with, so those two are read from pubspec.lock
# rather than pinned here: a mismatched worker or module fails only at
# runtime, in the browser. hls.js/mpegts.js aren't Dart packages, so their
# versions are pinned directly below -- bump them here when upgrading.
# None of these files are committed (see .gitignore). Re-run after bumping
# drift, sqlite3, or the pinned JS versions; it is a no-op while
# web/.web_assets already records the versions last fetched.
#
# Usage: scripts/fetch-web-assets.sh   (from flutter_client/)

set -euo pipefail

cd "$(dirname "$0")/.."

HLS_JS_VERSION="1.7.3"
MPEGTS_JS_VERSION="1.8.2"

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
WANTED="drift=$DRIFT_VERSION sqlite3=$SQLITE3_VERSION hls.js=$HLS_JS_VERSION mpegts.js=$MPEGTS_JS_VERSION"
if [ -f "$STAMP" ] && [ "$(cat "$STAMP")" = "$WANTED" ] &&
  [ -s web/drift_worker.js ] && [ -s web/sqlite3.wasm ] &&
  [ -s web/js/hls.min.js ] && [ -s web/js/mpegts.min.js ]; then
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

echo "$WANTED" > "$STAMP"
echo "Web assets ready ($WANTED)."

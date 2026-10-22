#!/bin/bash
# Downloads the two prebuilt files the web build's SQLite catalog needs into
# web/, where `flutter build web` / `flutter run -d chrome` pick them up:
#
#   web/drift_worker.js - drift's web worker, from the drift release
#   web/sqlite3.wasm    - sqlite3 compiled to WebAssembly, from the sqlite3 release
#
# Both must match the drift and sqlite3 package versions the app is built
# with, so the versions are read from pubspec.lock rather than pinned here: a
# mismatched worker or module fails only at runtime, in the browser. Neither
# file is committed (see .gitignore). Re-run after bumping drift or sqlite3;
# it is a no-op while web/.web_assets already records the locked versions.
#
# Usage: scripts/fetch-web-assets.sh   (from flutter_client/)

set -euo pipefail

cd "$(dirname "$0")/.."

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
WANTED="drift=$DRIFT_VERSION sqlite3=$SQLITE3_VERSION"
if [ -f "$STAMP" ] && [ "$(cat "$STAMP")" = "$WANTED" ] &&
  [ -s web/drift_worker.js ] && [ -s web/sqlite3.wasm ]; then
  echo "Web assets already match pubspec.lock ($WANTED)."
  exit 0
fi

download() {
  local url="$1" dest="$2"
  echo "Fetching $url"
  curl --fail --location --silent --show-error --retry 3 --retry-all-errors \
    --output "$dest.tmp" "$url"
  mv "$dest.tmp" "$dest"
}

download "https://github.com/simolus3/drift/releases/download/drift-$DRIFT_VERSION/drift_worker.js" web/drift_worker.js
download "https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-$SQLITE3_VERSION/sqlite3.wasm" web/sqlite3.wasm

# A CDN error page or truncated body still downloads "successfully".
if [ "$(head -c 4 web/sqlite3.wasm | od -An -tx1 | tr -d ' \n')" != "0061736d" ]; then
  echo "ERROR: web/sqlite3.wasm is not a WebAssembly module." >&2
  exit 1
fi
if head -c 512 web/drift_worker.js | grep -qi '<html'; then
  echo "ERROR: web/drift_worker.js is an HTML page, not the worker script." >&2
  exit 1
fi

echo "$WANTED" > "$STAMP"
echo "Web assets ready ($WANTED)."

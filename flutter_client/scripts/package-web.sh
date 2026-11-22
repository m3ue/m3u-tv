#!/bin/bash
# Builds the web app for M3U Editor's /m3u-tv/ route and packages it as the
# release assets M3U Editor installs from (Settings > M3U TV):
#
#   build/web-release/m3u-tv-v<version>-web.zip         the built app
#   build/web-release/m3u-tv-v<version>-web.zip.sha256  its checksum
#   build/web-release/m3u-tv-v<version>-web.json        install manifest
#
# The manifest (also inside the zip as m3u-tv-web.json) carries the version,
# build number, the zip's sha256 and the oldest M3U Editor version the build
# works with, so the editor can check compatibility before downloading.
#
# Build choices: Wasm with the JS fallback; --no-web-resources-cdn so the
# Flutter renderer is served by the editor too (works on LANs without
# internet, and opening the app doesn't contact Google's CDN);
# --web-content-hash so browsers fetch new entrypoints after an update (the
# editor serves index.html/flutter_bootstrap.js with revalidation); no
# source maps.
#
# Usage: scripts/package-web.sh <version> [build-number]   (from flutter_client/)
#   MIN_EDITOR_VERSION overrides the minimum M3U Editor version below.

set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${1:?usage: scripts/package-web.sh <version> [build-number]}"
VERSION="${VERSION#v}"
BUILD_NUMBER="${2:-1}"
# Oldest M3U Editor release whose API this web build supports. Raise it when
# the app starts depending on a newer editor endpoint or field.
MIN_EDITOR_VERSION="${MIN_EDITOR_VERSION:-0.14.5}"

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "ERROR: version must look like 1.2.3 (got '$VERSION')." >&2
  exit 1
fi

OUT_DIR="build/web-release"
NAME="m3u-tv-v${VERSION}-web"
STAGE="build/web"

bash scripts/fetch-web-assets.sh

flutter build web \
  --release \
  --wasm \
  --no-web-resources-cdn \
  --web-content-hash \
  --no-source-maps \
  --base-href /m3u-tv/ \
  --build-name "$VERSION" \
  --build-number "$BUILD_NUMBER"

rm -f "$STAGE/.last_build_id" "$STAGE/.web_assets"
# The renderer's debug symbol files (about 8 MB) aren't loaded at runtime.
find "$STAGE" -name '*.symbols' -delete

manifest() {
  local sha256="$1"
  cat <<JSON
{
  "name": "m3u-tv-web",
  "version": "${VERSION}",
  "build_number": "${BUILD_NUMBER}",
  "min_editor_version": "${MIN_EDITOR_VERSION}",
  "base_href": "/m3u-tv/",
  "archive": "${NAME}.zip",
  "archive_sha256": "${sha256}"
}
JSON
}

# The copy inside the zip can't contain the zip's own hash.
manifest "" > "$STAGE/m3u-tv-web.json"

mkdir -p "$OUT_DIR"
rm -f "$OUT_DIR/$NAME.zip" "$OUT_DIR/$NAME.zip.sha256" "$OUT_DIR/$NAME.json"
(cd "$STAGE" && zip -qr -9 "../../$OUT_DIR/$NAME.zip" .)

SHA256="$(cd "$OUT_DIR" && shasum -a 256 "$NAME.zip" | awk '{print $1}')"
echo "$SHA256  $NAME.zip" > "$OUT_DIR/$NAME.zip.sha256"
manifest "$SHA256" > "$OUT_DIR/$NAME.json"

echo "Packaged $OUT_DIR/$NAME.zip ($(du -h "$OUT_DIR/$NAME.zip" | cut -f1), sha256 $SHA256)"

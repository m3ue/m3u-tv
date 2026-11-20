#!/usr/bin/env bash
# Serves a fake "latest release" for testing the Android in-app updater
# without publishing a GitHub release.
#
# Usage: scripts/serve-test-update.sh <path/to/new.apk> <version> [port]
#
# 1. Build and install the "old" app, pointed at this feed:
#      flutter build apk --release --build-number=1 \
#        --dart-define=M3UTV_SIDELOAD_UPDATER=true \
#        --dart-define=M3UTV_UPDATE_FEED_URL=http://<this-mac-ip>:8765/release.json
# 2. Build the "new" app with a higher build number, same signing key:
#      flutter build apk --release --build-name=9.9.9 --build-number=999 \
#        --dart-define=M3UTV_SIDELOAD_UPDATER=true
# 3. Serve it (version must be newer than pubspec.yaml's):
#      scripts/serve-test-update.sh new.apk 9.9.9
#
# Set HOST to override the detected LAN address. Ctrl+C stops the server.
set -euo pipefail

APK="${1:?usage: $0 <apk> <version> [port]}"
VERSION="${2:?usage: $0 <apk> <version> [port]}"
PORT="${3:-8765}"
HOST="${HOST:-$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || true)}"
if [ -z "$HOST" ]; then
  echo "Couldn't detect a LAN address; set HOST=<ip>." >&2
  exit 1
fi

DIR="$(mktemp -d -t m3utv-update)"
NAME="m3u-tv-v${VERSION}-android.apk"
cp "$APK" "$DIR/$NAME"
(cd "$DIR" && shasum -a 256 "$NAME" > "$NAME.sha256")
SIZE=$(stat -f%z "$DIR/$NAME")
BASE="http://${HOST}:${PORT}"

cat > "$DIR/release.json" <<JSON
{
  "tag_name": "v${VERSION}",
  "assets": [
    {"name": "${NAME}", "size": ${SIZE}, "browser_download_url": "${BASE}/${NAME}"},
    {"name": "${NAME}.sha256", "size": 0, "browser_download_url": "${BASE}/${NAME}.sha256"}
  ]
}
JSON

echo "Feed: ${BASE}/release.json  (serving ${DIR})"
exec python3 -m http.server "$PORT" --bind 0.0.0.0 --directory "$DIR"

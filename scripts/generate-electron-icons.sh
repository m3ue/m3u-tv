#!/usr/bin/env bash
# generate-electron-icons.sh
#
# Generates Electron app icons from icon.png at the project root.
#
# Source:  icon.png (must be ≥ 2048x2048)
# Outputs: electron/images/icon.png       (1024x1024)
#          electron/images/icon@2x.png    (2048x2048)
#          electron/images/icon.icns      (multi-size Apple icon bundle)
#
# Usage (run from the m3u-tv/ directory):
#   ./scripts/generate-electron-icons.sh

set -euo pipefail
cd "$(dirname "$0")/.."

SRC="icon.png"
OUT="electron/images"

log() { printf "  [generate-electron-icons] %s\n" "$*"; }
die() { printf "\nERROR: %s\n" "$*" >&2; exit 1; }

[[ -f "$SRC" ]]             || die "Source icon not found: $SRC"
command -v sips     &>/dev/null || die "sips not found (macOS only)"
command -v iconutil &>/dev/null || die "iconutil not found — install Xcode CLT: xcode-select --install"

W=$(sips -g pixelWidth  "$SRC" | awk '/pixelWidth/{print $2}')
H=$(sips -g pixelHeight "$SRC" | awk '/pixelHeight/{print $2}')
[[ "$W" -ge 2048 && "$H" -ge 2048 ]] || die "Source must be at least 2048x2048 (got ${W}x${H})"

mkdir -p "$OUT"

log "icon@2x.png  → 2048x2048"
sips -z 2048 2048 "$SRC" --out "$OUT/icon@2x.png" > /dev/null

log "icon.png     → 1024x1024"
sips -z 1024 1024 "$SRC" --out "$OUT/icon.png" > /dev/null

log "icon.icns    → building iconset…"
ICONSET="$(mktemp -d)/icon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 64 128 256 512 1024; do
  sips -z $size $size "$SRC" --out "$ICONSET/icon_${size}x${size}.png" > /dev/null
  [[ $((size * 2)) -le 2048 ]] && \
    sips -z $((size * 2)) $((size * 2)) "$SRC" --out "$ICONSET/icon_${size}x${size}@2x.png" > /dev/null
done
iconutil -c icns "$ICONSET" -o "$OUT/icon.icns"
rm -rf "$(dirname "$ICONSET")"

log "Done:"
log "  $OUT/icon.png      (1024x1024)"
log "  $OUT/icon@2x.png   (2048x2048)"
log "  $OUT/icon.icns     ($(du -sh "$OUT/icon.icns" | cut -f1))"

#!/bin/bash
# Store listing art (headers, banners, tile icon) for m3u-tv. Screenshots are
# generate-screenshots.sh; this covers everything else.
#
#   Apple App Store (iOS only, App Store Connect > Product Page)
#     apple/ios-header/                Header (5244x2950, 3840x1646). Devices, no text.
#     apple/ios-search-results/        Search Results (5244x2950, 3840x2560, 1920x1280).
#                                      Copy + devices, plus -notext variants in case
#                                      the English copy is a problem for other locales.
#   Google Play
#     google/android-feature-graphic/  Feature graphic (1024x500). Copy + devices, kept
#                                      inside the centred 16:9 Play crops it to.
#     google/android-tv-banner/        TV banner (1280x720). Copy + devices.
#   Microsoft Store (Partner Center > Store listings)
#     microsoft/app-tile-icon-300x300.png     "1:1 App tile icon". Overrides the
#                                             package tile, so this is where the
#                                             icon padding comes from.
#     microsoft/super-hero-art-3840x2160.png  "16:9 Super hero art" (listing
#                                             banner). Store policy: no text.
#     microsoft/feature-3840x2160.png         The TV social card at 16:9, for the
#                                             first desktop screenshot.
#
# Everything but the tile icon is rendered from scripts/store-assets/art.html
# with headless Chrome, using tv1/tablet3/mobile5 from
# screenshots/app-screenshots/, so refreshing those screenshots and re-running
# this is all an update needs. The template adapts to each output's aspect
# ratio. Apple and Google variants drop the site URL (Apple prohibits URLs).
#
# Outputs are written to screenshots/store/.
#
# Prerequisites: Google Chrome (or set $CHROME), ImageMagick (magick)
#   brew install imagemagick
#
# Usage:
#   scripts/generate-store-assets.sh
#   TILE_PADDING=12 scripts/generate-store-assets.sh   # % of transparent margin

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLUTTER_DIR="$(dirname "$SCRIPT_DIR")"
TEMPLATE="$SCRIPT_DIR/store-assets/art.html"
ICON="$FLUTTER_DIR/assets/icons/icon-desktop.png"
OUT_DIR="$FLUTTER_DIR/screenshots/store"
CHROME="${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
TILE_PADDING="${TILE_PADDING:-8}"

[[ -x "$CHROME" ]] || {
    echo "Error: Chrome not found at: $CHROME"
    echo "Set CHROME to the Chrome or Chromium binary."
    exit 1
}

command -v magick &>/dev/null || {
    echo "Error: 'magick' not found."
    echo "Install with: brew install imagemagick"
    exit 1
}

[[ -f "$ICON" ]] || {
    echo "Error: $ICON not found (run scripts/setup-icons.sh first)"
    exit 1
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Render the template at an exact output size. The page is always 1200 CSS px
# wide (its design width) with the height following the target aspect ratio,
# captured at >= 2x for crisp text, then resized to the exact pixel size. The
# page loads its font from Google Fonts, hence the virtual-time budget.
# Args: query, width, height, output_path
render() {
    local query=$1 width=$2 height=$3 dest=$4
    local page_h scale shot="$TMP/shot.png"
    page_h=$(( (1200 * height + width / 2) / width ))
    scale=$(awk -v w="$width" 'BEGIN { s = w / 1200; if (s < 2) s = 2; printf "%.4f", s }')
    mkdir -p "$(dirname "$dest")"
    "$CHROME" --headless=new --disable-gpu --hide-scrollbars \
        --allow-file-access-from-files \
        --force-device-scale-factor="$scale" \
        --window-size="1200,$page_h" \
        --virtual-time-budget=5000 \
        --screenshot="$shot" \
        "file://$TEMPLATE?$query" > /dev/null 2>&1
    magick "$shot" -resize "${width}x${height}!" -alpha off -strip "PNG24:$dest"
    echo "  ✓ ${dest#"$OUT_DIR"/} ($(du -k "$dest" | cut -f1) KB)"
}

echo "Store listing art -> ${OUT_DIR#"$FLUTTER_DIR"/}"

echo ""
echo "--- Apple App Store (iOS) ---"
render "art=hero" 5244 2950 "$OUT_DIR/apple/ios-header/header-5244x2950.png"
render "art=hero" 3840 1646 "$OUT_DIR/apple/ios-header/header-3840x1646.png"
for size in 5244x2950 3840x2560 1920x1280; do
    w=${size%x*} h=${size#*x}
    render "art=feature&url=0" "$w" "$h" "$OUT_DIR/apple/ios-search-results/search-results-$size.png"
    render "art=hero" "$w" "$h" "$OUT_DIR/apple/ios-search-results/search-results-$size-notext.png"
done

echo ""
echo "--- Google Play ---"
render "art=feature&url=0&safe=1.7778" 1024 500 "$OUT_DIR/google/android-feature-graphic/feature-graphic.png"
render "art=feature&url=0" 1280 720 "$OUT_DIR/google/android-tv-banner/tv-banner.png"

echo ""
echo "--- Microsoft Store ---"
mkdir -p "$OUT_DIR/microsoft"
inner=$(( 300 - 2 * 300 * TILE_PADDING / 100 ))
magick "$ICON" -resize "${inner}x${inner}" \
    -background none -gravity center -extent 300x300 \
    -depth 8 "PNG32:$OUT_DIR/microsoft/app-tile-icon-300x300.png"
echo "  ✓ microsoft/app-tile-icon-300x300.png (${TILE_PADDING}% padding)"
render "art=hero" 3840 2160 "$OUT_DIR/microsoft/super-hero-art-3840x2160.png"
render "art=feature" 3840 2160 "$OUT_DIR/microsoft/feature-3840x2160.png"

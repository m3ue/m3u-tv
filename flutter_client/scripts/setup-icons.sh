#!/bin/bash
# Icon + splash generation for m3u-tv/flutter_client
#
# Generates all platform icons and splash screens from the SVG source at
# m3u-tv/logo.svg, including tvOS layered icons (not handled by
# flutter_launcher_icons).
#
# Prerequisites: librsvg (rsvg-convert), ImageMagick (magick)
#   brew install librsvg imagemagick
#
# Run from anywhere — the script resolves its own paths.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLUTTER_DIR="$(dirname "$SCRIPT_DIR")"   # flutter_client/
TV_ROOT="$(dirname "$FLUTTER_DIR")"      # m3u-tv/
ICONS_DIR="$FLUTTER_DIR/assets/icons"
SVG="$TV_ROOT/logo.svg"
TVOS_ASSETS="$FLUTTER_DIR/tvos/Runner/Assets.xcassets/AppIcon.brandassets"

APP_BG="#0a0a0f"    # App surface colour (used for icon.png, splash, android)
TVOS_BG="#1c1c1e"   # tvOS system dark (used for tvOS icon layers + top shelf)

# Prerequisites
for cmd in rsvg-convert magick; do
    command -v "$cmd" &>/dev/null || {
        echo "Error: '$cmd' not found."
        echo "Install with: brew install librsvg imagemagick"
        exit 1
    }
done

[[ -f "$SVG" ]] || { echo "Error: SVG source not found at $SVG"; exit 1; }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Render the SVG at a given pixel size (cached in $TMP).
# Args: size → echoes the path to the rendered PNG.
render_logo() {
    local size=$1
    local out="$TMP/logo_${size}.png"
    [[ -f "$out" ]] || rsvg-convert -w "$size" -h "$size" "$SVG" -o "$out"
    echo "$out"
}

# Composite a padded logo on a coloured canvas and write 8-bit RGBA PNG.
# Args: canvas_size, padding_pct, bg_color, logo_path, output_path
composite_square() {
    local size=$1 padding=$2 bg=$3 logo=$4 output=$5
    magick -size "${size}x${size}" xc:"$bg" \
        "$logo" -gravity center -composite \
        -depth 8 "PNG32:$output"
}

# ---------------------------------------------------------------------------
echo "=== Step 1: Render source PNGs from SVG ==="
# ---------------------------------------------------------------------------
mkdir -p "$ICONS_DIR"

# Logo render sizes (padding applied so the logo never touches canvas edges).
#   icon.png:         1024 px canvas, 10 % padding → 819 px logo
#   adaptive-icon.png: 1024 px canvas, 20 % padding → 614 px logo
#   splash-icon.png:    512 px canvas, 10 % padding → 409 px logo
LOGO_819=$(render_logo 819)
LOGO_614=$(render_logo 614)
LOGO_409=$(render_logo 409)

# icon.png — opaque dark background (required by iOS, macOS, Windows)
composite_square 1024 10 "$APP_BG" "$LOGO_819" "$ICONS_DIR/icon.png"

# adaptive-icon.png — dark background + 20 % padding (Android adaptive safe zone)
composite_square 1024 20 "$APP_BG" "$LOGO_614" "$ICONS_DIR/adaptive-icon.png"

# splash-icon.png — dark background + 10 % padding
composite_square 512 10 "$APP_BG" "$LOGO_409" "$ICONS_DIR/splash-icon.png"

echo "  icon.png, adaptive-icon.png, splash-icon.png written to $ICONS_DIR"

# ---------------------------------------------------------------------------
echo ""
echo "=== Step 2: flutter pub get ==="
# ---------------------------------------------------------------------------
cd "$FLUTTER_DIR"
flutter pub get

# ---------------------------------------------------------------------------
echo ""
echo "=== Step 3: Generate app icons (Android, iOS, macOS, Web, Windows, Linux) ==="
# ---------------------------------------------------------------------------
dart run flutter_launcher_icons

# ---------------------------------------------------------------------------
echo ""
echo "=== Step 4: Generate splash screens (Android + iOS) ==="
# ---------------------------------------------------------------------------
dart run flutter_native_splash:create

# ---------------------------------------------------------------------------
echo ""
echo "=== Step 5: Generate tvOS layered icons and Top Shelf image ==="
# ---------------------------------------------------------------------------
# flutter_launcher_icons does not cover tvOS. Each icon is a stack of
# transparent-background layers (Back / Middle / Front) composited by tvOS
# for the parallax effect.  Required sizes:
#   Large icon (focused):  1280×768 px
#   Small icon (shelf):     400×240 px (1x),  800×480 px (2x)
#   Top Shelf image:       2320×720 px (Top Shelf Image Wide)

LOGO_640=$(render_logo 640)
LOGO_580=$(render_logo 580)
LOGO_200=$(render_logo 200)
LOGO_400=$(render_logo 400)

LARGE="$TVOS_ASSETS/App Icon - Large.imagestack"
SMALL="$TVOS_ASSETS/App Icon - Small.imagestack"
SHELF="$TVOS_ASSETS/Top Shelf Image.imageset"

# Large — Back: dark background only
magick -size 1280x768 xc:"$TVOS_BG" -depth 8 \
    "$LARGE/Back.imagestacklayer/Content.imageset/large_back.png"

# Large — Front + Middle: transparent canvas, logo centred
for layer in Front Middle; do
    lower=$(echo "$layer" | tr '[:upper:]' '[:lower:]')
    magick -size 1280x768 xc:none "$LOGO_640" -gravity center -composite \
        -depth 8 "PNG32:$LARGE/${layer}.imagestacklayer/Content.imageset/large_${lower}.png"
done

# Small — Back: dark background only (1x + 2x)
magick -size 400x240 xc:"$TVOS_BG" -depth 8 \
    "$SMALL/Back.imagestacklayer/Content.imageset/small_back.png"
magick -size 800x480 xc:"$TVOS_BG" -depth 8 \
    "$SMALL/Back.imagestacklayer/Content.imageset/small_back@2x.png"

# Small — Front + Middle: transparent canvas, logo centred (1x + 2x)
for layer in Front Middle; do
    lower=$(echo "$layer" | tr '[:upper:]' '[:lower:]')
    magick -size 400x240 xc:none "$LOGO_200" -gravity center -composite \
        -depth 8 "PNG32:$SMALL/${layer}.imagestacklayer/Content.imageset/small_${lower}.png"
    magick -size 800x480 xc:none "$LOGO_400" -gravity center -composite \
        -depth 8 "PNG32:$SMALL/${layer}.imagestacklayer/Content.imageset/small_${lower}@2x.png"
done

# Top Shelf — dark background, logo centred and proportional (2320×720, Wide)
magick -size 2320x720 xc:"$TVOS_BG" "$LOGO_580" -gravity center -composite \
    -depth 8 "$SHELF/top_shelf.png"

echo "  tvOS layered icons and Top Shelf image written to $TVOS_ASSETS"

# ---------------------------------------------------------------------------
echo ""
echo "=== Done ==="
echo "All icons and splash screens are up to date."
echo "Rebuild the tvOS target in Xcode to pick up the refreshed icons."

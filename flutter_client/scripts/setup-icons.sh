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

# ---------------------------------------------------------------------------
echo "=== Step 1: Render source PNGs from SVG ==="
# ---------------------------------------------------------------------------
mkdir -p "$ICONS_DIR"

rsvg-convert -w 1024 -h 1024 "$SVG" -o "$TMP/logo_1024_transparent.png"
rsvg-convert -w 512  -h 512  "$SVG" -o "$TMP/logo_512_transparent.png"

# icon.png — opaque dark background (required by iOS, macOS, Windows)
magick -size 1024x1024 xc:"$APP_BG" \
    "$TMP/logo_1024_transparent.png" -gravity center -composite \
    "$ICONS_DIR/icon.png"

# adaptive-icon.png — transparent foreground for Android adaptive icon
cp "$TMP/logo_1024_transparent.png" "$ICONS_DIR/adaptive-icon.png"

# splash-icon.png — transparent, centred on the splash background colour
cp "$TMP/logo_512_transparent.png" "$ICONS_DIR/splash-icon.png"

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
#   Top Shelf image:       1920×720 px

rsvg-convert -w 640 -h 640 "$SVG" -o "$TMP/logo_640.png"
rsvg-convert -w 580 -h 580 "$SVG" -o "$TMP/logo_580.png"
rsvg-convert -w 200 -h 200 "$SVG" -o "$TMP/logo_200.png"
rsvg-convert -w 400 -h 400 "$SVG" -o "$TMP/logo_400.png"

LARGE="$TVOS_ASSETS/App Icon - Large.imagestack"
SMALL="$TVOS_ASSETS/App Icon - Small.imagestack"
SHELF="$TVOS_ASSETS/Top Shelf Image.imageset"

# Large — Back: dark background only
magick -size 1280x768 xc:"$TVOS_BG" \
    "$LARGE/Back.imagestacklayer/Content.imageset/large_back.png"

# Large — Front + Middle: transparent canvas, logo centred
for layer in Front Middle; do
    lower=$(echo "$layer" | tr '[:upper:]' '[:lower:]')
    magick -size 1280x768 xc:none "$TMP/logo_640.png" -gravity center -composite \
        "$LARGE/${layer}.imagestacklayer/Content.imageset/large_${lower}.png"
done

# Small — Back: dark background only (1x + 2x)
magick -size 400x240 xc:"$TVOS_BG" \
    "$SMALL/Back.imagestacklayer/Content.imageset/small_back.png"
magick -size 800x480 xc:"$TVOS_BG" \
    "$SMALL/Back.imagestacklayer/Content.imageset/small_back@2x.png"

# Small — Front + Middle: transparent canvas, logo centred (1x + 2x)
for layer in Front Middle; do
    lower=$(echo "$layer" | tr '[:upper:]' '[:lower:]')
    magick -size 400x240 xc:none "$TMP/logo_200.png" -gravity center -composite \
        "$SMALL/${layer}.imagestacklayer/Content.imageset/small_${lower}.png"
    magick -size 800x480 xc:none "$TMP/logo_400.png" -gravity center -composite \
        "$SMALL/${layer}.imagestacklayer/Content.imageset/small_${lower}@2x.png"
done

# Top Shelf — dark background, logo centred and proportional (1920×720)
magick -size 1920x720 xc:"$TVOS_BG" "$TMP/logo_580.png" -gravity center -composite \
    "$SHELF/top_shelf.png"

echo "  tvOS layered icons and Top Shelf image written to $TVOS_ASSETS"

# ---------------------------------------------------------------------------
echo ""
echo "=== Done ==="
echo "All icons and splash screens are up to date."
echo "Rebuild the tvOS target in Xcode to pick up the refreshed icons."

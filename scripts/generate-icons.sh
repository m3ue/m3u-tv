#!/bin/bash

# Icon Generation Script for M3U TV App
# Generates all required app icons and TV icons from SVG source
# Requires: librsvg (brew install librsvg) and ImageMagick (brew install imagemagick)

set -e

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"

# Default source SVG (can be overridden with first argument)
SOURCE_SVG="${1:-$ROOT_DIR/logo.svg}"

# Output directories
ASSETS_DIR="$ROOT_DIR/assets"
TV_ICONS_DIR="$ASSETS_DIR/tv_icons"

# Background color for icons (matches splash background in app.json)
BG_COLOR="#0a0a0f"

# Check dependencies
if ! command -v rsvg-convert &> /dev/null; then
    echo "Error: rsvg-convert is not installed."
    echo "Install it with: brew install librsvg"
    exit 1
fi

if ! command -v magick &> /dev/null && ! command -v convert &> /dev/null; then
    echo "Error: ImageMagick is not installed."
    echo "Install it with: brew install imagemagick"
    exit 1
fi

# Detect ImageMagick command
if command -v magick &> /dev/null; then
    MAGICK_CMD="magick"
else
    MAGICK_CMD="convert"
fi

# Check if source SVG exists
if [ ! -f "$SOURCE_SVG" ]; then
    echo "Error: Source SVG not found at: $SOURCE_SVG"
    echo "Usage: $0 [path/to/source.svg]"
    exit 1
fi

echo "Generating icons from: $SOURCE_SVG"
echo "Output directory: $ASSETS_DIR"

# Create directories if they don't exist
mkdir -p "$ASSETS_DIR"
mkdir -p "$TV_ICONS_DIR"

# Create a temporary directory for intermediate files
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

# Function to generate a square icon with centered logo
generate_square_icon() {
    local size=$1
    local output=$2
    local padding=${3:-15}  # Default 15% padding

    # Calculate logo size with padding
    local logo_size=$(echo "$size * (100 - $padding * 2) / 100" | bc)

    echo "  Generating $output (${size}x${size})..."

    # Render SVG to PNG at the logo size using rsvg-convert
    rsvg-convert -w "$logo_size" -h "$logo_size" "$SOURCE_SVG" -o "$TEMP_DIR/logo.png"

    # Create background and composite the logo centered
    $MAGICK_CMD -size "${size}x${size}" "xc:$BG_COLOR" \
        "$TEMP_DIR/logo.png" -gravity center -composite \
        -type TrueColorAlpha -depth 8 "PNG32:$output"
}

# Function to generate a rectangular TV icon with centered logo
generate_tv_icon() {
    local width=$1
    local height=$2
    local output=$3
    local padding=${4:-10}  # Default 10% padding for TV icons

    # Calculate the maximum logo size that fits within the bounds with padding
    local max_logo_width=$(echo "$width * (100 - $padding * 2) / 100" | bc)
    local max_logo_height=$(echo "$height * (100 - $padding * 2) / 100" | bc)

    # Use the smaller dimension to maintain aspect ratio
    local logo_size=$max_logo_height
    if [ "$max_logo_width" -lt "$max_logo_height" ]; then
        logo_size=$max_logo_width
    fi

    echo "  Generating $output (${width}x${height})..."

    # Render SVG to PNG at the logo size using rsvg-convert
    rsvg-convert -w "$logo_size" -h "$logo_size" "$SOURCE_SVG" -o "$TEMP_DIR/logo.png"

    # Create background and composite the logo centered
    $MAGICK_CMD -size "${width}x${height}" "xc:$BG_COLOR" \
        "$TEMP_DIR/logo.png" -gravity center -composite \
        -type TrueColorAlpha -depth 8 "PNG32:$output"
}

# Function to generate splash screen
generate_splash() {
    local width=$1
    local height=$2
    local output=$3
    local logo_size=${4:-400}  # Logo size for splash

    echo "  Generating $output (${width}x${height})..."

    # Render SVG to PNG at the logo size using rsvg-convert
    rsvg-convert -w "$logo_size" -h "$logo_size" "$SOURCE_SVG" -o "$TEMP_DIR/logo.png"

    # Create background and composite the logo centered
    $MAGICK_CMD -size "${width}x${height}" "xc:$BG_COLOR" \
        "$TEMP_DIR/logo.png" -gravity center -composite \
        -type TrueColorAlpha -depth 8 "PNG32:$output"
}

echo ""
echo "=== Generating Standard App Icons ==="

# Standard app icon (1024x1024)
generate_square_icon 1024 "$ASSETS_DIR/icon.png" 10

# Adaptive icon for Android (1024x1024)
generate_square_icon 1024 "$ASSETS_DIR/adaptive-icon.png" 20

echo ""
echo "=== Generating Splash Screen ==="

# Splash icon (used by app.json as splash-icon.png)
generate_splash 1920 1080 "$ASSETS_DIR/splash.png" 400
generate_square_icon 512 "$ASSETS_DIR/splash-icon.png" 10

echo ""
echo "=== Generating TV Icons ==="

# Android TV Banner / Apple TV iconSmall (400x240)
generate_tv_icon 400 240 "$TV_ICONS_DIR/icon-400x240.png"

# Apple TV iconSmall2x (800x480)
generate_tv_icon 800 480 "$TV_ICONS_DIR/icon-800x480.png"

# Apple TV icon (1280x768)
generate_tv_icon 1280 768 "$TV_ICONS_DIR/icon-1280x768.png"

# Apple TV topShelf (1920x720)
generate_tv_icon 1920 720 "$TV_ICONS_DIR/icon-1920x720.png"

# Apple TV topShelfWide (2320x720)
generate_tv_icon 2320 720 "$TV_ICONS_DIR/icon-2320x720.png"

# Apple TV topShelf2x (3840x1440)
generate_tv_icon 3840 1440 "$TV_ICONS_DIR/icon-3840x1440.png"

# Apple TV topShelfWide2x (4640x1440)
generate_tv_icon 4640 1440 "$TV_ICONS_DIR/icon-4640x1440.png"

echo ""
echo "=== Icon Generation Complete ==="
echo ""
echo "Generated icons:"
echo "  - $ASSETS_DIR/icon.png"
echo "  - $ASSETS_DIR/adaptive-icon.png"
echo "  - $ASSETS_DIR/splash.png"
echo "  - $ASSETS_DIR/splash-icon.png"
echo "  - $TV_ICONS_DIR/icon-400x240.png"
echo "  - $TV_ICONS_DIR/icon-800x480.png"
echo "  - $TV_ICONS_DIR/icon-1280x768.png"
echo "  - $TV_ICONS_DIR/icon-1920x720.png"
echo "  - $TV_ICONS_DIR/icon-2320x720.png"
echo "  - $TV_ICONS_DIR/icon-3840x1440.png"
echo "  - $TV_ICONS_DIR/icon-4640x1440.png"
echo ""
echo "Run 'expo prebuild --clean' to regenerate the native projects with the new icons."

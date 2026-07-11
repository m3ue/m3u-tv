#!/bin/bash
# Screenshot generation for m3u-tv App Store / Google Play submissions
#
# Generates all platform-specific screenshot sizes from source images in
# screenshots/app-screenshots/:
#
#   tv*.png      → Apple tvOS (1920×1080, 3840×2160)
#              → Android TV (1920×1080, 1280×720)
#   mobile*.png  → Apple iPhone (6.7", 6.5", 5.5")
#              → Android Phone (1080×2340)
#   desktop*.png → Apple macOS (1440×900)
#   logo.svg     → Google Play feature graphic (1024×500, generated)
#
# Outputs are written to screenshots/store/<platform>/<size>/.
#
# Prerequisites: ImageMagick (magick), librsvg (rsvg-convert)
#   brew install imagemagick librsvg
#
# Run from anywhere — the script resolves its own paths.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLUTTER_DIR="$(dirname "$SCRIPT_DIR")"
TV_ROOT="$(dirname "$FLUTTER_DIR")"
SRC_DIR="$FLUTTER_DIR/screenshots/app-screenshots"
OUT_DIR="$FLUTTER_DIR/screenshots/store"
SVG="$TV_ROOT/logo.svg"
APP_BG="#09090b"        # App background (near-black)
GRADIENT_START="#1a1528" # Top-left purple — matches app gradient (go_router_config.dart)
GRADIENT_END="#09090b"   # Bottom-right dark — transition completes at 45% in-app

# ---------------------------------------------------------------------------
# Prerequisites
# ---------------------------------------------------------------------------
for cmd in magick rsvg-convert; do
    command -v "$cmd" &>/dev/null || {
        echo "Error: '$cmd' not found."
        echo "Install with: brew install imagemagick librsvg"
        exit 1
    }
done

[[ -d "$SRC_DIR" ]] || {
    echo "Error: source screenshots not found at $SRC_DIR"
    exit 1
}

[[ -f "$SVG" ]] || {
    echo "Error: logo SVG not found at $SVG"
    exit 1
}

# Render the SVG logo at a given size and add a soft drop shadow.
# Shadow: 55% opacity, 18 px blur sigma, 0 px X / 8 px Y offset.
# Layers are merged on a transparent canvas so the result can be composited
# onto any background without a baked-in fill colour.
logo_with_shadow() {
    local size="$1" dst="$2"
    local raw="$TMP/logo_raw_${size}.png"
    rsvg-convert -w "$size" -h "$size" "$SVG" -o "$raw"
    magick "$raw" \
        \( +clone -background black -shadow "55x18+0+8" \) \
        +swap -background none -layers merge +repage \
        "$dst"
}

# Diagonal gradient background matching the app's _kGradientBg in go_router_config.dart:
#   topLeft=#1a1528 → bottomRight=#09090b
# gradient:vector pins the start/end colours to exact pixel coordinates so
# ImageMagick never extrapolates outside the specified range.
gradient_bg() {
    local dst="$1" w="$2" h="$3"
    magick -size "${w}x${h}" \
        -define "gradient:vector=0,0,$((w-1)),$((h-1))" \
        gradient:"${GRADIENT_START}-${GRADIENT_END}" \
        "$dst"
}

# Scale to fill exact dimensions, then center-crop any overflow.
# This preserves content without letterboxing/pillarboxing.
resize_fill() {
    local src="$1" dst="$2" w="$3" h="$4"
    magick "$src" \
        -resize "${w}x${h}^" \
        -gravity center \
        -extent "${w}x${h}" \
        "$dst"
}

echo "=== Generating store screenshots ==="
echo "  Source : $SRC_DIR"
echo "  Output : $OUT_DIR"

# ---------------------------------------------------------------------------
echo ""
echo "--- Apple tvOS ---"
# tvOS App Store requirements:
#   1920×1080  required (all submissions)
#   3840×2160  optional 4K (recommended for modern Apple TV hardware)
# ---------------------------------------------------------------------------
TVOS_1080="$OUT_DIR/apple/tvos/1920x1080"
TVOS_4K="$OUT_DIR/apple/tvos/3840x2160"
mkdir -p "$TVOS_1080" "$TVOS_4K"

for src in "$SRC_DIR"/tv*.png; do
    name=$(basename "$src")
    echo "  [tvOS 4K   3840×2160]  $name (copy)"
    cp "$src" "$TVOS_4K/$name"
    echo "  [tvOS 1080p 1920×1080] $name"
    magick "$src" -resize "1920x1080" "$TVOS_1080/$name"
done

# ---------------------------------------------------------------------------
echo ""
echo "--- Apple iOS (iPhone) ---"
# App Store Connect requires at least the 6.5" size for modern submissions.
# The 6.7" is required for iPhone 14 Plus / 15 Plus devices.
#
#   6.7"  1290×2796  (iPhone 14 Plus, 15 Plus, 15 Pro Max)
#   6.5"  1242×2688  (iPhone 11 Pro Max, XS Max, 12/13 Pro Max)
#   5.5"  1242×2208  (iPhone 8 Plus — covers legacy device class)
# ---------------------------------------------------------------------------
IOS_67="$OUT_DIR/apple/ios/6.7in-1290x2796"
IOS_65="$OUT_DIR/apple/ios/6.5in-1242x2688"
IOS_55="$OUT_DIR/apple/ios/5.5in-1242x2208"
mkdir -p "$IOS_67" "$IOS_65" "$IOS_55"

for src in "$SRC_DIR"/mobile*.png; do
    name=$(basename "$src")
    # Source (1206×2622) and 6.7"/6.5" targets share nearly identical aspect
    # ratios (~2.17), so cropping is negligible. The 5.5" target is shorter
    # (ratio ~1.78) and requires a more visible crop from the bottom.
    echo "  [iPhone 6.7\"  1290×2796] $name"
    resize_fill "$src" "$IOS_67/$name" 1290 2796
    echo "  [iPhone 6.5\"  1242×2688] $name"
    resize_fill "$src" "$IOS_65/$name" 1242 2688
    echo "  [iPhone 5.5\"  1242×2208] $name"
    resize_fill "$src" "$IOS_55/$name" 1242 2208
done

# ---------------------------------------------------------------------------
echo ""
echo "--- Apple macOS ---"
# Mac App Store screenshot requirements:
#   Minimum: 1280×800
#   Accepted common sizes: 1440×900, 2560×1600, 2880×1800
#
# Source desktop screenshots (1707×1160, ratio ~1.47) are slightly taller
# than the 16:10 store ratio (1.6). A small center crop is applied.
# ---------------------------------------------------------------------------
MACOS_DIR="$OUT_DIR/apple/macos/1440x900"
mkdir -p "$MACOS_DIR"

for src in "$SRC_DIR"/desktop*.png; do
    name=$(basename "$src")
    echo "  [macOS 1440×900] $name"
    resize_fill "$src" "$MACOS_DIR/$name" 1440 900
done

# ---------------------------------------------------------------------------
echo ""
echo "--- Google Play: Android Feature Graphic ---"
# Google Play requires a single 1024×500 feature graphic (mandatory).
# It appears as the hero banner at the top of the store listing.
# Logo at 260 px gives ~120 px breathing room top/bottom (~24% padding).
# ---------------------------------------------------------------------------
FEATURE_DIR="$OUT_DIR/google/android-feature-graphic"
mkdir -p "$FEATURE_DIR"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "  [Android Feature Graphic 1024×500] feature-graphic.png"
logo_with_shadow 260 "$TMP/logo_feature.png"
gradient_bg "$TMP/feature_bg.png" 1024 500
magick "$TMP/feature_bg.png" \
    "$TMP/logo_feature.png" -gravity center -composite \
    "$FEATURE_DIR/feature-graphic.png"

# ---------------------------------------------------------------------------
echo ""
echo "--- Google Play: Android TV Banner ---"
# Displayed on Android TV home screen. PNG or JPEG, 1280×720 (16:9).
# Logo at 300 px gives ~210 px breathing room top/bottom (~29% padding).
# ---------------------------------------------------------------------------
ATV_BANNER_DIR="$OUT_DIR/google/android-tv-banner"
mkdir -p "$ATV_BANNER_DIR"

echo "  [Android TV Banner 1280×720] tv-banner.png"
logo_with_shadow 300 "$TMP/logo_banner.png"
gradient_bg "$TMP/banner_bg.png" 1280 720
magick "$TMP/banner_bg.png" \
    "$TMP/logo_banner.png" -gravity center -composite \
    "$ATV_BANNER_DIR/tv-banner.png"

# ---------------------------------------------------------------------------
echo ""
echo "--- Google Play: Android TV ---"
# Google Play TV screenshot requirements (landscape, exactly 16:9):
#   1920×1080  recommended
#   1280×720   accepted (older/budget devices)
# ---------------------------------------------------------------------------
ATV_1080="$OUT_DIR/google/android-tv/1920x1080"
ATV_720="$OUT_DIR/google/android-tv/1280x720"
mkdir -p "$ATV_1080" "$ATV_720"

for src in "$SRC_DIR"/tv*.png; do
    name=$(basename "$src")
    echo "  [Android TV 1920×1080] $name"
    magick "$src" -resize "1920x1080" "$ATV_1080/$name"
    echo "  [Android TV 1280×720]  $name"
    magick "$src" -resize "1280x720" "$ATV_720/$name"
done

# ---------------------------------------------------------------------------
echo ""
echo "--- Google Play: Android Phone ---"
# Google Play phone screenshot requirements:
#   Any aspect ratio between 16:9 and 9:16; min 320px, max 3840px per side.
#   1080×2340 matches common FHD+ Android devices (19.5:9 ratio).
# ---------------------------------------------------------------------------
ANDROID_DIR="$OUT_DIR/google/android-phone/1080x2340"
mkdir -p "$ANDROID_DIR"

for src in "$SRC_DIR"/mobile*.png; do
    name=$(basename "$src")
    echo "  [Android Phone 1080×2340] $name"
    resize_fill "$src" "$ANDROID_DIR/$name" 1080 2340
done

# ---------------------------------------------------------------------------
echo ""
echo "=== Done ==="
echo ""
echo "Output written to: $OUT_DIR"
echo ""
echo "Store upload checklist:"
echo "  Apple tvOS       → apple/tvos/1920x1080/          (required)"
echo "                     apple/tvos/3840x2160/           (optional 4K)"
echo "  Apple iOS        → apple/ios/6.7in-1290x2796/     (required for iPhone 14+/15+)"
echo "                     apple/ios/6.5in-1242x2688/     (required for older iPhones)"
echo "                     apple/ios/5.5in-1242x2208/     (optional legacy)"
echo "  Apple macOS      → apple/macos/1440x900/"
echo "  Android Feature  → google/android-feature-graphic/feature-graphic.png  (required — 1 image)"
echo "  Android TV Banner→ google/android-tv-banner/tv-banner.png              (required for TV listing)"
echo "  Android TV       → google/android-tv/1920x1080/   (required)"
echo "                     google/android-tv/1280x720/    (optional legacy)"
echo "  Android Phone    → google/android-phone/1080x2340/"

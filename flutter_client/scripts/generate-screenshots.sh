#!/bin/bash
# Screenshot generation for m3u-tv App Store / Google Play submissions
#
# Generates all platform-specific screenshot sizes from source images in
# screenshots/app-screenshots/:
#
#   tv*.png      → Apple tvOS (1920×1080, 3840×2160)
#              → Android TV (1920×1080, 1280×720)
#   mobile*.png  → Apple iPhone (6.9", 6.3", 6.7", 6.5", 5.5")
#              → Android Phone (1080×2340)
#   tablet/*.png  → Apple iPad (12.9", 11")
#                 → Android Tablet (7", 10")
#   desktop*.png → Apple macOS (1440×900)
#
# Store headers and banners (Google feature graphic, Android TV banner, iOS
# product page header, Microsoft art) come from generate-store-assets.sh.
#
# Outputs are written to screenshots/store/<platform>/<size>/.
#
# Prerequisites: ImageMagick (magick)
#   brew install imagemagick
#
# Run from anywhere — the script resolves its own paths.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FLUTTER_DIR="$(dirname "$SCRIPT_DIR")"
SRC_DIR="$FLUTTER_DIR/screenshots/app-screenshots"
OUT_DIR="$FLUTTER_DIR/screenshots/store"

# ---------------------------------------------------------------------------
# Prerequisites
# ---------------------------------------------------------------------------
for cmd in magick; do
    command -v "$cmd" &>/dev/null || {
        echo "Error: '$cmd' not found."
        echo "Install with: brew install imagemagick"
        exit 1
    }
done

[[ -d "$SRC_DIR" ]] || {
    echo "Error: source screenshots not found at $SRC_DIR"
    exit 1
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
# App Store Connect groups iPhone screenshots by display class. Each slot
# only accepts its own exact pixel sizes (portrait or landscape):
#
#   6.9"  1320×2868  (iPhone 16 Pro Max and newer Pro Max)
#   6.3"  1206×2622  (iPhone 16 Pro and newer, 6.1"/6.3" slot - matches source)
#   6.7"  1290×2796  (iPhone 14 Plus, 15 Plus, 15 Pro Max - also accepted in 6.9" slot)
#   6.5"  1242×2688  (iPhone 11 Pro Max, XS Max, 12/13 Pro Max)
#   5.5"  1242×2208  (iPhone 8 Plus — covers legacy device class)
# ---------------------------------------------------------------------------
IOS_69="$OUT_DIR/apple/ios/6.9in-1320x2868"
IOS_63="$OUT_DIR/apple/ios/6.3in-1206x2622"
IOS_67="$OUT_DIR/apple/ios/6.7in-1290x2796"
IOS_65="$OUT_DIR/apple/ios/6.5in-1242x2688"
IOS_55="$OUT_DIR/apple/ios/5.5in-1242x2208"
mkdir -p "$IOS_69" "$IOS_63" "$IOS_67" "$IOS_65" "$IOS_55"

for src in "$SRC_DIR"/mobile*.png; do
    name=$(basename "$src")
    # Source (1206×2622) and 6.7"/6.5" targets share nearly identical aspect
    # ratios (~2.17), so cropping is negligible. The 5.5" target is shorter
    # (ratio ~1.78) and requires a more visible crop from the bottom.
    echo "  [iPhone 6.9\"  1320×2868] $name"
    resize_fill "$src" "$IOS_69/$name" 1320 2868
    echo "  [iPhone 6.3\"  1206×2622] $name"
    resize_fill "$src" "$IOS_63/$name" 1206 2622
    echo "  [iPhone 6.7\"  1290×2796] $name"
    resize_fill "$src" "$IOS_67/$name" 1290 2796
    echo "  [iPhone 6.5\"  1242×2688] $name"
    resize_fill "$src" "$IOS_65/$name" 1242 2688
    echo "  [iPhone 5.5\"  1242×2208] $name"
    resize_fill "$src" "$IOS_55/$name" 1242 2208
done

# ---------------------------------------------------------------------------
echo ""
echo "--- Apple iOS (iPad) ---"
# App Store Connect supports tablet screenshots. These are common portrait
# targets for iPad Pro classes:
#   12.9" 2048×2732
#   11"   1668×2388
# ---------------------------------------------------------------------------
IOS_IPAD_129="$OUT_DIR/apple/ipad/12.9in-2048x2732"
IOS_IPAD_11="$OUT_DIR/apple/ipad/11in-1668x2388"
mkdir -p "$IOS_IPAD_129" "$IOS_IPAD_11"

for src in "$SRC_DIR"/tablet*.png; do
    name=$(basename "$src")
    echo "  [iPad 12.9\"  2048×2732] $name"
    resize_fill "$src" "$IOS_IPAD_129/$name" 2048 2732
    echo "  [iPad 11\"  1668×2388] $name"
    resize_fill "$src" "$IOS_IPAD_11/$name" 1668 2388
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
echo "--- Google Play: Android Tablet ---"
# Google Play supports dedicated tablet screenshots for 7" and 10" classes.
# Using portrait 16:10 targets works well across common Android tablets.
# ---------------------------------------------------------------------------
ANDROID_TAB_7_DIR="$OUT_DIR/google/android-tablet/7in-1200x1920"
ANDROID_TAB_10_DIR="$OUT_DIR/google/android-tablet/10in-1600x2560"
mkdir -p "$ANDROID_TAB_7_DIR" "$ANDROID_TAB_10_DIR"

for src in "$SRC_DIR"/tablet*.png; do
    name=$(basename "$src")
    echo "  [Android Tablet 7\"   1200×1920] $name"
    resize_fill "$src" "$ANDROID_TAB_7_DIR/$name" 1200 1920
    echo "  [Android Tablet 10\"  1600×2560] $name"
    resize_fill "$src" "$ANDROID_TAB_10_DIR/$name" 1600 2560
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
echo "  Apple iOS        → apple/ios/6.9in-1320x2868/     (6.9\" slot)"
echo "                     apple/ios/6.3in-1206x2622/     (6.1\"/6.3\" slot)"
echo "                     apple/ios/6.7in-1290x2796/     (also accepted in 6.9\" slot)"
echo "                     apple/ios/6.5in-1242x2688/     (required for older iPhones)"
echo "                     apple/ios/5.5in-1242x2208/     (optional legacy)"
echo "  Apple macOS      → apple/macos/1440x900/"
echo "  Android TV       → google/android-tv/1920x1080/   (required)"
echo "                     google/android-tv/1280x720/    (optional legacy)"
echo "  Android Phone    → google/android-phone/1080x2340/"
echo ""
echo "Headers/banners (feature graphic, TV banner, iOS header, Microsoft art):"
echo "  scripts/generate-store-assets.sh"

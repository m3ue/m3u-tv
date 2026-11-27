#!/usr/bin/env bash
#
# build-appimage.sh - wrap a bundle from bundle-libs.sh into an AppImage.
#
# Usage: build-appimage.sh <bundle-dir> <output.AppImage> <version>
#
# Downloads checksum-pinned appimagetool and type2 runtime releases (extracted,
# so no FUSE is needed to build). When UPDATE_REPO=<owner>/<repo> is set, the
# image embeds gh-releases-zsync update information for Gear Lever and
# AppImageUpdate and a matching .zsync is written next to it.

set -euo pipefail

if [[ $# -ne 3 ]]; then
    echo "Usage: $0 <bundle-dir> <output.AppImage> <version>" >&2
    exit 2
fi
BUNDLE_DIR="$(realpath "$1")"
OUTPUT="$(realpath -m "$2")"
VERSION="$3"
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
CLIENT_DIR="$(realpath "$SCRIPT_DIR/../..")"

[[ "$(uname -m)" == x86_64 ]] || { echo "Error: only x86_64 AppImages are built" >&2; exit 1; }
[[ -x "$BUNDLE_DIR/m3u-tv.sh" ]] || { echo "Error: run bundle-libs.sh on $BUNDLE_DIR first" >&2; exit 1; }
IMAGEMAGICK="$(command -v magick || command -v convert || true)"
[[ -n "$IMAGEMAGICK" ]] || { echo "Error: ImageMagick is required for the icon" >&2; exit 1; }

APPIMAGETOOL_VERSION=1.9.1
APPIMAGETOOL_SHA256=ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0
RUNTIME_VERSION=20251108
RUNTIME_SHA256=2fca8b443c92510f1483a883f60061ad09b46b978b2631c807cd873a47ec260d

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

curl -fsSL --retry 3 -o "$WORK/appimagetool.AppImage" \
    "https://github.com/AppImage/appimagetool/releases/download/$APPIMAGETOOL_VERSION/appimagetool-x86_64.AppImage"
curl -fsSL --retry 3 -o "$WORK/runtime" \
    "https://github.com/AppImage/type2-runtime/releases/download/$RUNTIME_VERSION/runtime-x86_64"
echo "$APPIMAGETOOL_SHA256  $WORK/appimagetool.AppImage" | sha256sum --check --strict
echo "$RUNTIME_SHA256  $WORK/runtime" | sha256sum --check --strict
chmod +x "$WORK/appimagetool.AppImage"
(cd "$WORK" && ./appimagetool.AppImage --appimage-extract >/dev/null)
APPIMAGETOOL="$WORK/squashfs-root/AppRun"

APPDIR="$WORK/M3U_TV.AppDir"
cp -a "$BUNDLE_DIR" "$APPDIR"
ln -s m3u-tv.sh "$APPDIR/AppRun"
cp "$SCRIPT_DIR/dev.sparkison.tv.desktop" "$APPDIR/"
ICON_DIR="$APPDIR/usr/share/icons/hicolor/256x256/apps"
mkdir -p "$ICON_DIR"
"$IMAGEMAGICK" "$CLIENT_DIR/assets/icons/icon-desktop.png" -resize 256x256 "$ICON_DIR/dev.sparkison.tv.png"
ln -s usr/share/icons/hicolor/256x256/apps/dev.sparkison.tv.png "$APPDIR/dev.sparkison.tv.png"
ln -s dev.sparkison.tv.png "$APPDIR/.DirIcon"

TOOL_ARGS=(--no-appstream --runtime-file "$WORK/runtime")
if [[ -n "${UPDATE_REPO:-}" ]]; then
    [[ "$UPDATE_REPO" =~ ^[^/|]+/[^/|]+$ ]] || { echo "Error: UPDATE_REPO must be <owner>/<repo>" >&2; exit 1; }
    # appimagetool only warns without zsyncmake, which would publish an image
    # whose updates never resolve.
    command -v zsyncmake >/dev/null || { echo "Error: zsyncmake (apt-get install zsync) is required" >&2; exit 1; }
    # Gear Lever finds the newest release's .zsync by this pattern, then
    # downloads the asset with the same name minus .zsync.
    TOOL_ARGS+=(--updateinformation "gh-releases-zsync|${UPDATE_REPO%/*}|${UPDATE_REPO#*/}|latest|m3u-tv-v*-linux-x86_64.AppImage.zsync")
fi

mkdir -p "$(dirname "$OUTPUT")"
rm -f "$OUTPUT" "$OUTPUT.zsync"
# zsyncmake writes into the working directory, which appimagetool changes to
# $OWD; pin both so the .zsync lands next to the image.
(cd "$(dirname "$OUTPUT")" && OWD="$(dirname "$OUTPUT")" ARCH=x86_64 VERSION="$VERSION" \
    "$APPIMAGETOOL" "${TOOL_ARGS[@]}" "$APPDIR" "$OUTPUT")

if [[ -n "${UPDATE_REPO:-}" ]]; then
    [[ -f "$OUTPUT.zsync" ]] || { echo "Error: appimagetool did not write $OUTPUT.zsync" >&2; exit 1; }
    embedded="$(env -u APPIMAGE_EXTRACT_AND_RUN "$OUTPUT" --appimage-updateinformation)"
    [[ "$embedded" == "${TOOL_ARGS[-1]}" ]] || { echo "Error: unexpected update information: $embedded" >&2; exit 1; }
    grep -qx "Filename: $(basename "$OUTPUT")" <(head -c 4096 "$OUTPUT.zsync" | sed -n '1,/^$/p') \
        || { echo "Error: $OUTPUT.zsync does not describe $(basename "$OUTPUT")" >&2; exit 1; }
fi
chmod +x "$OUTPUT"
echo "Created $OUTPUT"

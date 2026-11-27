#!/usr/bin/env bash
#
# build-deb.sh - package a bundle from bundle-libs.sh as a .deb.
#
# Usage: build-deb.sh <bundle-dir> <output.deb> <version>
#
# Installs the bundle to /opt/m3u-tv with /usr/bin/m3u-tv pointing at its
# launcher. Depends is derived from the bundle itself by check-bundle.py, so
# every host library it loads is declared and nothing else is. Must run on a
# Debian-family build host (dpkg-query answers which package owns each file).

set -euo pipefail

if [[ $# -ne 3 ]]; then
    echo "Usage: $0 <bundle-dir> <output.deb> <version>" >&2
    exit 2
fi
BUNDLE_DIR="$(realpath "$1")"
OUTPUT="$(realpath -m "$2")"
VERSION="$3"
SCRIPT_DIR="$(dirname "$(realpath "$0")")"
CLIENT_DIR="$(realpath "$SCRIPT_DIR/../..")"

for tool in dpkg-deb dpkg-query; do
    command -v "$tool" >/dev/null || { echo "Error: $tool is required (Debian/Ubuntu build host)" >&2; exit 1; }
done
IMAGEMAGICK="$(command -v magick || command -v convert || true)"
[[ -n "$IMAGEMAGICK" ]] || { echo "Error: ImageMagick is required for the icons" >&2; exit 1; }

DEPENDS="$(python3 "$SCRIPT_DIR/check-bundle.py" --deb-depends "$BUNDLE_DIR")"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
ROOT="$WORK/root"

mkdir -p "$ROOT/opt" "$ROOT/usr/bin" "$ROOT/usr/share/applications" "$ROOT/usr/share/metainfo" \
    "$ROOT/usr/share/doc/m3u-tv" "$ROOT/DEBIAN"
cp -a "$BUNDLE_DIR" "$ROOT/opt/m3u-tv"
ln -s /opt/m3u-tv/m3u-tv.sh "$ROOT/usr/bin/m3u-tv"
install -m644 "$SCRIPT_DIR/dev.sparkison.tv.desktop" "$ROOT/usr/share/applications/"
install -m644 "$SCRIPT_DIR/dev.sparkison.tv.metainfo.xml" "$ROOT/usr/share/metainfo/"
install -m644 "$CLIENT_DIR/../LICENSE" "$ROOT/usr/share/doc/m3u-tv/copyright"
for size in 16 32 48 64 128 256 512; do
    icon_dir="$ROOT/usr/share/icons/hicolor/${size}x${size}/apps"
    mkdir -p "$icon_dir"
    "$IMAGEMAGICK" "$CLIENT_DIR/assets/icons/icon-desktop.png" -resize "${size}x${size}" \
        "$icon_dir/dev.sparkison.tv.png"
done

INSTALLED_SIZE="$(du -sk --exclude=DEBIAN "$ROOT" | cut -f1)"
cat > "$ROOT/DEBIAN/control" <<EOF
Package: m3u-tv
Version: $VERSION
Architecture: amd64
Maintainer: M3U Editor <noreply@github.com>
Installed-Size: $INSTALLED_SIZE
Depends: $DEPENDS
Section: video
Priority: optional
Homepage: https://github.com/m3ue/m3u-tv
Description: Live TV, movies and series player for M3U Editor
 M3U TV is the player for M3U Editor and Xtream-compatible servers, with a
 full program guide, movies, series and mpv-based playback.
EOF

for hook in postinst postrm; do
    cat > "$ROOT/DEBIAN/$hook" <<'EOF'
#!/bin/sh
set -e
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f -t /usr/share/icons/hicolor || true
fi
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database /usr/share/applications || true
fi
EOF
    chmod 755 "$ROOT/DEBIAN/$hook"
done

mkdir -p "$(dirname "$OUTPUT")"
dpkg-deb --root-owner-group -Zxz --build "$ROOT" "$OUTPUT"
dpkg-deb --info "$OUTPUT" | sed -n '/Depends:/p'
echo "Created $OUTPUT"

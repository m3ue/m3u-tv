#!/usr/bin/env bash
# Package an already-built Flutter Linux x64 bundle. Run on Ubuntu 24.04,
# matching the release build's glibc baseline and libmpv/FFmpeg ABI.
set -euo pipefail

CLIENT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
if [[ $# -ne 2 ]]; then
    echo "Usage: $0 <flutter-bundle-directory> <output.AppImage>" >&2
    exit 2
fi
BUNDLE=$(realpath "$1")
OUTPUT=$(realpath -m "$2")
[[ "$OUTPUT" == *.AppImage ]] || { echo 'Output must end in .AppImage' >&2; exit 2; }
[[ $(uname -m) == x86_64 ]] || { echo 'Only Linux x86_64 is supported' >&2; exit 1; }
for tool in curl sha256sum desktop-file-validate pkg-config glib-compile-schemas python3 dpkg-query readelf convert; do
    command -v "$tool" >/dev/null || { echo "Missing packaging tool: $tool" >&2; exit 1; }
done
for file in m3u_tv lib/libflutter_linux_gtk.so lib/libapp.so lib/libmpv.so.2 \
    data/icudtl.dat data/flutter_assets/version.json; do
    [[ -s "$BUNDLE/$file" ]] || { echo "Missing bundle file: $file" >&2; exit 1; }
done
[[ -d "$BUNDLE/data/flutter_assets" ]]

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
APPDIR="$WORK/M3U_TV.AppDir"
mkdir -p "$APPDIR/usr/bin" "$APPDIR/usr/lib" "$APPDIR/usr/share/glib-2.0/schemas" "$(dirname "$OUTPUT")"
cp -a "$BUNDLE/data" "$APPDIR/usr/bin/data"
cp -a "$BUNDLE/lib/." "$APPDIR/usr/lib/"
# Transitive Android JNI plugins leave this unused library in Linux bundles.
# Linux uses its native plugins and does not start a JVM. Refuse to omit it if
# a future native-assets manifest actually registers it for this platform.
if [[ -f "$APPDIR/usr/lib/libdartjni.so" ]]; then
    [[ -f "$APPDIR/usr/bin/data/flutter_assets/NativeAssetsManifest.json" ]]
    if grep -q 'libdartjni' "$APPDIR/usr/bin/data/flutter_assets/NativeAssetsManifest.json"; then
        echo 'Linux now registers JNI; review its JVM packaging before releasing.' >&2
        exit 1
    fi
    rm "$APPDIR/usr/lib/libdartjni.so"
fi
install -m755 "$BUNDLE/m3u_tv" "$APPDIR/usr/bin/m3u_tv"
# Flutter looks for lib/ and data/ next to the executable.
ln -s ../lib "$APPDIR/usr/bin/lib"
install -m755 "$CLIENT_DIR/linux/appimage/AppRun" "$APPDIR/AppRun"
install -m644 "$CLIENT_DIR/linux/appimage/dev.sparkison.tv.desktop" "$WORK/dev.sparkison.tv.desktop"
# Share the Windows/Linux desktop artwork, preserving its transparent corners.
# linuxdeploy accepts icons up to 512px; the source is generated at 1024px.
convert "$CLIENT_DIR/assets/icons/icon-desktop.png" -resize 512x512 \
    "$WORK/dev.sparkison.tv.png"
desktop-file-validate "$WORK/dev.sparkison.tv.desktop"
# GTK's default theme is built in; its settings schema must match bundled GTK.
[[ -f /usr/share/glib-2.0/schemas/org.gnome.desktop.interface.gschema.xml ]] || {
    echo 'Install gsettings-desktop-schemas before packaging.' >&2
    exit 1
}
cp -a /usr/share/glib-2.0/schemas/. "$APPDIR/usr/share/glib-2.0/schemas/"
glib-compile-schemas "$APPDIR/usr/share/glib-2.0/schemas"

# Use a tagged tool and verify the published asset digest, not a moving
# continuous download. Extract the tool so packaging never requires FUSE.
LINUXDEPLOY_TAG=1-alpha-20251107-1
LINUXDEPLOY_SHA256=c20cd71e3a4e3b80c3483cef793cda3f4e990aca14014d23c544ca3ce1270b4d
curl --fail --location --retry 3 \
    "https://github.com/linuxdeploy/linuxdeploy/releases/download/$LINUXDEPLOY_TAG/linuxdeploy-x86_64.AppImage" \
    -o "$WORK/linuxdeploy.AppImage"
echo "$LINUXDEPLOY_SHA256  $WORK/linuxdeploy.AppImage" | sha256sum --check
chmod +x "$WORK/linuxdeploy.AppImage"
(cd "$WORK" && ./linuxdeploy.AppImage --appimage-extract >/dev/null)
LINUXDEPLOY="$WORK/squashfs-root/AppRun"

# libmpv and Flutter plugins are opened with dlopen: following just the
# executable's DT_NEEDED entries misses their dependencies. Explicitly seed
# every library from the Flutter bundle, including native assets.
LIBRARIES=()
while IFS= read -r -d '' library; do
    LIBRARIES+=(--library "$library")
done < <(find "$APPDIR/usr/lib" -type f -name '*.so*' -print0)
export ARCH=x86_64
export NO_STRIP=1
LD_LIBRARY_PATH="$APPDIR/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" \
"$LINUXDEPLOY" --appdir "$APPDIR" \
    --exclude-library 'libwayland-client.so*' \
    --exclude-library 'libwayland-server.so*' \
    --executable "$APPDIR/usr/bin/m3u_tv" \
    --desktop-file "$WORK/dev.sparkison.tv.desktop" \
    --icon-file "$WORK/dev.sparkison.tv.png" \
    "${LIBRARIES[@]}"

# Ship distro copyright notices for the additional shared libraries. Keep a
# package/version manifest to make the bundled dependency set reviewable.
python3 "$CLIENT_DIR/scripts/appimage-license-notices.py" "$APPDIR" "$CLIENT_DIR/.."

export LDAI_OUTPUT="$OUTPUT"
export LDAI_NO_APPSTREAM=1
# Gear Lever/AppImageUpdate discover stable x86_64 releases in the upstream
# repository from this standard metadata. appimagetool also emits the .zsync
# companion, which must be published alongside the exact AppImage it describes.
export LDAI_UPDATE_INFORMATION='gh-releases-zsync|m3ue|m3u-tv|latest|m3u-tv-v*-linux-x86_64.AppImage.zsync'
LDAI_VERSION=$(python3 -c 'import json, sys; print(json.load(open(sys.argv[1]))["version"])' \
    "$BUNDLE/data/flutter_assets/version.json")
export LDAI_VERSION
(
    # zsyncmake writes to the current directory, even for an absolute image
    # path. Keep the companion next to the image for local builds and CI.
    cd "$(dirname "$OUTPUT")"
    APPIMAGE_EXTRACT_AND_RUN=1 "$LINUXDEPLOY" --appdir "$APPDIR" \
        --exclude-library 'libwayland-client.so*' \
        --exclude-library 'libwayland-server.so*' \
        --output appimage
)
chmod +x "$OUTPUT"
python3 "$CLIENT_DIR/scripts/verify-linux-appimage.py" "$OUTPUT"
(
    cd "$(dirname "$OUTPUT")"
    for asset in "$(basename "$OUTPUT")" "$(basename "$OUTPUT").zsync"; do
        sha256sum "$asset" > "$asset.sha256"
    done
)
echo "Created $OUTPUT"

#!/usr/bin/env bash
#
# build-linux-release.sh - build every Linux release package from one bundle.
#
# Usage: linux/packaging/build-linux-release.sh [options]
#   --output DIR       where packages go (default: build/linux-release)
#   --formats LIST     comma list of zip,appimage,deb,flatpak (default: all)
#   --version V        package version (default: pubspec.yaml, without +build)
#   --skip-build       reuse the existing release bundle instead of rebuilding
#
# Run from anywhere on an Ubuntu 24.04 x86_64 host with the packages listed in
# flutter_client/README.md. CI and the release workflow call this same script.
# Set UPDATE_REPO=<owner>/<repo> to embed AppImage update information.

set -euo pipefail

if [[ "$(uname -s)" != Linux || "$(uname -m)" != x86_64 ]]; then
    echo "Error: Linux packages are built on Linux x86_64 (Ubuntu 24.04); this is $(uname -s) $(uname -m)" >&2
    exit 1
fi

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
CLIENT_DIR="$(realpath "$SCRIPT_DIR/../..")"
cd "$CLIENT_DIR"

OUT_DIR="build/linux-release"
FORMATS="zip,appimage,deb,flatpak"
VERSION=""
SKIP_BUILD=false
while (($#)); do
    case "$1" in
        --output) OUT_DIR="$2"; shift 2 ;;
        --formats) FORMATS="$2"; shift 2 ;;
        --version) VERSION="$2"; shift 2 ;;
        --skip-build) SKIP_BUILD=true; shift ;;
        *) echo "Unknown option: $1" >&2; exit 2 ;;
    esac
done
[[ -n "$VERSION" ]] || VERSION="$(sed -n 's/^version: *\([^+ ]*\).*/\1/p' pubspec.yaml)"
[[ -n "$VERSION" ]] || { echo "Error: could not read the version from pubspec.yaml" >&2; exit 1; }
mkdir -p "$OUT_DIR"
OUT_DIR="$(realpath "$OUT_DIR")"

wants() { [[ ",$FORMATS," == *",$1,"* ]]; }

# Check every tool up front so a missing package fails here, not after the
# Flutter build. The apt packages are listed in flutter_client/README.md.
REQUIRED_TOOLS=(python3 zstd tar ldd readelf strip pkg-config glib-compile-schemas sha256sum cmp)
$SKIP_BUILD || REQUIRED_TOOLS+=(flutter)
if wants appimage; then
    REQUIRED_TOOLS+=(curl)
    if [[ -n "${UPDATE_REPO:-}" ]]; then
        REQUIRED_TOOLS+=(zsyncmake)
    fi
fi
wants deb && REQUIRED_TOOLS+=(dpkg-deb dpkg-query)
wants flatpak && REQUIRED_TOOLS+=(flatpak flatpak-builder)
MISSING=()
for tool in "${REQUIRED_TOOLS[@]}"; do
    command -v "$tool" >/dev/null || MISSING+=("$tool")
done
if wants appimage || wants deb || wants flatpak; then
    command -v magick >/dev/null || command -v convert >/dev/null || MISSING+=("imagemagick")
fi
if ((${#MISSING[@]})); then
    echo "Error: missing build tools: ${MISSING[*]} (see the Linux section of flutter_client/README.md)" >&2
    exit 1
fi

PREFIX="$CLIENT_DIR/build/libmpv-prefix"
BUNDLE="$CLIENT_DIR/build/linux/x64/release/bundle"

echo "==> Fetching pinned libmpv"
python3 "$SCRIPT_DIR/fetch-libmpv.py" --dest "$PREFIX"

if ! $SKIP_BUILD; then
    echo "==> Building the Flutter Linux release"
    M3U_TV_LIBMPV_PREFIX="$PREFIX" flutter build linux --release
fi

# A host libmpv in the bundle would package fine and then behave differently
# on every distro, so refuse anything but the pinned build.
PINNED="$(find "$PREFIX" -name 'libmpv.so.2' | head -1)"
cmp -s "$(realpath "$PINNED")" "$BUNDLE/lib/libmpv.so.2" || {
    echo "Error: $BUNDLE/lib/libmpv.so.2 is not the pinned libmpv; rebuild without --skip-build" >&2
    exit 1
}

echo "==> Bundling shared libraries"
bash "$SCRIPT_DIR/bundle-libs.sh" "$BUNDLE"
echo "==> Verifying the bundle"
python3 "$SCRIPT_DIR/check-bundle.py" --probe-mpv "$BUNDLE"

ARTIFACTS=()
if wants zip; then
    ZIP="$OUT_DIR/m3u-tv-v$VERSION-linux.zip"
    rm -f "$ZIP"
    (cd "$BUNDLE" && python3 -m zipfile -c "$ZIP" .)
    python3 -m zipfile -t "$ZIP" >/dev/null
    ARTIFACTS+=("$ZIP")
fi
if wants appimage; then
    IMAGE="$OUT_DIR/m3u-tv-v$VERSION-linux-x86_64.AppImage"
    bash "$SCRIPT_DIR/build-appimage.sh" "$BUNDLE" "$IMAGE" "$VERSION"
    ARTIFACTS+=("$IMAGE")
    if [[ -f "$IMAGE.zsync" ]]; then
        ARTIFACTS+=("$IMAGE.zsync")
    fi
fi
if wants deb; then
    DEB="$OUT_DIR/m3u-tv-v$VERSION-linux-amd64.deb"
    bash "$SCRIPT_DIR/build-deb.sh" "$BUNDLE" "$DEB" "$VERSION"
    ARTIFACTS+=("$DEB")
fi
if wants flatpak; then
    FLATPAK="$OUT_DIR/m3u-tv-v$VERSION-linux-x86_64.flatpak"
    python3 "$SCRIPT_DIR/build-flatpak.py" build "$BUNDLE" "$FLATPAK" "$VERSION"
    ARTIFACTS+=("$FLATPAK")
fi

for artifact in "${ARTIFACTS[@]}"; do
    (cd "$(dirname "$artifact")" && sha256sum "$(basename "$artifact")" > "$(basename "$artifact").sha256")
done
echo "==> Linux packages in $OUT_DIR:"
ls -lh "${ARTIFACTS[@]}"

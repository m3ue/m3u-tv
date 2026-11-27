#!/usr/bin/env bash
#
# bundle-libs.sh - make a Flutter Linux release bundle portable across distros.
#
# Usage: bundle-libs.sh <bundle-dir>
#
# Copies every shared library the bundle needs into <bundle>/lib, except the
# ones that must come from the running system (HOST_LIBRARY_PATTERN below),
# plus the GTK/GIO modules those libraries dlopen and the GSettings schemas GTK
# reads. Run it on the build host (Ubuntu 24.04) after `flutter build linux`
# with the pinned libmpv already in <bundle>/lib. The m3u-tv.sh launcher sets
# the search paths that make these copies take effect at runtime.

set -euo pipefail

BUNDLE_DIR="$(realpath "$1")"
LIB_DIR="$BUNDLE_DIR/lib"
BINARY="$BUNDLE_DIR/m3u_tv"
SCRIPT_DIR="$(dirname "$(realpath "$0")")"

[[ -x "$BINARY" ]] || { echo "Error: $BINARY not found" >&2; exit 1; }
[[ -f "$LIB_DIR/libmpv.so.2" ]] || { echo "Error: $LIB_DIR/libmpv.so.2 missing; build with M3U_TV_LIBMPV_PREFIX set" >&2; exit 1; }

# Libraries that must come from the host. The C runtime and loader; the GPU,
# VA-API/VDPAU, Vulkan, Wayland/X11 and ALSA stacks, which are coupled to the
# running driver, compositor and kernel; the C++ runtime, because host Mesa
# drivers are loaded into this process and need the host's (newer) libstdc++;
# and fontconfig/freetype, which must match the host's font configuration.
# check-bundle.py reads this same pattern, so keep the two in step.
HOST_LIBRARY_PATTERN="$(grep -vE '^[[:space:]]*(#|$)' "$SCRIPT_DIR/host-libraries.txt" | paste -sd'|' -)"

COPIED=()

collect_deps() {
    LD_LIBRARY_PATH="$LIB_DIR" ldd "$@" 2>/dev/null \
        | grep -oP '(?<==> )/\S+' \
        | sort -u \
        | grep -vE "/($HOST_LIBRARY_PATTERN)[^/]*$" \
        || true
}

copy_lib() {
    local source="$1" dest_dir="$2"
    local base
    base="$(basename "$source")"
    if [[ ! -e "$dest_dir/$base" ]]; then
        cp -L "$source" "$dest_dir/$base"
        COPIED+=("$dest_dir/$base")
        return 0
    fi
    return 1
}

resolve_closure() {
    local -a seeds=("$@")
    while ((${#seeds[@]})); do
        local -a fresh=()
        while IFS= read -r dep; do
            [[ -z "$dep" || "$dep" == "$LIB_DIR/"* ]] && continue
            if copy_lib "$dep" "$LIB_DIR"; then
                fresh+=("$LIB_DIR/$(basename "$dep")")
            fi
        done < <(collect_deps "${seeds[@]}")
        if ((${#fresh[@]})); then
            echo "    bundled ${#fresh[@]} libraries"
        fi
        seeds=("${fresh[@]}")
    done
}

find_tool() {
    local name="$1"
    if command -v "$name" 2>/dev/null; then
        return
    fi
    find /usr/lib /usr/libexec -name "$name" -type f -perm -u+x 2>/dev/null | head -1
}

echo "==> Resolving shared library dependencies"
mapfile -t seeds < <(find "$LIB_DIR" -maxdepth 1 -name '*.so*' -type f; echo "$BINARY")
resolve_closure "${seeds[@]}"

# Returns 1 when the build host has no such module directory.
bundle_modules() {
    local source_dir="$1" dest_dir="$2"
    if [[ -z "$source_dir" || ! -d "$source_dir" ]] || ! compgen -G "$source_dir/*.so" >/dev/null; then
        echo "WARNING: no modules in ${source_dir:-(unknown)}, skipping" >&2
        return 1
    fi
    mkdir -p "$dest_dir"
    local -a modules=()
    while IFS= read -r -d '' module; do
        copy_lib "$module" "$dest_dir" || true
        modules+=("$dest_dir/$(basename "$module")")
    done < <(find "$source_dir" -maxdepth 1 -name '*.so' -print0)
    resolve_closure "${modules[@]}"
    echo "==> Bundled ${#modules[@]} modules from $source_dir"
}

# Module caches are written with a placeholder for the bundle's lib directory.
# The launcher substitutes the real install path, so the same tree works from
# a ZIP, an AppImage mount, /opt or /app.
write_cache_template() {
    local tool="$1" module_dir="$2" template="$3"
    [[ -n "$tool" ]] || { echo "Error: no cache tool for $module_dir" >&2; exit 1; }
    "$tool" "$module_dir"/*.so | sed "s|$LIB_DIR|@M3U_TV_LIB@|g" > "$template"
    grep -q '@M3U_TV_LIB@' "$template" || { echo "Error: $template lists no bundled modules" >&2; exit 1; }
}

PIXBUF_SOURCE="$(pkg-config --variable=gdk_pixbuf_moduledir gdk-pixbuf-2.0)"
PIXBUF_DEST="$LIB_DIR/gdk-pixbuf-2.0/2.10.0/loaders"
if bundle_modules "$PIXBUF_SOURCE" "$PIXBUF_DEST"; then
    write_cache_template "$(find_tool gdk-pixbuf-query-loaders)" "$PIXBUF_DEST" \
        "$LIB_DIR/gdk-pixbuf-2.0/2.10.0/loaders.cache.in"
fi

bundle_modules "$(pkg-config --variable=giomoduledir gio-2.0)" "$LIB_DIR/gio/modules" || true

GTK_LIBDIR="$(pkg-config --variable=libdir gtk+-3.0)"
IM_DEST="$LIB_DIR/gtk-3.0/3.0.0/immodules"
if bundle_modules "$GTK_LIBDIR/gtk-3.0/3.0.0/immodules" "$IM_DEST"; then
    write_cache_template "$(find_tool gtk-query-immodules-3.0)" "$IM_DEST" \
        "$LIB_DIR/gtk-3.0/3.0.0/immodules.cache.in"
fi

echo "==> Bundling GSettings schemas"
SCHEMAS_DEST="$BUNDLE_DIR/share/glib-2.0/schemas"
mkdir -p "$SCHEMAS_DEST"
cp /usr/share/glib-2.0/schemas/*.xml "$SCHEMAS_DEST/"
cp /usr/share/glib-2.0/schemas/*.override "$SCHEMAS_DEST/" 2>/dev/null || true
glib-compile-schemas "$SCHEMAS_DEST"

install -m755 "$SCRIPT_DIR/m3u-tv.sh" "$BUNDLE_DIR/m3u-tv.sh"
install -m755 "$SCRIPT_DIR/host-launch.sh" "$LIB_DIR/host-launch.sh"

# Strip only what this script copied. The Flutter engine, libapp.so and the
# pinned libmpv are left exactly as built.
echo "==> Stripping ${#COPIED[@]} bundled libraries"
if ((${#COPIED[@]})); then
    strip --strip-unneeded "${COPIED[@]}"
fi

echo "==> Done"
du -sh "$LIB_DIR"

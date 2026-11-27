#!/usr/bin/env bash
# Launcher for the portable Linux bundle. Used as-is by the ZIP, as AppRun in
# the AppImage, as /usr/bin/m3u-tv (a symlink into /opt/m3u-tv) in the .deb,
# and by the Flatpak's /app/bin/m3u-tv.

set -euo pipefail

INSTALL_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
LIB_DIR="$INSTALL_DIR/lib"

# Everything below changes for this process only. Programs it launches (the
# browser for sign-in links, trailers) get the user's own values back through
# host-launch.sh, so they never load this bundle's libraries.
HOST_VARIABLES=(LD_LIBRARY_PATH GDK_PIXBUF_MODULE_FILE GIO_MODULE_DIR GTK_IM_MODULE_FILE
    GSETTINGS_SCHEMA_DIR GIO_LAUNCH_DESKTOP)
for name in "${HOST_VARIABLES[@]}"; do
    if [[ -n "${!name+set}" ]]; then
        export "M3U_TV_HOST_$name=${!name}"
    else
        export "M3U_TV_HOST_$name=@unset@"
    fi
done

# The GTK module caches carry absolute paths, so they are written per launch
# for wherever this bundle lives (ZIP, AppImage mount, /opt, /app).
RUNTIME_ROOT="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}"
for stale in "$RUNTIME_ROOT"/m3u-tv-gtk-*; do
    [[ -d "$stale" ]] || continue
    pid="${stale##*-}"
    if [[ "$pid" =~ ^[0-9]+$ ]] && ! kill -0 "$pid" 2>/dev/null; then
        rm -rf "$stale"
    fi
done
CACHE_DIR="$RUNTIME_ROOT/m3u-tv-gtk-$$"

write_cache() {
    local template="$1" output="$2"
    [[ -f "$template" ]] || return 1
    mkdir -p "$CACHE_DIR" 2>/dev/null || return 1
    local content
    content="$(<"$template")"
    printf '%s\n' "${content//@M3U_TV_LIB@/$LIB_DIR}" > "$output" 2>/dev/null
}

if write_cache "$LIB_DIR/gdk-pixbuf-2.0/2.10.0/loaders.cache.in" "$CACHE_DIR/loaders.cache"; then
    export GDK_PIXBUF_MODULE_FILE="$CACHE_DIR/loaders.cache"
fi
if write_cache "$LIB_DIR/gtk-3.0/3.0.0/immodules.cache.in" "$CACHE_DIR/immodules.cache"; then
    export GTK_IM_MODULE_FILE="$CACHE_DIR/immodules.cache"
fi
if [[ -d "$LIB_DIR/gio/modules" ]]; then
    export GIO_MODULE_DIR="$LIB_DIR/gio/modules"
fi
if [[ -d "$INSTALL_DIR/share/glib-2.0/schemas" ]]; then
    export GSETTINGS_SCHEMA_DIR="$INSTALL_DIR/share/glib-2.0/schemas"
fi

# The bundled libgio launches URL handlers through this helper; the one its
# build host compiled in does not exist on most other distros.
export GIO_LAUNCH_DESKTOP="$LIB_DIR/host-launch.sh"

# Bundled libraries carry no RUNPATH, and libmpv is dlopen'd, so the loader
# needs this for their dependencies to resolve inside the bundle.
export LD_LIBRARY_PATH="$LIB_DIR${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"

exec "$INSTALL_DIR/m3u_tv" "$@"

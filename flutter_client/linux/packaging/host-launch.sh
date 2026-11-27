#!/usr/bin/env bash
# GIO_LAUNCH_DESKTOP helper set by m3u-tv.sh. libgio runs every launched
# desktop application (the default browser, for example) as
# `host-launch.sh <program> <args...>`. Restore the environment the user
# started M3U TV with so the program loads the host's libraries, not the
# bundle's, then do what glib's own gio-launch-desktop does.

for name in LD_LIBRARY_PATH GDK_PIXBUF_MODULE_FILE GIO_MODULE_DIR GTK_IM_MODULE_FILE \
    GSETTINGS_SCHEMA_DIR GIO_LAUNCH_DESKTOP; do
    saved="M3U_TV_HOST_$name"
    [[ -n "${!saved+set}" ]] || continue
    if [[ "${!saved}" == "@unset@" ]]; then
        unset "$name"
    else
        export "$name=${!saved}"
    fi
    unset "$saved"
done

export GIO_LAUNCHED_DESKTOP_FILE_PID=$$
exec "$@"

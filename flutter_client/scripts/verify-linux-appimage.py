#!/usr/bin/env python3
"""Extract an AppImage, check every ELF dependency and exercise bundled libmpv.

The libmpv probe runs in a fresh process with the same library search path as
AppRun. It plays a generated PCM sample with null outputs: no network, display,
audio device or existing application settings are used.
"""
import ctypes
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import time
import wave

UPDATE_INFORMATION = (
    "gh-releases-zsync|m3ue|m3u-tv|latest|"
    "m3u-tv-v*-linux-x86_64.AppImage.zsync"
)

# Deliberate host dependencies: glibc and the desktop/driver libraries excluded
# by linuxdeploy. Codec, GTK and plugin dependencies must be inside the image,
# even on a build host where apt would otherwise hide a packaging omission.
SYSTEM_LIBRARIES = set("""
ld-linux-x86-64.so.2 libc.so.6 libm.so.6 libmvec.so.1 libdl.so.2
libpthread.so.0 libresolv.so.2 librt.so.1 libutil.so.1
libstdc++.so.6 libgcc_s.so.1 libGL.so.1 libEGL.so.1 libOpenGL.so.0
libGLX.so.0 libGLdispatch.so.0 libdrm.so.2 libglapi.so.0 libgbm.so.1
libX11.so.6 libX11-xcb.so.1 libxcb.so.1 libxcb-dri2.so.0 libxcb-dri3.so.0
libwayland-client.so.0 libwayland-server.so.0 libasound.so.2
libjack.so.0 libpipewire-0.3.so.0 libfontconfig.so.1 libfreetype.so.6
libharfbuzz.so.0 libfribidi.so.0 libcom_err.so.2 libexpat.so.1
libgpg-error.so.0 libICE.so.6 libSM.so.6 libusb-1.0.so.0 libuuid.so.1
libz.so.1 libgmp.so.10
""".split())


def probe(library, sample):
    mpv = ctypes.CDLL(str(library))
    mpv.mpv_create.restype = ctypes.c_void_p
    mpv.mpv_set_option_string.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_char_p]
    mpv.mpv_initialize.argtypes = [ctypes.c_void_p]
    mpv.mpv_command.argtypes = [ctypes.c_void_p, ctypes.POINTER(ctypes.c_char_p)]
    mpv.mpv_terminate_destroy.argtypes = [ctypes.c_void_p]

    class Event(ctypes.Structure):
        _fields_ = [("event_id", ctypes.c_int), ("error", ctypes.c_int),
                    ("reply_userdata", ctypes.c_uint64), ("data", ctypes.c_void_p)]

    class EndFile(ctypes.Structure):
        _fields_ = [("reason", ctypes.c_int), ("error", ctypes.c_int)]

    mpv.mpv_wait_event.argtypes = [ctypes.c_void_p, ctypes.c_double]
    mpv.mpv_wait_event.restype = ctypes.POINTER(Event)
    handle = mpv.mpv_create()
    if not handle:
        raise RuntimeError("mpv_create failed")
    try:
        for key, value in [(b"config", b"no"), (b"vo", b"null"), (b"ao", b"null"),
                           (b"input-default-bindings", b"no")]:
            if mpv.mpv_set_option_string(handle, key, value) < 0:
                raise RuntimeError(f"mpv option failed: {key!r}")
        if mpv.mpv_initialize(handle) < 0:
            raise RuntimeError("mpv_initialize failed")
        args = (ctypes.c_char_p * 3)(b"loadfile", os.fsencode(sample), None)
        if mpv.mpv_command(handle, args) < 0:
            raise RuntimeError("mpv loadfile failed")
        loaded = False
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            event = mpv.mpv_wait_event(handle, 0.5).contents
            if event.event_id == 8:  # MPV_EVENT_FILE_LOADED
                loaded = True
            if event.event_id == 7:  # MPV_EVENT_END_FILE
                end = ctypes.cast(event.data, ctypes.POINTER(EndFile)).contents
                if not loaded or end.reason != 0 or end.error < 0:
                    raise RuntimeError(f"Playback failed: reason={end.reason}, error={end.error}")
                print("Bundled libmpv loaded, initialized and decoded the playback sample")
                return
        raise RuntimeError("Timed out waiting for libmpv playback")
    finally:
        mpv.mpv_terminate_destroy(handle)


def verify_updates(image):
    # This runtime option otherwise launches the app instead of returning its
    # update information, which must also work on a headless release runner.
    env = os.environ.copy()
    env.pop("APPIMAGE_EXTRACT_AND_RUN", None)
    embedded = subprocess.check_output(
        [str(image), "--appimage-updateinformation"], text=True, env=env
    ).strip()
    if embedded != UPDATE_INFORMATION:
        raise RuntimeError(f"Unexpected AppImage update source: {embedded!r}")

    # Gear Lever compares this hash with the installed AppImage. A stale
    # companion would repeatedly offer the wrong update even if the app runs.
    with Path(f"{image}.zsync").open("rb") as stream:
        header, separator, _ = stream.read(65536).partition(b"\n\n")
    if not separator:
        raise RuntimeError("Missing zsync header terminator")
    fields = dict(line.split(": ", 1) for line in header.decode("utf-8").splitlines())
    if fields.get("Filename") != image.name or fields.get("URL") != image.name:
        raise RuntimeError("zsync filename/URL must refer to the adjacent AppImage")
    if fields.get("Length") != str(image.stat().st_size):
        raise RuntimeError("zsync length does not match the AppImage")
    with image.open("rb") as stream:
        digest = hashlib.file_digest(stream, "sha1").hexdigest()
    if fields.get("SHA-1") != digest:
        raise RuntimeError("zsync SHA-1 does not match the AppImage")
    print("Verified upstream update source and matching zsync metadata")


def verify(image):
    image = Path(image).resolve()
    verify_updates(image)
    with tempfile.TemporaryDirectory(prefix="m3u-appimage-verify-") as temp:
        root = Path(temp)
        subprocess.run([str(image), "--appimage-extract"], cwd=root,
                       stdout=subprocess.DEVNULL, check=True)
        appdir = root / "squashfs-root"
        libdir = appdir / "usr/lib"
        for name in ["AppRun", "usr/bin/m3u_tv", "usr/bin/data/icudtl.dat",
                     "usr/lib/libflutter_linux_gtk.so", "usr/lib/libapp.so",
                     "usr/lib/libmpv.so.2", "dev.sparkison.tv.desktop"]:
            if not (appdir / name).is_file():
                raise RuntimeError(f"Missing AppImage file: {name}")
        version = json.loads((appdir / "usr/bin/data/flutter_assets/version.json").read_text())["version"]
        desktop = (appdir / "dev.sparkison.tv.desktop").read_text()
        if f"X-AppImage-Version={version}" not in desktop.splitlines():
            raise RuntimeError("AppImage desktop version does not match the Flutter build")
        # Requiring codec libraries inside the image prevents a false pass on
        # the build host, where apt has already installed all of libmpv's deps.
        for name in ["libavcodec.so.*", "libavformat.so.*", "libavutil.so.*",
                     "libswresample.so.*", "libswscale.so.*", "libplacebo.so.*"]:
            if not list(libdir.glob(name)):
                raise RuntimeError(f"Unbundled playback dependency: {name}")
        env = os.environ | {"LD_LIBRARY_PATH": str(libdir)}
        binaries = [appdir / "usr/bin/m3u_tv"] + sorted(libdir.rglob("*.so*"))
        for binary in binaries:
            if binary.is_symlink() or not binary.is_file():
                continue
            with binary.open("rb") as stream:
                if stream.read(4) != b"\x7fELF":
                    continue
            result = subprocess.run(["ldd", str(binary)], env=env,
                                    capture_output=True, text=True, check=True)
            if "not found" in result.stdout + result.stderr:
                raise RuntimeError(f"Unresolved dependencies for {binary}:\n{result.stdout}{result.stderr}")
            dynamic = subprocess.check_output(["readelf", "-d", str(binary)], text=True)
            for dependency in re.findall(r"\(NEEDED\).*\[([^]]+)\]", dynamic):
                if dependency not in SYSTEM_LIBRARIES and not (libdir / dependency).is_file():
                    raise RuntimeError(f"Unbundled dependency of {binary.name}: {dependency}")
        sample = root / "sample.wav"
        with wave.open(str(sample), "wb") as output:
            output.setparams((1, 2, 8000, 0, "NONE", "not compressed"))
            output.writeframes(b"\0\0" * 2000)
        subprocess.run([sys.executable, str(Path(__file__).resolve()), "--probe",
                        str(libdir / "libmpv.so.2"), str(sample)],
                       env=env, check=True, timeout=30)
        print(f"Verified {image.name}: ELF dependencies and playback")


if __name__ == "__main__":
    if len(sys.argv) == 4 and sys.argv[1] == "--probe":
        probe(Path(sys.argv[2]), Path(sys.argv[3]))
    elif len(sys.argv) == 3 and sys.argv[1] == "--updates-only":
        verify_updates(Path(sys.argv[2]).resolve())
    elif len(sys.argv) == 2:
        verify(sys.argv[1])
    else:
        raise SystemExit(f"Usage: {sys.argv[0]} [--updates-only] <image.AppImage>")

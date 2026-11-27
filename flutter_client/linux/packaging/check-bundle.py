#!/usr/bin/env python3
"""Verify a portable Linux bundle produced by bundle-libs.sh.

Every ELF object in the bundle is resolved with the same library path the
launcher uses. The check fails when a dependency resolves nowhere, or when it
resolves from the host without matching host-libraries.txt: that library
should have been bundled, and a user without it would fail to start.

--probe-mpv also loads the bundled libmpv in a child process and plays a
generated audio sample with null outputs, proving its own dependencies load.

--deb-depends prints the Debian packages that own the host libraries (plus the
glibc floor), for build-deb.sh.
"""

import argparse
import ctypes
import os
import re
import subprocess
import sys
import tempfile
import time
import wave
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
REQUIRED = [
    "m3u_tv", "m3u-tv.sh", "lib/host-launch.sh", "lib/libflutter_linux_gtk.so", "lib/libapp.so",
    "lib/libmpv.so.2", "lib/libshaderc_shared.so.1", "data/icudtl.dat",
    "data/flutter_assets/version.json",
]
# The jni FFI plugin ships its bridge in every Linux build, but it is only
# loaded on Android, where a JVM exists.
UNLOADED_ON_LINUX = {"libdartjni.so"}


def host_pattern() -> re.Pattern:
    lines = (SCRIPT_DIR / "host-libraries.txt").read_text().splitlines()
    entries = [line.strip() for line in lines if line.strip() and not line.strip().startswith("#")]
    return re.compile("^(" + "|".join(entries) + ")")


def elf_objects(bundle: Path) -> list[Path]:
    objects = []
    for path in [bundle / "m3u_tv", *sorted(bundle.rglob("*.so*"))]:
        if path.is_symlink() or not path.is_file():
            continue
        with path.open("rb") as stream:
            if stream.read(4) == b"\x7fELF":
                objects.append(path)
    return objects


def resolve(bundle: Path) -> tuple[dict[str, str], list[str], str]:
    pattern = host_pattern()
    lib_dir = str(bundle / "lib")
    env = dict(os.environ, LD_LIBRARY_PATH=lib_dir)
    host: dict[str, str] = {}
    errors: list[str] = []
    glibc = (0, 0)
    for obj in elf_objects(bundle):
        result = subprocess.run(["ldd", str(obj)], env=env, capture_output=True, text=True)
        if result.returncode != 0:
            errors.append(f"ldd could not read {obj}: {result.stderr.strip()}")
            continue
        for line in result.stdout.splitlines():
            name, arrow, target = (part.strip() for part in line.partition("=>"))
            if not arrow:
                continue
            if target.startswith("not found"):
                if obj.name not in UNLOADED_ON_LINUX:
                    errors.append(f"{obj.relative_to(bundle)} needs {name}, which resolves nowhere "
                                  "(install it on the build host so bundle-libs.sh can copy it)")
                continue
            path = target.split(" (")[0]
            if not path.startswith("/") or path.startswith(lib_dir + "/"):
                continue
            if not pattern.match(name):
                errors.append(f"{obj.relative_to(bundle)} loads {name} from the host ({path}); "
                              "bundle it or add it to host-libraries.txt")
                continue
            host[name] = path
        versions = subprocess.run(["readelf", "--version-info", "--wide", str(obj)],
                                  capture_output=True, text=True).stdout
        for major, minor in re.findall(r"Name: GLIBC_(\d+)\.(\d+)", versions):
            glibc = max(glibc, (int(major), int(minor)))
    if not host:
        errors.append("no host libraries resolved at all; ldd produced nothing usable")
    return host, errors, f"{glibc[0]}.{glibc[1]}"


def deb_owner(path: str) -> str:
    for candidate in (path, os.path.realpath(path)):
        output = subprocess.run(["dpkg-query", "-S", candidate], capture_output=True, text=True).stdout
        for line in output.splitlines():
            if line.startswith("diversion "):
                continue
            packages, _, _ = line.partition(": ")
            if packages:
                return packages.split(",")[0].strip().split(":")[0]
    raise SystemExit(f"{path} is not owned by any Debian package")


def probe(library: str, sample: str) -> None:
    # The pinned libmpv leaves its C++ runtime symbols to the process that
    # loads it rather than declaring libstdc++ as NEEDED. m3u_tv is a C++
    # executable, so it always has the host libstdc++ loaded globally before
    # it dlopens libmpv; load it the same way here.
    ctypes.CDLL("libstdc++.so.6", mode=ctypes.RTLD_GLOBAL)
    mpv = ctypes.CDLL(library)
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
        raise SystemExit("mpv_create failed")
    try:
        for key, value in ((b"config", b"no"), (b"vo", b"null"), (b"ao", b"null"), (b"terminal", b"no")):
            if mpv.mpv_set_option_string(handle, key, value) < 0:
                raise SystemExit(f"mpv rejected option {key.decode()}")
        if mpv.mpv_initialize(handle) < 0:
            raise SystemExit("mpv_initialize failed")
        command = (ctypes.c_char_p * 3)(b"loadfile", os.fsencode(sample), None)
        if mpv.mpv_command(handle, command) < 0:
            raise SystemExit("mpv loadfile failed")
        loaded = False
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            event = mpv.mpv_wait_event(handle, 0.5).contents
            if event.event_id == 8:  # MPV_EVENT_FILE_LOADED
                loaded = True
            elif event.event_id == 7:  # MPV_EVENT_END_FILE
                end = ctypes.cast(event.data, ctypes.POINTER(EndFile)).contents
                if not loaded or end.reason != 0:
                    raise SystemExit(f"mpv playback failed (reason {end.reason}, error {end.error})")
                return
        raise SystemExit("timed out waiting for mpv playback")
    finally:
        mpv.mpv_terminate_destroy(handle)


def probe_mpv(bundle: Path) -> None:
    with tempfile.TemporaryDirectory(prefix="m3u-tv-mpv-probe-") as temp:
        sample = Path(temp) / "sample.wav"
        with wave.open(str(sample), "wb") as output:
            output.setnchannels(1)
            output.setsampwidth(2)
            output.setframerate(8000)
            output.writeframes(b"\0\0" * 4000)
        env = dict(os.environ, LD_LIBRARY_PATH=str(bundle / "lib"))
        subprocess.run([sys.executable, __file__, "--probe-child", str(bundle / "lib/libmpv.so.2"), str(sample)],
                       env=env, check=True, timeout=60)
    print("Bundled libmpv loaded, initialized and played the sample")


def main() -> int:
    if len(sys.argv) == 4 and sys.argv[1] == "--probe-child":
        probe(sys.argv[2], sys.argv[3])
        return 0

    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("bundle", type=Path)
    parser.add_argument("--probe-mpv", action="store_true")
    parser.add_argument("--deb-depends", action="store_true")
    args = parser.parse_args()
    bundle = args.bundle.resolve()

    missing = [name for name in REQUIRED if not (bundle / name).is_file()]
    if missing:
        print(f"Error: bundle is missing {', '.join(missing)}", file=sys.stderr)
        return 1

    host, errors, glibc = resolve(bundle)
    # The Wayland GPU video plane is optional at configure time, so a build host
    # missing its headers would quietly ship the software-only path.
    dynamic = subprocess.run(["readelf", "-d", str(bundle / "m3u_tv")], capture_output=True, text=True).stdout
    if "[libwayland-egl.so.1]" not in dynamic:
        errors.append("m3u_tv was built without the Wayland video plane (install libwayland-dev and libegl-dev)")
    if "[libstdc++.so.6]" not in dynamic:
        errors.append("m3u_tv no longer links libstdc++, which the pinned libmpv relies on being loaded")
    for error in errors:
        print(f"::error::{error}", file=sys.stderr)
    if errors:
        return 1

    if args.deb_depends:
        packages = sorted({deb_owner(path) for path in host.values()} - {"libc6"})
        print(", ".join([f"libc6 (>= {glibc})", *packages]))
        return 0

    print(f"All dependencies resolve; {len(host)} come from the host, glibc >= {glibc}:")
    for name, path in sorted(host.items()):
        print(f"  {name:<28} {path}")
    if args.probe_mpv:
        probe_mpv(bundle)
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Download the pinned Linux libmpv prefix named by mpv-build.lock.json.

The prefix is a self-contained libmpv (FFmpeg, libplacebo, dav1d and libass
compiled in) plus libshaderc_shared. Its SHA-256 is checked against the lock
before anything is extracted. Used by CI, the release workflow and local
builds, so every Linux package is cut from the same libmpv.
"""

import argparse
import hashlib
import json
import platform
import shutil
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path

CLIENT_DIR = Path(__file__).resolve().parents[2]
DEFAULT_LOCK = CLIENT_DIR / "mpv-build.lock.json"
CHUNK_SIZE = 1024 * 1024
MARKER = ".m3u-tv-libmpv-asset"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lock", type=Path, default=DEFAULT_LOCK)
    parser.add_argument("--dest", type=Path, required=True)
    args = parser.parse_args()

    if shutil.which("zstd") is None:
        print("Error: zstd is required to extract the libmpv archive (apt-get install zstd)", file=sys.stderr)
        return 1

    group = json.loads(args.lock.read_text(encoding="utf-8"))["artifacts"]["linux"]
    machine = platform.machine()
    entry = group["assets"].get(machine)
    if entry is None:
        print(f"Error: no Linux libmpv pinned for {machine!r} (locked: {', '.join(sorted(group['assets']))})",
              file=sys.stderr)
        return 1

    marker = args.dest / MARKER
    if marker.is_file() and marker.read_text().strip() == entry["checksum"]:
        print(f"libmpv prefix already at {args.dest} ({entry['asset']})")
        return 0

    url = f"{group['assetBase']}/{entry['asset']}"
    print(f"Fetching {url}", flush=True)
    digest = hashlib.sha256()
    with tempfile.NamedTemporaryFile(suffix=".tar.zst") as archive:
        with urllib.request.urlopen(url) as response:
            while chunk := response.read(CHUNK_SIZE):
                digest.update(chunk)
                archive.write(chunk)
        archive.flush()
        if digest.hexdigest() != entry["checksum"]:
            print(f"Error: {entry['asset']} SHA-256 {digest.hexdigest()} does not match the lock "
                  f"({entry['checksum']})", file=sys.stderr)
            return 1
        if args.dest.exists():
            shutil.rmtree(args.dest)
        args.dest.mkdir(parents=True)
        subprocess.run(["tar", "--zstd", "-xf", archive.name, "-C", str(args.dest)], check=True)
    marker.write_text(entry["checksum"] + "\n")
    print(f"Extracted {entry['asset']} to {args.dest}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Package a bundle from bundle-libs.sh as a single-file Flatpak, or verify one.

  build-flatpak.py build <bundle-dir> <output.flatpak> <version>
  build-flatpak.py verify

`build` needs flatpak, flatpak-builder, ImageMagick and the
org.freedesktop.Platform/Sdk runtime from the manifest installed for the user.
It uses no network. `verify` runs against the user-installed app and resolves
every ELF dependency inside the sandbox, against the runtime instead of the
build host.
"""

import json
import shutil
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET
from datetime import datetime, timezone
from pathlib import Path

SCRIPT_DIR = Path(__file__).resolve().parent
CLIENT_DIR = SCRIPT_DIR.parents[1]
APP_ID = "dev.sparkison.tv"

VERIFY = r'''
set -euo pipefail
export LD_LIBRARY_PATH=/app/m3u-tv/lib
for executable in /app/bin/m3u-tv /app/m3u-tv/m3u_tv /app/m3u-tv/m3u-tv.sh; do
    test -x "$executable" || { echo "Not executable: $executable" >&2; exit 1; }
done
count=0
while IFS= read -r -d '' object; do
    case "$(basename "$object")" in libdartjni.so) continue ;; esac
    magic=$(od -An -tx1 -N4 "$object")
    [[ "$magic" == *"7f 45 4c 46"* ]] || continue
    dependencies=$(ldd "$object" 2>&1) || { echo "$dependencies" >&2; exit 1; }
    if [[ "$dependencies" == *"not found"* ]]; then
        printf 'Unresolved dependency in %s:\n%s\n' "$object" "$dependencies" >&2
        exit 1
    fi
    count=$((count + 1))
done < <(find /app/m3u-tv -type f -print0)
test "$count" -gt 0
printf 'Resolved every dependency of %s ELF objects against the Flatpak runtime.\n' "$count"
'''


def build(bundle: Path, output: Path, version: str) -> None:
    for required in ("m3u_tv", "m3u-tv.sh", "lib/libmpv.so.2", "lib/libflutter_linux_gtk.so"):
        if not (bundle / required).is_file():
            raise SystemExit(f"Incomplete bundle, missing {bundle / required}; run bundle-libs.sh first")
    image_tool = shutil.which("magick") or shutil.which("convert")
    if image_tool is None:
        raise SystemExit("ImageMagick is required for the 512px icon")

    template = SCRIPT_DIR / "flatpak"
    manifest = json.loads((template / f"{APP_ID}.json").read_text())
    with tempfile.TemporaryDirectory(prefix="m3u-tv-flatpak-") as temporary:
        stage = Path(temporary)
        shutil.copy2(template / "m3u-tv", stage / "m3u-tv")
        shutil.copy2(SCRIPT_DIR / f"{APP_ID}.desktop", stage / f"{APP_ID}.desktop")
        metadata = ET.parse(SCRIPT_DIR / f"{APP_ID}.metainfo.xml")
        releases = ET.SubElement(metadata.getroot(), "releases")
        ET.SubElement(releases, "release", version=version,
                      date=datetime.now(timezone.utc).date().isoformat())
        metadata.write(stage / f"{APP_ID}.metainfo.xml", encoding="utf-8", xml_declaration=True)
        subprocess.run([image_tool, str(CLIENT_DIR / "assets/icons/icon-desktop.png"), "-resize", "512x512",
                        str(stage / f"{APP_ID}.png")], check=True)
        manifest["modules"][0]["sources"][0]["path"] = str(bundle)
        manifest_path = stage / f"{APP_ID}.json"
        manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")
        subprocess.run([
            "flatpak-builder", "--user", "--disable-rofiles-fuse", "--force-clean", "--arch=x86_64",
            f"--state-dir={stage / 'state'}", f"--repo={stage / 'repo'}",
            str(stage / "build"), str(manifest_path),
        ], check=True, cwd=stage)
        artifact = stage / output.name
        subprocess.run([
            "flatpak", "build-bundle", "--arch=x86_64",
            "--runtime-repo=https://flathub.org/repo/flathub.flatpakrepo",
            str(stage / "repo"), str(artifact), APP_ID, "master",
        ], check=True)
        output.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(artifact, output)
    print(f"Created {output}")


def main() -> None:
    if len(sys.argv) == 5 and sys.argv[1] == "build":
        build(Path(sys.argv[2]).resolve(), Path(sys.argv[3]).resolve(), sys.argv[4])
    elif len(sys.argv) == 2 and sys.argv[1] == "verify":
        subprocess.run(["flatpak", "run", "--user", "--command=bash", APP_ID, "-c", VERIFY], check=True)
    else:
        raise SystemExit(__doc__)


if __name__ == "__main__":
    main()

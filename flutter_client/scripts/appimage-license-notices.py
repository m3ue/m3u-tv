#!/usr/bin/env python3
"""Collect Ubuntu notices for libraries added to the Flutter AppImage."""
import pathlib
import shutil
import subprocess
import sys

appdir, repo = map(pathlib.Path, sys.argv[1:])
destination = appdir / "usr/share/doc/m3u-tv"
destination.mkdir(parents=True, exist_ok=True)
shutil.copy2(repo / "LICENSE", destination / "LICENSE")
packages = set()
for library in sorted((appdir / "usr/lib").rglob("*.so*")):
    # Original Flutter/native-asset binaries aren't Ubuntu packages.
    result = subprocess.run(
        ["dpkg-query", "-S", f"*/{library.name}"], capture_output=True, text=True
    )
    for line in result.stdout.splitlines():
        package, _, _ = line.partition(": ")
        packages.add(package)

manifest = []
for package in sorted(packages):
    version = subprocess.check_output(
        ["dpkg-query", "-W", "-f=${Version}", package], text=True
    )
    name = package.split(":")[0]
    copyright_file = pathlib.Path("/usr/share/doc") / name / "copyright"
    if not copyright_file.is_file():
        raise SystemExit(f"Missing copyright notice for {package}")
    package_dir = destination / "dependencies" / name
    package_dir.mkdir(parents=True, exist_ok=True)
    shutil.copy2(copyright_file, package_dir / "copyright")
    manifest.append(f"{package}\t{version}\n")
(destination / "packages.tsv").write_text("".join(manifest))
shutil.copytree("/usr/share/common-licenses", destination / "common-licenses")

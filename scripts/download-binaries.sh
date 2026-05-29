#!/usr/bin/env bash
# download-binaries.sh
#
# Produces a self-contained mpv bundle in binaries/mac/{arch}/ by:
#   1. Installing mpv via Homebrew (if not already installed)
#   2. Recursively collecting every non-system dylib mpv depends on
#   3. Rewriting all load paths to @executable_path/ (relative)
#   4. Re-applying an adhoc codesign (install_name_tool invalidates sigs)
#
# This is the same strategy jellyfin-desktop uses in their xtask/install.rs.
#
# Usage (run from the m3u-tv/ directory):
#   ./scripts/download-binaries.sh          # current host arch
#   ./scripts/download-binaries.sh --all    # arm64 + x64
#
# Output:
#   binaries/mac/arm64/  mpv + libmpv.2.dylib + all transitive dylibs
#   binaries/mac/x64/    same for Intel
#   binaries/win/x64/    mpv.exe  (Windows; run from Git Bash / Linux CI)

set -euo pipefail
cd "$(dirname "$0")/.."

log() { printf "  [download-binaries] %s\n" "$*"; }
die() { printf "\nERROR: %s\n" "$*" >&2; exit 1; }

# ─── macOS ───────────────────────────────────────────────────────────────────

bundle_mac() {
  local arch="$1"   # arm64 | x64
  local dest="binaries/mac/$arch"

  # Skip if already bundled and the binary works
  if [[ -f "$dest/mpv" ]] && "$dest/mpv" --version &>/dev/null 2>&1; then
    log "mac/$arch: already bundled and working, skipping."
    return
  fi

  command -v brew &>/dev/null || die "Homebrew is required. See https://brew.sh"
  command -v install_name_tool &>/dev/null || die "install_name_tool not found (Xcode CLT required)."

  # 1. Ensure mpv is installed
  if ! brew list mpv &>/dev/null; then
    log "mac/$arch: installing mpv via Homebrew…"
    brew install mpv
  fi

  local mpv_bin libmpv
  mpv_bin="$(brew --prefix mpv)/bin/mpv"
  libmpv="$(brew --prefix mpv)/lib/libmpv.2.dylib"
  [[ -f "$mpv_bin" ]] || die "mpv binary not found at $mpv_bin"
  [[ -f "$libmpv"  ]] || die "libmpv not found at $libmpv"

  rm -rf "$dest"
  mkdir -p "$dest"

  log "mac/$arch: copying mpv and collecting dependencies…"
  cp "$mpv_bin" "$dest/mpv"
  chmod 755 "$dest/mpv"

  # 2. Recursively collect every non-system dylib
  #    (system = /usr/lib/*, /System/*)
  _collect() {
    local file="$1"
    local deps
    deps=$(otool -L "$file" 2>/dev/null | awk 'NR>1{print $1}')
    while IFS= read -r dep; do
      [[ -z "$dep" ]] && continue
      case "$dep" in /usr/lib/*|/System/*|@*) continue ;; esac
      local base; base="$(basename "$dep")"
      [[ -f "$dest/$base" ]] && continue          # already copied
      [[ -f "$dep" ]] || continue                 # skip if missing
      log "  + $base"
      cp "$dep" "$dest/$base"
      chmod 755 "$dest/$base"
      _collect "$dest/$base"                      # recurse
    done <<< "$deps"
  }
  _collect "$dest/mpv"

  # 3. Rewrite all load paths in every file in the bundle
  #    @executable_path/<lib>  works because Electron spawns mpv with
  #    the binary's directory as cwd, and mpv resolves @executable_path
  #    relative to itself (not the Electron exe).
  log "mac/$arch: rewriting load paths…"
  for f in "$dest"/*; do
    [[ -f "$f" ]] || continue
    # Fix the install name of dylibs
    if [[ "$f" == *.dylib ]]; then
      local cur_id; cur_id="$(otool -D "$f" 2>/dev/null | tail -1)"
      local new_id="@executable_path/$(basename "$f")"
      if [[ "$cur_id" != "$new_id" ]]; then
        install_name_tool -id "$new_id" "$f" 2>/dev/null || true
      fi
    fi
    # Rewrite all non-system deps to @executable_path/
    while IFS= read -r dep; do
      [[ -z "$dep" ]] && continue
      case "$dep" in /usr/lib/*|/System/*|@*) continue ;; esac
      install_name_tool -change "$dep" \
        "@executable_path/$(basename "$dep")" "$f" 2>/dev/null || true
    done < <(otool -L "$f" 2>/dev/null | awk 'NR>1{print $1}')
    # Add @executable_path as an rpath (for @rpath/... references in mpv)
    install_name_tool -add_rpath "@executable_path" "$f" 2>/dev/null || true
  done

  # 4. Re-sign everything (install_name_tool invalidates existing signatures)
  log "mac/$arch: re-signing with adhoc signature…"
  for f in "$dest"/*; do
    [[ -f "$f" ]] || continue
    codesign --force --sign - "$f" 2>/dev/null || true
  done

  # 5. Sanity check
  if "$dest/mpv" --version &>/dev/null 2>&1; then
    log "mac/$arch: ✓ mpv runs ($(ls "$dest"/*.dylib 2>/dev/null | wc -l | tr -d ' ') dylibs bundled)"
  else
    log "mac/$arch: ⚠ binary test failed — may still work when launched by Electron"
  fi
}

# ─── Windows ─────────────────────────────────────────────────────────────────

bundle_win_x64() {
  local dest="binaries/win/x64"
  [[ -f "$dest/mpv.exe" ]] && { log "win/x64: already present, skipping."; return; }
  mkdir -p "$dest"

  command -v curl &>/dev/null || die "curl is required"

  log "win/x64: fetching latest shinchiro release…"
  local url
  url="$(curl -sL https://api.github.com/repos/shinchiro/mpv-winbuild-cmake/releases/latest \
    | grep browser_download_url \
    | grep 'mpv-x86_64-[0-9].*\.7z"' \
    | head -1 \
    | sed 's/.*"\(https[^"]*\)".*/\1/')"
  [[ -n "$url" ]] || die "Could not find Windows mpv release URL"

  local tmp; tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  curl -L --progress-bar "$url" -o "$tmp/mpv.7z"
  local z; z="$(command -v 7z 2>/dev/null || command -v 7za 2>/dev/null)"
  [[ -n "$z" ]] || die "p7zip required: brew install p7zip"
  "$z" e "$tmp/mpv.7z" -o"$tmp/out" mpv.exe -r -y &>/dev/null
  cp "$tmp/out/mpv.exe" "$dest/mpv.exe"
  log "win/x64: done."
}

# ─── Main ─────────────────────────────────────────────────────────────────────

ALL=false; [[ "${1:-}" == "--all" ]] && ALL=true

case "$(uname -s)" in
  Darwin)
    # sysctl is reliable even under Rosetta (uname -m returns x86_64 in Rosetta shells)
    if [[ "$(sysctl -n hw.optional.arm64 2>/dev/null)" == "1" ]]; then
      HOST="arm64"
    else
      HOST="x64"
    fi

    if $ALL; then
      bundle_mac "arm64"
      bundle_mac "x64"
    else
      bundle_mac "$HOST"
    fi
    ;;
  Linux)
    $ALL && bundle_win_x64 || true
    printf "\nLinux: install mpv from your package manager (apt/dnf/pacman).\n\n"
    ;;
  MINGW*|MSYS*|CYGWIN*)
    bundle_win_x64
    ;;
  *)
    die "Unsupported OS: $(uname -s)"
    ;;
esac

printf "\nDone. Run 'corepack yarn electron:build' to package.\n"

#!/usr/bin/env bash
# Build store/release artifacts for one or more platforms, following the
# "Release builds" section of flutter_client/README.md.
#
# Usage (from flutter_client/):
#   ./scripts/build-release.sh                    # pick platforms from a menu
#   ./scripts/build-release.sh tvos macos         # build the named platforms
#   ./scripts/build-release.sh all --upload       # every platform this host can build
#
# Platforms (each needs its own host OS):
#   android   App Bundle + APK, release-signed       (any host)
#   ios       App Store .ipa                         (macOS)
#   tvos      App Store .ipa via flutter-tvos        (macOS)
#   macos     Mac App Store .pkg                     (macOS; the DMG is built by CI)
#   linux     Portable .zip of the release bundle    (Linux)
#   windows   Portable .zip + Microsoft Store .msix  (Windows, Git Bash)
#
# Options:
#   --upload       Upload Apple builds to App Store Connect with altool. Needs
#                  ASC_API_KEY_ID and ASC_API_ISSUER_ID set, and the key file
#                  AuthKey_<id>.p8 in ~/.appstoreconnect/private_keys/.
#                  Without them, the build is offered to Transporter instead.
#                  Apple builds that aren't uploaded are offered to Transporter
#                  in one prompt after every platform has finished, so a
#                  multi-platform run doesn't stop between builds.
#   --xcode        Apple builds: stop after archiving and open the archive in
#                  Xcode's Organizer (Distribute App) instead of exporting.
#   --clean        Run `flutter clean` before building.
#   -y, --yes      Skip the confirmation prompt.
#   --dart-define=KEY=VALUE   Passed through to every Flutter build.
#   -h, --help     Show this help.
#
# Artifacts are copied to build/release/v<version>/ with the same names the
# GitHub Release uses (m3u-tv-v<version>-<platform>.<ext>). The version and
# build number come from pubspec.yaml; bump them there first.

set -euo pipefail

FLUTTER_CLIENT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$FLUTTER_CLIENT"

APPLE_TEAM_ID="5AMT94T836"
ALL_PLATFORMS="android ios tvos macos linux windows"

UPLOAD=false
OPEN_XCODE=false
CLEAN=false
ASSUME_YES=false
PLATFORMS=()
DART_DEFINES=()

usage() {
    sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
}

# ---------------------------------------------------------------------------
# Output helpers
# ---------------------------------------------------------------------------

if [[ -t 1 ]]; then
    BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RESET=$'\033[0m'
else
    BOLD=""; DIM=""; RED=""; GREEN=""; YELLOW=""; RESET=""
fi

step() { echo; echo "${BOLD}==> $*${RESET}"; }
info() { echo "    $*"; }
warn() { echo "${YELLOW}    Warning: $*${RESET}" >&2; }
fail() { echo "${RED}    Error: $*${RESET}" >&2; exit 1; }

run() {
    echo "${DIM}    \$ $*${RESET}"
    "$@"
}

confirm() {
    local prompt="$1" reply
    if $ASSUME_YES || [[ ! -t 0 ]]; then return 0; fi
    read -r -p "$prompt [Y/n] " reply
    [[ -z "$reply" || "$reply" =~ ^[Yy] ]]
}

require() {
    command -v "$1" >/dev/null 2>&1 || fail "$1 not found. $2"
}

# ---------------------------------------------------------------------------
# Arguments
# ---------------------------------------------------------------------------

while [[ $# -gt 0 ]]; do
    case "$1" in
        --upload) UPLOAD=true ;;
        --xcode) OPEN_XCODE=true ;;
        --clean) CLEAN=true ;;
        -y|--yes) ASSUME_YES=true ;;
        --dart-define=*) DART_DEFINES+=("$1") ;;
        -h|--help) usage; exit 0 ;;
        all) for p in $ALL_PLATFORMS; do PLATFORMS+=("$p"); done ;;
        android|ios|tvos|macos|linux|windows) PLATFORMS+=("$1") ;;
        *) echo "Unknown argument: $1" >&2; echo >&2; usage >&2; exit 2 ;;
    esac
    shift
done

if $UPLOAD && $OPEN_XCODE; then
    fail "--upload and --xcode can't be combined: --xcode stops before exporting anything to upload."
fi

# ---------------------------------------------------------------------------
# Host and version
# ---------------------------------------------------------------------------

case "$(uname -s)" in
    Darwin) HOST="macos" ;;
    Linux) HOST="linux" ;;
    MINGW*|MSYS*|CYGWIN*) HOST="windows" ;;
    *) HOST="unknown" ;;
esac

can_build_on_host() {
    case "$1" in
        android) return 0 ;;
        ios|tvos|macos) [[ "$HOST" == "macos" ]] ;;
        linux) [[ "$HOST" == "linux" ]] ;;
        windows) [[ "$HOST" == "windows" ]] ;;
        *) return 1 ;;
    esac
}

PUBSPEC_VERSION="$(sed -n 's/^version: *//p' pubspec.yaml | tr -d '[:space:]')"
[[ "$PUBSPEC_VERSION" == *+* ]] || fail "pubspec.yaml version '$PUBSPEC_VERSION' has no +build number."
VERSION="${PUBSPEC_VERSION%%+*}"
BUILD_NUMBER="${PUBSPEC_VERSION#*+}"
OUT_DIR="$FLUTTER_CLIENT/build/release/v$VERSION"

# ---------------------------------------------------------------------------
# Platform selection
# ---------------------------------------------------------------------------

AVAILABLE=()
for p in $ALL_PLATFORMS; do
    if can_build_on_host "$p"; then AVAILABLE+=("$p"); fi
done

if [[ ${#PLATFORMS[@]} -eq 0 ]]; then
    [[ -t 0 ]] || fail "No platform given. Pass one or more of: $ALL_PLATFORMS"
    echo "Which platforms? (this $HOST host can build: ${AVAILABLE[*]})"
    i=1
    for p in "${AVAILABLE[@]}"; do
        echo "  $i) $p"
        i=$((i + 1))
    done
    echo "  a) all of the above"
    read -r -p "Enter numbers separated by spaces: " choice
    for c in $choice; do
        if [[ "$c" == "a" ]]; then
            PLATFORMS=("${AVAILABLE[@]}")
            break
        elif [[ "$c" =~ ^[0-9]+$ ]] && ((c >= 1 && c <= ${#AVAILABLE[@]})); then
            PLATFORMS+=("${AVAILABLE[$((c - 1))]}")
        else
            fail "Not a menu option: $c"
        fi
    done
    [[ ${#PLATFORMS[@]} -gt 0 ]] || fail "Nothing selected."
else
    # `all` from the command line means "all this host can build".
    SELECTED=()
    for p in "${PLATFORMS[@]}"; do
        if can_build_on_host "$p"; then
            SELECTED+=("$p")
        else
            warn "Skipping $p: it can't be built on a $HOST host."
        fi
    done
    [[ ${#SELECTED[@]} -gt 0 ]] || fail "None of the requested platforms can be built on this $HOST host."
    PLATFORMS=("${SELECTED[@]}")
fi

# ---------------------------------------------------------------------------
# Shared steps
# ---------------------------------------------------------------------------

flutter_build() {
    run flutter build "$@" ${DART_DEFINES[@]+"${DART_DEFINES[@]}"}
}

collect() {
    local source="$1" name="$2"
    [[ -e "$source" ]] || fail "Expected build output not found: $source"
    mkdir -p "$OUT_DIR"
    rm -rf "${OUT_DIR:?}/$name"
    cp -R "$source" "$OUT_DIR/$name"
    info "${GREEN}-> build/release/v$VERSION/$name${RESET}"
}

zip_dir() {
    local dir="$1" zip_path="$2"
    rm -f "$zip_path"
    mkdir -p "$(dirname "$zip_path")"
    if [[ "$HOST" == "windows" ]]; then
        local win_dir win_zip
        win_dir="$(cygpath -w "$dir")"
        win_zip="$(cygpath -w "$zip_path")"
        run powershell.exe -NoProfile -Command \
            "Compress-Archive -Path '$win_dir\\*' -DestinationPath '$win_zip'"
    else
        (cd "$dir" && run python3 -m zipfile -c "$zip_path" .)
    fi
    info "${GREEN}-> build/release/v$VERSION/$(basename "$zip_path")${RESET}"
}

# Apple packages waiting for Transporter. Each platform builds in its own
# subshell, so they're queued in a file rather than an array.
TRANSPORTER_QUEUE="$(mktemp)"
trap 'rm -f "$TRANSPORTER_QUEUE"' EXIT

# Uploads an exported Apple package, or queues it for Transporter.
deliver_apple() {
    local package="$1" platform="$2"
    if $UPLOAD; then
        if [[ -n "${ASC_API_KEY_ID:-}" && -n "${ASC_API_ISSUER_ID:-}" ]]; then
            step "Uploading $platform build to App Store Connect"
            run xcrun altool --upload-package "$package" \
                --api-key "$ASC_API_KEY_ID" --api-issuer "$ASC_API_ISSUER_ID"
            return
        fi
        warn "ASC_API_KEY_ID / ASC_API_ISSUER_ID not set; opening Transporter instead."
    fi
    if [[ -d "/Applications/Transporter.app" ]]; then
        echo "$package" >>"$TRANSPORTER_QUEUE"
        info "Will offer $(basename "$package") to Transporter once all builds finish."
    fi
}

offer_transporter() {
    local packages=()
    while IFS= read -r package; do
        [[ -n "$package" ]] && packages+=("$package")
    done <"$TRANSPORTER_QUEUE"
    [[ ${#packages[@]} -gt 0 ]] || return 0
    step "Transporter"
    for package in "${packages[@]}"; do info "$(basename "$package")"; done
    if confirm "    Open ${#packages[@]} build(s) in Transporter?"; then
        run open -a Transporter "${packages[@]}"
    fi
}

open_archive_in_xcode() {
    local archive="$1"
    info "Opening $archive in Xcode. Use Distribute App > App Store Connect."
    run open "$archive"
}

# ---------------------------------------------------------------------------
# Platforms
# ---------------------------------------------------------------------------

build_android() {
    # Fail instead of falling back to a debug-signed release build. Keys come
    # from env vars or android/signing.properties (see build.gradle.kts).
    export ANDROID_REQUIRE_RELEASE_SIGNING=true
    # The Play bundle never gets the in-app updater (Play forbids
    # self-updating); the sideload APK does.
    flutter_build appbundle --release
    flutter_build apk --release --dart-define=M3UTV_SIDELOAD_UPDATER=true
    collect build/app/outputs/bundle/release/app-release.aab "m3u-tv-v$VERSION-android.aab"
    collect build/app/outputs/flutter-apk/app-release.apk "m3u-tv-v$VERSION-android.apk"
}

build_ios() {
    flutter_build ipa --release --export-options-plist=ios/ExportOptions.plist
    if $OPEN_XCODE; then
        open_archive_in_xcode build/ios/archive/Runner.xcarchive
        return
    fi
    local ipa
    ipa="$(find build/ios/ipa -maxdepth 1 -name '*.ipa' | head -n 1)"
    [[ -n "$ipa" ]] || fail "flutter build ipa produced no .ipa (check ios/ExportOptions.plist and signing)."
    collect "$ipa" "m3u-tv-v$VERSION-ios.ipa"
    deliver_apple "$OUT_DIR/m3u-tv-v$VERSION-ios.ipa" ios
}

build_tvos() {
    require flutter-tvos "Install it per the tvOS section of the root README."
    # Not under build/tvos: flutter-tvos uses that folder as its asset output
    # and copies all of it (bar Xcode's *-appletvos dirs) into
    # tvos/Flutter/flutter_assets, so an archive left there ships inside the
    # next build's app. Clear what older runs of this script left behind.
    local archive=build/tvos-release/Runner.xcarchive export_dir=build/tvos-release/export
    rm -rf build/tvos/Runner.xcarchive build/tvos/export \
        tvos/Flutter/flutter_assets/Runner.xcarchive tvos/Flutter/flutter_assets/export

    # flutter-tvos always forces Automatic signing on its internal xcodebuild
    # call, which fails against this project's Manual signing. The Dart AOT
    # compile and asset staging finish before that call, so its failure is
    # expected; the staged output is verified below, same as CI's tvos-build.
    step "Staging tvOS Flutter artifacts (a signing failure at the end is expected)"
    run flutter-tvos build tvos --release ${DART_DEFINES[@]+"${DART_DEFINES[@]}"} ||
        info "flutter-tvos exited non-zero, as expected. Verifying the staged output."
    [[ -s tvos/Flutter/flutter_assets/AssetManifest.bin ]] ||
        fail "tvos/Flutter/flutter_assets/AssetManifest.bin missing: flutter-tvos didn't stage the assets."
    [[ -d tvos/Flutter/App.framework ]] ||
        fail "tvos/Flutter/App.framework missing: the Dart AOT compile didn't complete."

    step "Archiving tvOS"
    rm -rf "$archive"
    run xcodebuild archive \
        -workspace tvos/Runner.xcworkspace -scheme Runner \
        -sdk appletvos -configuration Release \
        -destination 'generic/platform=tvOS' \
        -archivePath "$archive" \
        -allowProvisioningUpdates \
        DEVELOPMENT_TEAM="$APPLE_TEAM_ID"
    [[ -s "$archive/Products/Applications/Runner.app/flutter_assets/AssetManifest.bin" ]] ||
        fail "The archived Runner.app has no flutter_assets (see issue #186)."

    if $OPEN_XCODE; then
        open_archive_in_xcode "$archive"
    else
        step "Exporting tvOS .ipa"
        rm -rf "$export_dir"
        run xcodebuild -exportArchive \
            -archivePath "$archive" \
            -exportOptionsPlist tvos/ExportOptions.plist \
            -exportPath "$export_dir" \
            -allowProvisioningUpdates
        local ipa
        ipa="$(find "$export_dir" -maxdepth 1 -name '*.ipa' | head -n 1)"
        [[ -n "$ipa" ]] || fail "Export produced no .ipa. Retry with --xcode to distribute from the Organizer."
        collect "$ipa" "m3u-tv-v$VERSION-tvos.ipa"
        deliver_apple "$OUT_DIR/m3u-tv-v$VERSION-tvos.ipa" tvos
    fi
    info "To debug in the tvOS simulator again, run \`flutter-tvos run -d <simulator-id>\` first (README)."
}

build_macos() {
    local archive=build/macos/Runner.xcarchive export_dir=build/macos/export
    # Compiling through flutter writes the --dart-define values that the
    # Xcode archive then picks up.
    flutter_build macos --release

    step "Archiving macOS"
    rm -rf "$archive"
    run xcodebuild archive \
        -workspace macos/Runner.xcworkspace -scheme Runner \
        -configuration Release \
        -archivePath "$archive" \
        -allowProvisioningUpdates

    if $OPEN_XCODE; then
        open_archive_in_xcode "$archive"
        return
    fi
    step "Exporting Mac App Store .pkg"
    rm -rf "$export_dir"
    run xcodebuild -exportArchive \
        -archivePath "$archive" \
        -exportOptionsPlist macos/ExportOptions.plist \
        -exportPath "$export_dir" \
        -allowProvisioningUpdates
    local pkg
    pkg="$(find "$export_dir" -maxdepth 1 -name '*.pkg' | head -n 1)"
    [[ -n "$pkg" ]] || fail "Export produced no .pkg. Retry with --xcode to distribute from the Organizer."
    collect "$pkg" "m3u-tv-v$VERSION-macos-appstore.pkg"
    info "This is the App Store build only. The notarized DMG comes from CI on tag push."
    deliver_apple "$OUT_DIR/m3u-tv-v$VERSION-macos-appstore.pkg" macos
}

build_linux() {
    require python3 "It's used by the Linux packaging scripts, same as CI."
    local prefix="$FLUTTER_CLIENT/build/libmpv-prefix"
    local formats="zip,appimage,deb"
    command -v flatpak-builder >/dev/null && formats="$formats,flatpak"
    run python3 linux/packaging/fetch-libmpv.py --dest "$prefix"
    M3U_TV_LIBMPV_PREFIX="$prefix" flutter_build linux --release
    run linux/packaging/build-linux-release.sh --skip-build --version "$VERSION" \
        --output "$OUT_DIR" --formats "${M3U_TV_LINUX_FORMATS:-$formats}"
}

build_windows() {
    local bundle=build/windows/x64/runner/Release
    flutter_build windows --release
    for file in m3u_tv.exe flutter_windows.dll libmpv-gpu-2.dll data/flutter_assets/AssetManifest.bin; do
        [[ -s "$bundle/$file" ]] || fail "Windows bundle is missing $file."
    done
    zip_dir "$bundle" "$OUT_DIR/m3u-tv-v$VERSION-windows.zip"

    # msix:create rebuilds Windows by default; reuse the build above. The
    # Store requires the fourth version part to be 0, and this keeps the
    # MSIX version in step with pubspec instead of msix_config's copy.
    step "Packaging Microsoft Store .msix"
    mkdir -p "$OUT_DIR"
    run dart run msix:create \
        --build-windows false \
        --version "$VERSION.0" \
        --output-path "$OUT_DIR" \
        --output-name "m3u-tv-v$VERSION-windows"
    info "${GREEN}-> build/release/v$VERSION/m3u-tv-v$VERSION-windows.msix${RESET}"
    info "Upload it in Partner Center. It's Store-signed on ingestion, so it won't sideload as-is."
}

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------

echo "${BOLD}M3U TV release build${RESET}"
info "Version:   $VERSION (build $BUILD_NUMBER)"
info "Platforms: ${PLATFORMS[*]}"
info "Output:    build/release/v$VERSION/"
if $UPLOAD; then info "Upload:    Apple builds to App Store Connect"; fi
if $OPEN_XCODE; then info "Apple:     archive, then open in Xcode"; fi
if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
    warn "The working tree has uncommitted changes; they'll be in the build."
fi
info "Store uploads need a build number higher than the last one uploaded."
confirm "Continue?" || exit 1

if $CLEAN; then
    step "flutter clean"
    run flutter clean
fi

SUCCEEDED=()
FAILED=()
for platform in "${PLATFORMS[@]}"; do
    step "Building $platform"
    # A subshell per platform, so one failure doesn't stop the rest.
    set +e
    (set -e; "build_$platform")
    status=$?
    set -e
    if [[ $status -eq 0 ]]; then
        SUCCEEDED+=("$platform")
    else
        FAILED+=("$platform")
        echo "${RED}    $platform failed (exit $status).${RESET}" >&2
    fi
done

step "Summary"
if [[ ${#SUCCEEDED[@]} -gt 0 ]]; then info "${GREEN}Built:  ${SUCCEEDED[*]}${RESET}"; fi
if [[ ${#FAILED[@]} -gt 0 ]]; then info "${RED}Failed: ${FAILED[*]}${RESET}"; fi
if [[ -d "$OUT_DIR" ]]; then
    info "Artifacts in build/release/v$VERSION/:"
    for artifact in "$OUT_DIR"/*; do
        [[ -e "$artifact" ]] && info "  $(basename "$artifact")"
    done
fi
offer_transporter
[[ ${#FAILED[@]} -eq 0 ]]

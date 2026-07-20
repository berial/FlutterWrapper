#!/bin/bash
# fix-local-properties.sh - Configure local.properties for mixed SDK setup.
#
# Architecture:
#   - sdk.dir   -> Windows SDK (/mnt/d/Android/Sdk)
#                  Provides build-tools (aapt2, aidl, dexdump, zipalign, ...)
#                  which have Linux shell wrappers that call .exe via WSL
#                  interop. Also provides platform-tools (adb.exe).
#   - ndk.dir   -> WSL-local NDK ($HOME/.android-sdk-wsl/ndk/<ver>)
#                  Linux native compiler; Windows NDK has only .exe.
#   - cmake.dir -> WSL-local cmake ($HOME/.android-sdk-wsl/cmake/3.22.1)
#                  Linux native; Windows cmake is .exe only.
#
# flutter's updateLocalProperties() rewrites sdk.dir from ANDROID_HOME on each
# run, so sdk.dir may flip back to /mnt/d/Android/Sdk (which is what we want).
# ndk.dir and cmake.dir are NOT touched by flutter, so they persist.
#
# This script also clears .cxx caches (baked-in NDK paths from old failures).
#
# Run inside WSL: bash /mnt/d/Android/FlutterWrapper/tools/fix-local-properties.sh [project]

set -e

PROJECT="${1:-/home/berial/workspace/flutter/sd_ldar}"
LOCAL_PROPS="$PROJECT/android/local.properties"
WSL_SDK="$HOME/.android-sdk-wsl"

# Default Windows SDK path (used if not auto-detectable)
WIN_SDK="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-/mnt/d/Android/Sdk}}"

if [ ! -f "$LOCAL_PROPS" ]; then
    echo "ERROR: $LOCAL_PROPS not found"
    exit 1
fi

if [ ! -d "$WSL_SDK/ndk" ]; then
    echo "ERROR: $WSL_SDK/ndk not found. Run tools/setup-wsl-ndk.sh first."
    exit 1
fi

# Pick highest NDK version
NDK_VER=$(ls "$WSL_SDK/ndk" | sort -V | tail -1)
NDK_PATH="$WSL_SDK/ndk/$NDK_VER"

if [ ! -d "$NDK_PATH/toolchains/llvm/prebuilt/linux-x86_64" ]; then
    echo "ERROR: Linux NDK toolchain not found at $NDK_PATH/toolchains/llvm/prebuilt/linux-x86_64"
    exit 1
fi

echo "=== Before ==="
cat "$LOCAL_PROPS"
echo ""

# Rewrite local.properties (preserving flutter.* keys)
TMP=$(mktemp)
{
    echo "sdk.dir=$WIN_SDK"
    echo "ndk.dir=$NDK_PATH"
    echo "cmake.dir=$WSL_SDK/cmake/3.22.1"
    # Preserve flutter.* keys (flutter.sdk, flutter.buildMode, etc.)
    grep '^flutter\.' "$LOCAL_PROPS" 2>/dev/null || true
} > "$TMP"

cp "$TMP" "$LOCAL_PROPS"
rm -f "$TMP"

echo "=== After ==="
cat "$LOCAL_PROPS"
echo ""

# Clear .cxx caches (they contain baked-in NDK paths from previous failures)
echo "=== Clearing .cxx caches ==="
rm -rf "$PROJECT/android/.cxx" 2>/dev/null && echo "  removed $PROJECT/android/.cxx" || echo "  (no .cxx in project)"
rm -rf "$PROJECT/build/jni" 2>/dev/null && echo "  removed $PROJECT/build/jni" || echo "  (no build/jni in project)"

# Also clear .cxx in pub packages that use native build (jni, etc.)
echo ""
echo "=== Clearing .cxx in pub packages (jni, ...) ==="
for pkg_cxx in ~/.pub-cache/hosted/pub.dev/jni-*/android/.cxx; do
    if [ -d "$pkg_cxx" ]; then
        rm -rf "$pkg_cxx" && echo "  removed $pkg_cxx"
    fi
done

echo ""
echo "=== DONE ==="
echo "sdk.dir   = $WIN_SDK   (Windows SDK; build-tools have shell wrappers)"
echo "ndk.dir   = $NDK_PATH  (WSL Linux NDK)"
echo "cmake.dir = $WSL_SDK/cmake/3.22.1  (WSL Linux cmake)"
echo ""
echo "Note: flutter will rewrite sdk.dir from ANDROID_HOME on each run."
echo "      wrapper.ps1 injects ANDROID_HOME=<Windows SDK>, so sdk.dir stays"
echo "      pointing at Windows SDK (which is what we want for build-tools)."
echo ""
echo "Next: re-run flutter in Android Studio. If daemon was started before"
echo "      wrapper.ps1 was updated, restart AS so ANDROID_NDK_HOME is injected."

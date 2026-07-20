#!/bin/bash
# setup-wsl-ndk.sh - Install Linux NDK in WSL for native Android builds.
#
# Windows NDK (.exe compiler) cannot be used by WSL Linux cmake/ninja.
# This script:
#   1. Downloads Linux Android cmdline-tools
#   2. Installs NDK 28.2.13676358 (matches Windows version) to WSL-local SDK
#   3. Adds sdkmanager to PATH (for future use)
#   4. Updates project's local.properties to point to WSL SDK
#
# Run inside WSL: bash /mnt/d/Android/FlutterWrapper/tools/setup-wsl-ndk.sh

set -e

WSL_SDK="$HOME/.android-sdk-wsl"
CMDLINE_TOOLS_URL="https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"
NDK_VERSION="28.2.13676358"

echo "=== Step 1: Setup WSL-local Android SDK directory ==="
mkdir -p "$WSL_SDK/cmdline-tools"
ls -la "$WSL_SDK"

# Resolve JAVA_HOME (sdkmanager needs it)
if [ -z "$JAVA_HOME" ]; then
    # Try vfox-managed Java first
    if [ -d "$HOME/.vfox/sdks/java" ]; then
        export JAVA_HOME=$(readlink -f "$HOME/.vfox/sdks/java")
    elif [ -x /usr/lib/jvm/default-java/bin/java ]; then
        export JAVA_HOME=/usr/lib/jvm/default-java
    fi
fi
export PATH="$JAVA_HOME/bin:$PATH"
echo "Using JAVA_HOME=$JAVA_HOME"
java -version 2>&1 | head -1

echo ""
echo "=== Step 2: Download Linux cmdline-tools ==="
if [ -d "$WSL_SDK/cmdline-tools/latest" ]; then
    echo "cmdline-tools already installed, skipping"
else
    TMP_ZIP="/tmp/cmdline-tools.zip"
    if [ ! -f "$TMP_ZIP" ]; then
        echo "Downloading from $CMDLINE_TOOLS_URL..."
        curl -fL -o "$TMP_ZIP" "$CMDLINE_TOOLS_URL"
    fi
    echo "Extracting..."
    unzip -q "$TMP_ZIP" -d /tmp/cmdline-tools-extract
    # cmdline-tools extracts as /tmp/cmdline-tools-extract/cmdline-tools/
    mv /tmp/cmdline-tools-extract/cmdline-tools "$WSL_SDK/cmdline-tools/latest"
    rm -rf /tmp/cmdline-tools-extract
fi

export ANDROID_HOME="$WSL_SDK"
export PATH="$WSL_SDK/cmdline-tools/latest/bin:$PATH"

echo ""
echo "=== Step 3: Verify sdkmanager ==="
sdkmanager --version

echo ""
echo "=== Step 4: Accept licenses and install NDK $NDK_VERSION ==="
yes | sdkmanager --licenses > /dev/null 2>&1 || true

if [ -d "$WSL_SDK/ndk/$NDK_VERSION" ]; then
    echo "NDK $NDK_VERSION already installed"
else
    sdkmanager "ndk;$NDK_VERSION"
fi

echo ""
echo "=== Step 5: Verify NDK installation ==="
ls "$WSL_SDK/ndk/"
ls "$WSL_SDK/ndk/$NDK_VERSION/toolchains/llvm/prebuilt/"

echo ""
echo "=== Step 6: Also install cmake via sdkmanager (Linux native) ==="
if [ ! -d "$WSL_SDK/cmake/3.22.1" ]; then
    sdkmanager "cmake;3.22.1"
fi
ls "$WSL_SDK/cmake/" 2>&1

echo ""
echo "=== DONE ==="
echo "WSL SDK location: $WSL_SDK"
echo "NDK: $WSL_SDK/ndk/$NDK_VERSION"
echo "CMake: $WSL_SDK/cmake/3.22.1"
echo ""
echo "Next: update android/local.properties to use this WSL SDK:"
echo "  sdk.dir=$WSL_SDK"

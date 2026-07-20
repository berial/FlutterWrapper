#!/bin/bash
set -e

echo '=== 创建目标目录 ==='
mkdir -p ~/android ~/.cache

echo '=== 1. Android SDK ==='
if [ -d ~/.android-sdk-wsl ]; then
    mv ~/.android-sdk-wsl ~/android/sdk
    echo '  moved ~/.android-sdk-wsl -> ~/android/sdk'
fi

echo '=== 2. Android AVD/keystore ==='
if [ -d ~/.android ]; then
    mv ~/.android ~/android/.android
    echo '  moved ~/.android -> ~/android/.android'
fi

echo '=== 3. Gradle ==='
if [ -d ~/.gradle ]; then
    mv ~/.gradle ~/android/gradle
    echo '  moved ~/.gradle -> ~/android/gradle'
fi

echo '=== 4. Pub Cache ==='
if [ -d ~/.pub-cache ]; then
    mv ~/.pub-cache ~/.cache/pub-cache
    echo '  moved ~/.pub-cache -> ~/.cache/pub-cache'
fi

echo '=== 5. Dart Analysis Server ==='
if [ -d ~/.dartServer ]; then
    mv ~/.dartServer ~/.cache/dartServer
    echo '  moved ~/.dartServer -> ~/.cache/dartServer'
fi

echo '=== 6. vfox cache (软链接保持兼容) ==='
if [ -d ~/.vfox/cache ] && [ ! -L ~/.vfox/cache ]; then
    mv ~/.vfox/cache ~/.cache/vfox
    ln -s ~/.cache/vfox ~/.vfox/cache
    echo '  moved ~/.vfox/cache -> ~/.cache/vfox (symlinked)'
fi

echo ''
echo '=== 写入环境变量到 ~/.bashrc ==='
if ! grep -q 'ANDROID_HOME="$HOME/android/sdk"' ~/.bashrc; then
    cat >> ~/.bashrc << 'ENV'

# ===== Reorganized Paths (2026-07-20) =====
# Android
export ANDROID_HOME="$HOME/android/sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export ANDROID_AVD_HOME="$HOME/android/avd"
mkdir -p "$ANDROID_AVD_HOME" 2>/dev/null
NDK_VERSION=$(ls "$ANDROID_HOME/ndk" 2>/dev/null | sort -V | tail -1)
if [ -n "$NDK_VERSION" ]; then
    export ANDROID_NDK_HOME="$ANDROID_HOME/ndk/$NDK_VERSION"
    export ANDROID_NDK_ROOT="$ANDROID_NDK_HOME"
fi
export GRADLE_USER_HOME="$HOME/android/gradle"

# Dart/Flutter
export PUB_CACHE="$HOME/.cache/pub-cache"
export ANALYZER_STATE_LOCATION_OVERRIDE="$HOME/.cache/dartServer"

# Path
export PATH="$ANDROID_HOME/platform-tools:$ANDROID_HOME/cmdline-tools/latest/bin:$HOME/.local/bin:$PATH"
ENV
    echo '  已写入 ~/.bashrc'
else
    echo '  ~/.bashrc 已有配置，跳过'
fi

echo ''
echo '=== 同步到 ~/.zshrc ==='
if [ -f ~/.zshrc ] && ! grep -q 'ANDROID_HOME="$HOME/android/sdk"' ~/.zshrc; then
    sed -n '/# ===== Reorganized Paths/,/^ENV$/p' ~/.bashrc >> ~/.zshrc
    echo '  已同步到 ~/.zshrc'
fi

echo ''
echo '=== 完成 ==='

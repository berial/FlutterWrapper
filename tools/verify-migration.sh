#!/bin/bash
source ~/.profile

echo '=== 环境变量 ==='
echo "ANDROID_HOME=$ANDROID_HOME"
echo "GRADLE_USER_HOME=$GRADLE_USER_HOME"
echo "PUB_CACHE=$PUB_CACHE"
echo "ANALYZER_STATE_LOCATION_OVERRIDE=$ANALYZER_STATE_LOCATION_OVERRIDE"
echo "ANDROID_NDK_HOME=$ANDROID_NDK_HOME"
echo "ANDROID_NDK_ROOT=$ANDROID_NDK_ROOT"
echo "PATH=$PATH" | tr ':' '\n' | head -5

echo ''
echo '=== SDK 目录 ==='
ls "$ANDROID_HOME/" 2>&1

echo ''
echo '=== platform-tools ==='
ls "$ANDROID_HOME/platform-tools/adb" 2>&1
ls "$ANDROID_HOME/platform-tools/" 2>&1 | head -5

echo ''
echo '=== cmdline-tools ==='
ls "$ANDROID_HOME/cmdline-tools/" 2>&1

echo ''
echo '=== NDK ==='
ls "$ANDROID_HOME/ndk/" 2>&1

echo ''
echo '=== Gradle init.d ==='
ls "$GRADLE_USER_HOME/init.d/" 2>&1

echo ''
echo '=== Pub cache ==='
ls "$PUB_CACHE/hosted/" 2>&1 | head -5

echo ''
echo '=== Analysis Server ==='
ls "$ANALYZER_STATE_LOCATION_OVERRIDE/" 2>&1 | head -5

echo ''
echo '=== Flutter ==='
ls ~/.vfox/cache/flutter/*/flutter-*/bin/flutter 2>&1
which flutter 2>&1
flutter --version 2>&1 | head -3

echo ''
echo '=== adb ==='
which adb 2>&1
adb version 2>&1 | head -2

#!/bin/bash
# setup-gradle-mirror.sh - Install Alibaba Cloud mirror init script for gradle.
#
# WSL proxy + Java TLS + dl.google.com causes handshake failures.
# Alibaba mirrors are fast in China without proxy. This init script
# redirects Google Maven / Maven Central / Gradle Plugin Portal to
# Alibaba mirrors, applied to ALL gradle builds (no project modification).
#
# Run inside WSL: bash /mnt/d/Android/FlutterWrapper/tools/setup-gradle-mirror.sh

set -e

INIT_DIR="$HOME/.gradle/init.d"
INIT_FILE="$INIT_DIR/mirror.gradle"
SOURCE="/mnt/d/Android/FlutterWrapper/tools/init-mirror.gradle"

mkdir -p "$INIT_DIR"

# Copy (not symlink) so that even if FlutterWrapper repo is removed,
# the mirror config persists.
cp "$SOURCE" "$INIT_FILE"
echo "Installed: $INIT_FILE"
echo ""
echo "=== verify ==="
ls -la "$INIT_FILE"
echo ""
echo "=== test mirror connectivity ==="
curl -sI -o /dev/null -w "aliyun google: HTTP %{http_code}, time %{time_total}s\n" https://maven.aliyun.com/repository/google/ 2>&1
curl -sI -o /dev/null -w "aliyun public: HTTP %{http_code}, time %{time_total}s\n" https://maven.aliyun.com/repository/public/ 2>&1
curl -sI -o /dev/null -w "aliyun plugin: HTTP %{http_code}, time %{time_total}s\n" https://maven.aliyun.com/repository/gradle-plugin/ 2>&1

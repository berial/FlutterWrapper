#!/bin/bash
# setup-local-properties.sh - Add cmake.dir to android/local.properties
# so AGP uses WSL-native cmake/ninja instead of Windows .exe.
#
# Run inside WSL: bash /mnt/d/Android/FlutterWrapper/tools/setup-local-properties.sh <project>

PROJECT="${1:-/home/berial/workspace/flutter/sd_ldar}"
LOCAL_PROPS="$PROJECT/android/local.properties"

if [ ! -f "$LOCAL_PROPS" ]; then
    echo "ERROR: $LOCAL_PROPS not found"
    exit 1
fi

# Check if cmake.dir already present
if grep -q "^cmake.dir=" "$LOCAL_PROPS"; then
    echo "cmake.dir already in $LOCAL_PROPS:"
    grep "^cmake.dir=" "$LOCAL_PROPS"
    exit 0
fi

# Append cmake.dir pointing to our WSL cmake wrapper
cat >> "$LOCAL_PROPS" <<EOF

# Use WSL-native cmake/ninja (Windows .exe cannot be exec'd by Linux gradle)
cmake.dir=/home/berial/.android-sdk-wsl/cmake
EOF

echo "Updated: $LOCAL_PROPS"
echo "--- contents ---"
cat "$LOCAL_PROPS"

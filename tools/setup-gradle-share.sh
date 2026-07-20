#!/bin/bash
# setup-gradle-share.sh - Share Windows gradle wrapper dists with WSL.
#
# Gradle wrapper downloads distributions to <GRADLE_USER_HOME>/wrapper/dists/.
# WSL has its own ~/.gradle, so it re-downloads versions Windows already has.
# The distribution zip is cross-platform (contains both gradle and gradle.bat),
# so we can safely share wrapper/dists between Windows and WSL via symlink.
#
# We share ONLY wrapper/dists (large, one-time downloads, cross-platform).
# We do NOT share caches/ (many small files, slow on 9p) or daemon/
# (OS-specific daemon registry).
#
# Run inside WSL: bash /mnt/d/Android/FlutterWrapper/tools/setup-gradle-share.sh

set -e

WIN_GRADLE_HOME="${GRADLE_USER_HOME:-/mnt/d/Android/Gradle}"
WIN_DISTS="$WIN_GRADLE_HOME/wrapper/dists"
WSL_GRADLE_HOME="$HOME/.gradle"
WSL_DISTS="$WSL_GRADLE_HOME/wrapper/dists"

echo "=== source (Windows) ==="
echo "  $WIN_DISTS"
if [ ! -d "$WIN_DISTS" ]; then
    echo "ERROR: Windows gradle dists not found at $WIN_DISTS"
    echo "Set GRADLE_USER_HOME env var to your Windows gradle home (as WSL path)."
    exit 1
fi
echo "  contents: $(ls "$WIN_DISTS" | tr '\n' ' ')"
echo ""

echo "=== target (WSL) ==="
echo "  $WSL_DISTS"
echo ""

# If already a symlink, report and exit
if [ -L "$WSL_DISTS" ]; then
    current=$(readlink "$WSL_DISTS")
    if [ "$current" = "$WIN_DISTS" ]; then
        echo "Already symlinked: $WSL_DISTS -> $WIN_DISTS"
        exit 0
    else
        echo "Symlink exists but points to $current (expected $WIN_DISTS)"
        echo "Removing and re-creating..."
        rm "$WSL_DISTS"
    fi
fi

# If directory exists with content, back it up
if [ -d "$WSL_DISTS" ] && [ -n "$(ls -A "$WSL_DISTS" 2>/dev/null)" ]; then
    backup="$WSL_DISTS.bak.$(date +%s)"
    echo "Backing up existing WSL dists to $backup"
    mv "$WSL_DISTS" "$backup"
elif [ -d "$WSL_DISTS" ]; then
    rmdir "$WSL_DISTS"
fi

# Create symlink
ln -s "$WIN_DISTS" "$WSL_DISTS"
echo ""
echo "Created symlink: $WSL_DISTS -> $WIN_DISTS"
echo ""
echo "=== verify ==="
ls -la "$WSL_DISTS" | head -5
echo ""
echo "Now WSL gradle wrapper will reuse Windows-downloaded distributions."
echo "(Distribution zips are cross-platform; both gradle and gradle.bat are inside.)"

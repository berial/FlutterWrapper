#!/bin/bash
# check-native-build-tools.sh - Diagnose CMake/Ninja availability for WSL.
echo "=== WSL ninja ==="
which ninja 2>&1
ninja --version 2>&1

echo ""
echo "=== WSL cmake ==="
which cmake 2>&1
cmake --version 2>&1 | head -1

echo ""
echo "=== Windows SDK CMake folder ==="
ls /mnt/d/Android/Sdk/cmake/ 2>&1
echo ""
echo "=== Look inside each CMake version ==="
for d in /mnt/d/Android/Sdk/cmake/*/; do
    echo "  $d:"
    ls "$d/bin/" 2>&1 | head -10
    echo ""
done

echo "=== apt available? ==="
which apt 2>&1

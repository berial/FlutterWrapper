#!/bin/bash
# setup-wsl-symlink.sh - Create symlinks so both AS analyzer (Windows) and
# WSL flutter compiler can read the SAME package_config.json.
#
# Problem:
#   - AS Dart analyzer (Windows) needs Windows-accessible paths in
#     package_config.json. UNC form (file://///wsl.localhost/...) crashes
#     the analyzer's Blaze workspace detector and path package's URI
#     converter (FormatException on '?' from \\?\UNC\ prefix).
#   - WSL flutter compiler needs paths it can read. W: mapped drive form
#     (file:///W:/...) is not directly readable by WSL Dart because /W:/
#     doesn't exist in the WSL filesystem.
#
# Solution:
#   1. /wsl.localhost/<distro> -> / symlink:
#      Lets WSL Dart read UNC form URIs (legacy, kept for compatibility).
#   2. /<Drive>:/<dir> -> /<dir> symlinks (e.g. /W:/home -> /home):
#      Lets WSL Dart read mapped drive form URIs. WSL Dart parses
#      file:///W:/home/berial/... as path /W:/home/berial/..., then
#      /W:/home symlink resolves to /home, giving /home/berial/...
#   3. /blaze-out empty dir:
#      Prevents Windows analyzer's Blaze workspace detector from crashing
#      when it stats \\wsl.localhost\blaze-out (returns false instead of
#      throwing "OS Error 67 找不到网络名").
#
# After this, package_config.json uses file:///W:/home/berial/... form,
# readable by BOTH Windows AS analyzer (via W: drive mapping) and WSL
# flutter compiler (via /W:/home -> /home symlink). No swap needed.
#
# Requires sudo (creates symlinks under / and /wsl.localhost).
#
# Run inside WSL: bash /mnt/d/Android/FlutterWrapper/tools/setup-wsl-symlink.sh [distro] [drive]

set -e

DISTRO="${1:-Ubuntu-24.04}"
DRIVE="${2:-W}"

echo "=== Creating /wsl.localhost/$DISTRO -> / symlink ==="
sudo mkdir -p /wsl.localhost
if [ -e "/wsl.localhost/$DISTRO" ] && [ -L "/wsl.localhost/$DISTRO" ]; then
    TARGET=$(readlink "/wsl.localhost/$DISTRO")
    if [ "$TARGET" = "/" ]; then
        echo "  already correct: /wsl.localhost/$DISTRO -> /"
    else
        echo "  recreating (was -> $TARGET)"
        sudo rm -f "/wsl.localhost/$DISTRO"
        sudo ln -sfn / "/wsl.localhost/$DISTRO"
    fi
elif [ -e "/wsl.localhost/$DISTRO" ]; then
    echo "  ERROR: /wsl.localhost/$DISTRO exists but is not a symlink. Remove it manually first."
    exit 1
else
    sudo ln -sfn / "/wsl.localhost/$DISTRO"
fi

echo ""
echo "=== Creating /$DRIVE:/ symlinks (for mapped drive URI form) ==="
# WSL Dart parses file:///w:/home/berial/... as /w:/home/berial/...
# IMPORTANT (case sensitivity): flutter.ps1 lowercases the drive letter when
# translating package_config.json (emits file:///w:/...), but historically the
# symlink root was created upper-case (/W:). Linux paths ARE case-sensitive, so
# an upper-case /W: symlink can NOT resolve a lower-case /w:/... path (this was
# the root cause of "Error when reading '/w:/home/...': No such file" on WSL
# compiles). Windows drive letters are case-INsensitive, so file:///W:/ and
# file:///w:/ are equivalent to the AS analyzer. Therefore we create BOTH the
# lower- and upper-case symlink roots to be robust regardless of the case emitted.
DRIVE_LOWER=$(echo "$DRIVE" | tr '[:upper:]' '[:lower:]')
DRIVE_UPPER=$(echo "$DRIVE" | tr '[:lower:]' '[:upper:]')
for D in "$DRIVE_LOWER" "$DRIVE_UPPER"; do
    sudo mkdir -p "/$D:"
    for dir in home usr opt etc var bin lib sbin root; do
        if [ -d "/$dir" ]; then
            sudo ln -sfn "/$dir" "/$D:/$dir"
        fi
    done
    echo "  /$D:/ contents:"
    ls -la "/$D:/"
done

echo ""
echo "=== Creating /blaze-out empty dir (Blaze workspace detector workaround) ==="
# Windows Dart analyzer's Blaze workspace detector stats
# \\?\UNC\wsl.localhost\blaze-out when given UNC paths. Without this dir,
# it throws "OS Error 67 找不到网络名" and crashes the analysis server.
# With this empty dir (no BUILD file), Blaze detection returns false cleanly.
if [ ! -e "/blaze-out" ]; then
    sudo mkdir -p /blaze-out
    echo "  created /blaze-out (empty dir)"
else
    echo "  /blaze-out already exists"
fi

echo ""
echo "=== Verification ==="
echo "Symlinks:"
ls -la /wsl.localhost/ "/$DRIVE:/" | grep -E "^l|^d" | head -20

echo ""
echo "=== Dart URI test (WSL) ==="
cat > /tmp/test_uris.dart << EOF
import 'dart:io';
void main() {
  var realFile = '/home/$USER/.pub-cache/hosted/pub.dev/archive-4.0.9/lib/archive.dart';
  if (!File(realFile).existsSync()) {
    print('SKIP: $realFile does not exist (no archive package in pub-cache)');
    return;
  }
  var uri = Uri.parse('file:///$DRIVE_LOWER:/home/$USER/.pub-cache/hosted/pub.dev/archive-4.0.9/lib/archive.dart');
  var file = File.fromUri(uri);
  print('w: form path: \${file.path}');
  print('w: form exists: \${file.existsSync()}');
}
EOF
dart /tmp/test_uris.dart 2>&1 || /home/$USER/.vfox/sdks/flutter/bin/dart /tmp/test_uris.dart 2>&1
rm -f /tmp/test_uris.dart

echo ""
echo "=== DONE ==="
echo "Symlinks created. Next: run 'flutter pub get' to regenerate"
echo "package_config.json in mapped drive (file:///W:/...) form."

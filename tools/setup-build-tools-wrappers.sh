#!/bin/bash
# setup-build-tools-wrappers.sh
# Creates Linux wrapper scripts for Windows build-tools executables.
# Run inside WSL: bash /mnt/d/Android/FlutterWrapper/tools/setup-build-tools-wrappers.sh
#
# Flutter on Linux looks for tools without .exe extension (e.g. aapt, aapt2).
# Windows SDK only ships .exe versions. This script creates shell wrappers
# that delegate to the corresponding .exe, which runs via WSL interop and
# shares the Windows adb server / SDK state.

set -e

SDK="${ANDROID_HOME:-/mnt/d/Android/Sdk}"

if [ ! -d "$SDK/build-tools" ]; then
    echo "ERROR: build-tools not found at $SDK/build-tools"
    exit 1
fi

# Tools flutter/gradle may invoke (without .exe extension).
TOOLS="aapt aapt2 zipalign dexdump aidl split-select bcc_compat llvm-rs-cc"

count=0
for bt_dir in "$SDK"/build-tools/*/; do
    [ -d "$bt_dir" ] || continue
    bt_ver=$(basename "$bt_dir")
    echo "==> build-tools/$bt_ver"
    for tool in $TOOLS; do
        exe="$bt_dir${tool}.exe"
        wrapper="$bt_dir${tool}"
        if [ -f "$exe" ] && [ ! -f "$wrapper" ]; then
            cat > "$wrapper" <<EOF
#!/bin/bash
# FlutterWrapper: Linux wrapper for Windows ${tool}.exe (build-tools/$bt_ver).
exec "\$(dirname "\$0")/${tool}.exe" "\$@"
EOF
            chmod +x "$wrapper"
            echo "    created: $tool"
            count=$((count + 1))
        elif [ -f "$wrapper" ]; then
            echo "    exists:  $tool"
        fi
    done
done

echo ""
echo "Done. $count wrapper(s) created."
echo "Verify: cd \$ANDROID_HOME/build-tools/<ver> && ./aapt version"

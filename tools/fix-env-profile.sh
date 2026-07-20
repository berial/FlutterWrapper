#!/bin/bash
set -e

BASHRC="$HOME/.bashrc"
PROFILE="$HOME/.profile"

echo '=== 1. 从 ~/.bashrc 移除之前追加的环境变量块 ==='
# 删除从 "# ===== Reorganized Paths" 到文件末尾的内容
if grep -q '# ===== Reorganized Paths' "$BASHRC"; then
    # 找到标记行号，删除该行及之后所有内容
    LINE=$(grep -n '# ===== Reorganized Paths' "$BASHRC" | head -1 | cut -d: -f1)
    if [ -n "$LINE" ]; then
        sed -i "${LINE},\$d" "$BASHRC"
        # 删除末尾空行
        sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$BASHRC"
        echo "  已从 ~/.bashrc 第 $LINE 行开始删除"
    fi
fi

echo ''
echo '=== 2. 写入环境变量到 ~/.profile ==='
# 先移除旧块（如果重复运行）
if grep -q '# ===== Reorganized Paths' "$PROFILE"; then
    LINE=$(grep -n '# ===== Reorganized Paths' "$PROFILE" | head -1 | cut -d: -f1)
    if [ -n "$LINE" ]; then
        sed -i "${LINE},\$d" "$PROFILE"
        sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$PROFILE"
    fi
fi

cat >> "$PROFILE" << 'ENV'

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
echo '  已写入 ~/.profile'

echo ''
echo '=== 3. 同步到 ~/.zshrc（zsh 不读 .profile，需单独配置）==='
if [ -f "$HOME/.zshrc" ]; then
    # 移除旧块
    if grep -q '# ===== Reorganized Paths' "$HOME/.zshrc"; then
        LINE=$(grep -n '# ===== Reorganized Paths' "$HOME/.zshrc" | head -1 | cut -d: -f1)
        if [ -n "$LINE" ]; then
            sed -i "${LINE},\$d" "$HOME/.zshrc"
            sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$HOME/.zshrc"
        fi
    fi
    # zsh 也需要 source .profile 的内容，直接追加
    cat >> "$HOME/.zshrc" << 'ENV'

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
    echo '  已写入 ~/.zshrc'
fi

echo ''
echo '=== 完成 ==='
echo ''
echo '验证:'
echo '  source ~/.profile'
echo '  echo $ANDROID_HOME'

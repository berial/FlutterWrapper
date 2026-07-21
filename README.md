# FlutterWrapper

[English](README.md) | [中文](README_zh-CN.md)

> Windows Android Studio + WSL Flutter — Compatibility Orchestration Layer
> v3.1 — Seamlessly bridge Windows IDE with WSL Flutter toolchain. Diagnose, repair, and manage.

## What It Does

FlutterWrapper lets Android Studio on Windows use a Flutter SDK installed inside WSL2 — **without installing Flutter on Windows**.

It simulates a Flutter SDK directory structure, transparently forwards all `flutter`/`dart` commands to WSL, and translates paths bidirectionally so the IDE never knows the difference.

```
Android Studio → flutter.bat → flutter.ps1 → wsl.exe → WSL Flutter
                  ↑ Windows paths ↔ WSL paths translated ↑
```

## Quick Start

```powershell
git clone https://github.com/berial/FlutterWrapper.git %USERPROFILE%\FlutterWrapper
powershell -NoProfile -ExecutionPolicy Bypass -File %USERPROFILE%\FlutterWrapper\install.ps1 -Auto
%USERPROFILE%\FlutterWrapper\bin\fw.bat doctor
```

### Prerequisites
- Windows 10/11 with WSL2
- Flutter SDK in WSL (via [vfox](https://vfox.dev) or [FVM](https://fvm.app))
- Android Studio + Flutter plugin

### Configure Android Studio
1. **Settings → Languages & Frameworks → Flutter** → SDK path: `%USERPROFILE%\FlutterWrapper`
2. **Settings → Languages & Frameworks → Dart** → SDK path: `%USERPROFILE%\FlutterWrapper\bin\cache\dart-sdk`
3. ⚠️ Open WSL projects via mapped drive: `W:\home\<user>\<project>` — NOT UNC `\\wsl.localhost\...`

## Core Commands (`fw`)

```powershell
fw doctor                 # 13-category diagnostic
fw doctor --fix-safe      # diagnose + auto-repair safe items
fw repair dart-sdk        # repair specific component
fw repair --list          # list all repair modules
fw provider               # show SDK manager (vfox/FVM)
fw flutter current        # current Flutter version
fw flutter use 3.44.6     # switch version (routes to provider)
fw status                 # quick summary
```

## How It Works

| Layer | What | Detail |
|-------|------|--------|
| **SDK Proxy** | Simulates Flutter SDK | `flutter.bat`, `dart.bat`, Junction to Windows dart-sdk, `pubspec.yaml` stub |
| **Command Bridge** | Forwards to WSL | `flutter.ps1`/`dart.ps1` → `wsl.exe -e flutter/dart` |
| **Path Translation** | Bidirectional | `D:\x` ↔ `/mnt/d/x`, `\\wsl.localhost\...` ↔ `/home/...` |
| **Daemon Translator** | TCP JSON-RPC | `wrapper.ps1` — two-Runspace text-mode bridge on port 9876 |
| **Dart Analysis** | Dual-track | Windows `dart.exe` via Junction for IDE; WSL symlinks for compiler |
| **Android Bridge** | Hybrid toolchain | Windows SDK + WSL Linux NDK/cmake via `local.properties` |
| **Gradle Adapter** | Mirror + cache | Aliyun Maven mirror, dists symlink sharing |

## Key Features

| Feature | Description |
|---------|-------------|
| **One-command install** | `install.ps1 -Auto` detects WSL, Flutter (vfox/FVM), JDK, Android SDK, generates config |
| **Diagnostics** | `fw doctor` checks 13 categories with fix suggestions |
| **Auto-repair** | `fw repair <module>` — 7 idempotent modules (package-config, dart-sdk, symlinks, config, vfox, daemon, cache) |
| **Provider integration** | Detects and integrates with vfox / FVM, not replaces them |
| **Split logging** | `logs/flutter.log` / `dart.log` / `bridge.log` by command type |
| **UTF-8 safe** | Full chain UTF-8, handles CJK paths and emoji |

## Support Matrix

| Component | Supported |
|-----------|-----------|
| Windows | 10 / 11 |
| WSL | Ubuntu 22.04 / 24.04, Debian |
| Flutter | 3.22+ (3.44+ recommended) |
| Android Studio | Koala / Ladybug / Quail |
| SDK Manager | vfox, FVM |

## Docs

- [Quick Start](docs/quick-start.md) ([中文](docs/quick-start_zh-CN.md))
- [FAQ](docs/faq.md) ([中文](docs/faq_zh-CN.md))
- [Troubleshooting](docs/troubleshooting.md) ([中文](docs/troubleshooting_zh-CN.md))
- [Architecture](docs/architecture.md)
- [Daemon Protocol](docs/daemon.md)
- [Path Translation](docs/path-convert.md)

## License

MIT — see [LICENSE](LICENSE).

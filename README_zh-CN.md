# FlutterWrapper

[English](README.md) | [中文](README_zh-CN.md)

> Windows Android Studio + WSL Flutter 兼容编排层
> v3.1 — 让 Windows IDE 与 WSL Flutter 工具链无缝协作，提供诊断、修复和 SDK 管理对接。

## 项目定位

FlutterWrapper 让 Windows 上的 Android Studio 使用 WSL2 内的 Flutter SDK — **无需在 Windows 侧安装 Flutter**。

它在 Windows 侧模拟一个 Flutter SDK 目录结构，把 AS 发起的 `flutter`/`dart` 命令透明转发到 WSL，并双向翻译路径，IDE 完全无感。

```
Android Studio → flutter.bat → flutter.ps1 → wsl.exe → WSL Flutter
                  ↑ Windows 路径 ↔ WSL 路径双向翻译 ↑
```

## 快速开始

```powershell
git clone https://github.com/berial/FlutterWrapper.git %USERPROFILE%\FlutterWrapper
powershell -NoProfile -ExecutionPolicy Bypass -File %USERPROFILE%\FlutterWrapper\install.ps1 -Auto
%USERPROFILE%\FlutterWrapper\bin\fw.bat doctor
```

### 前置要求
- Windows 10/11 + WSL2
- WSL 内已安装 Flutter SDK（推荐 [vfox](https://vfox.dev) 或 [FVM](https://fvm.app)）
- Android Studio + Flutter 插件

### 配置 Android Studio
1. **Settings → Languages & Frameworks → Flutter** → SDK 路径：`%USERPROFILE%\FlutterWrapper`
2. **Settings → Languages & Frameworks → Dart** → SDK 路径：`%USERPROFILE%\FlutterWrapper\bin\cache\dart-sdk`
3. ⚠️ 用映射盘符打开 WSL 项目：`W:\home\<用户名>\<项目>` — 不能用 UNC `\\wsl.localhost\...`

## 核心命令 (`fw`)

```powershell
fw doctor                 # 13 大类诊断
fw doctor --fix-safe      # 诊断 + 自动修复安全项
fw repair dart-sdk        # 修复特定模块
fw repair --list          # 列出所有修复模块
fw provider               # 查看 SDK 管理器 (vfox/FVM)
fw flutter current        # 当前 Flutter 版本
fw flutter use 3.44.6     # 切换版本 (自动路由到 provider)
fw status                 # 快速状态摘要
```

## 工作原理

| 层次 | 做什么 | 细节 |
|------|--------|------|
| **SDK 伪装** | 模拟 Flutter SDK | `flutter.bat`、`dart.bat`、Junction 指向 Windows dart-sdk、`pubspec.yaml` 占位 |
| **命令桥接** | 转发到 WSL | `flutter.ps1`/`dart.ps1` → `wsl.exe -e flutter/dart` |
| **路径翻译** | 双向转换 | `D:\x` ↔ `/mnt/d/x`、`\\wsl.localhost\...` ↔ `/home/...` |
| **Daemon 翻译** | TCP JSON-RPC | `wrapper.ps1` — 双 Runspace 文本桥接，端口 9876 |
| **Dart 分析** | 双轨运行 | Windows `dart.exe`（Junction）给 IDE 分析；WSL 符号链接给编译器 |
| **Android 桥接** | 混合工具链 | Windows SDK + WSL Linux NDK/cmake |
| **Gradle 适配** | 镜像 + 缓存 | 阿里云 Maven 镜像，dists 软链接共享 |

## 核心功能

| 功能 | 说明 |
|------|------|
| **一键安装** | `install.ps1 -Auto` 自动检测 WSL、Flutter（vfox/FVM）、JDK、Android SDK |
| **诊断工具** | `fw doctor` 13 大类检查，失败项附带修复建议 |
| **自动修复** | `fw repair <模块>` 7 个幂等模块 |
| **Provider 对接** | 检测并打通 vfox/FVM，不替代它们 |
| **日志拆分** | `logs/flutter.log` / `dart.log` / `bridge.log` |
| **UTF-8 安全** | 全链路 UTF-8，正确处理中文路径 |

## v3.1 更新内容

- **Doctor 模块化**：`lib/doctor/check-*.ps1` — 13 类检查拆分到 4 个独立模块
- **Provider 适配器**：`lib/providers/vfox.ps1` + `fvm.ps1` — SDK 管理器插件架构
- **诊断报告**：`fw doctor --collect` 生成 `flutterwrapper-report.zip`，提交 Issue 直接上传
- **CI 流水线**：每次推送自动检查 PowerShell 语法、ShellCheck、冒烟测试
- **VERSION 文件**：统一版本号来源，所有脚本读取同一文件

## 支持矩阵

| 组件 | 支持版本 |
|------|---------|
| Windows | 10 / 11 |
| WSL | Ubuntu 22.04 / 24.04, Debian |
| Flutter | 3.22+（推荐 3.44+） |
| Android Studio | Koala / Ladybug / Quail |
| SDK 管理器 | vfox, FVM |

## 文档

- [快速开始](docs/quick-start_zh-CN.md)
- [常见问题](docs/faq_zh-CN.md)
- [故障排查](docs/troubleshooting_zh-CN.md)
- [架构设计](docs/architecture.md)
- [Daemon 协议](docs/daemon.md)
- [路径转换](docs/path-convert.md)

## License

MIT — 详见 [LICENSE](LICENSE)。

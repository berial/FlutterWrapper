# FlutterWrapper

> Windows Android Studio + WSL Flutter 兼容编排层
> v3.0 — 让 Windows IDE 与 WSL Flutter 工具链无缝协作

## 项目目的

在 Windows + WSL2 环境中，Flutter SDK 应该装在 WSL 里（Linux 工具链完整、性能好、版本管理方便）。但 Android Studio 的 Flutter 插件只能指向 Windows 本地 SDK。

FlutterWrapper 在 Windows 侧模拟一个 Flutter SDK 目录，把 AS 发起的 `flutter` / `dart` 命令转发到 WSL，并双向翻译路径，让 IDE 无感。

```
Android Studio → flutter.bat → flutter.ps1 → wsl.exe → WSL 内 flutter
                  ↑ Windows 路径 ↔ WSL 路径双向翻译 ↑
```

## 快速开始

```powershell
# 1. 克隆
git clone https://github.com/<user>/FlutterWrapper.git %USERPROFILE%\FlutterWrapper

# 2. 一键安装（自动检测 WSL、Flutter、JDK、Android SDK）
powershell -NoProfile -ExecutionPolicy Bypass -File %USERPROFILE%\FlutterWrapper\install.ps1 -Auto

# 3. 诊断验证
%USERPROFILE%\FlutterWrapper\bin\fw.bat doctor
```

### 前置要求

- Windows 10/11 + WSL2（Ubuntu 24.04 推荐）
- WSL 内已安装 Flutter SDK（推荐 [vfox](https://vfox.dev) 或 [FVM](https://fvm.app)）
- Android Studio + Flutter 插件

### Android Studio 配置

1. **File → Settings → Languages & Frameworks → Flutter**  
   Flutter SDK path: `%USERPROFILE%\FlutterWrapper`（或你 clone 的路径）
2. **Dart SDK path**: `%USERPROFILE%\FlutterWrapper\bin\cache\dart-sdk`
3. ⚠️ **必须用映射盘符打开 WSL 项目**：`W:\home\<user>\<project>`  
   不能用 UNC 路径 `\\wsl.localhost\...`（CMD 不支持）

## 核心命令 (`fw`)

```powershell
fw doctor                 # 完整诊断（13 大类）
fw doctor --fix-safe      # 诊断 + 自动修复安全项
fw repair dart-sdk        # 修复特定模块
fw repair --list          # 列出所有修复模块
fw provider               # 查看 SDK 管理器（vfox / FVM）
fw flutter current        # 当前 Flutter 版本
fw flutter use 3.44.6     # 切换版本
fw status                 # 快速状态摘要
```

## 支持矩阵

| 组件 | 支持版本 |
|------|---------|
| Windows | 10 / 11 |
| WSL | Ubuntu 22.04 / 24.04, Debian |
| Flutter | 3.22+（推荐 3.44+） |
| Android Studio | Koala / Ladybug / Quail |
| SDK 管理器 | vfox, FVM |

## 常见问题

- **为什么要用 WSL Flutter？** Linux 工具链完整、文件系统性能更好、vfox/FVM 版本管理方便。
- **为什么需要 W: 盘？** CMD.EXE 不支持 UNC 路径作为工作目录，必须映射盘符。
- **为什么修改 package_config.json？** 让 Windows 分析器和 WSL 编译器共享同一个文件。

详见 [docs/faq_zh-CN.md](docs/faq_zh-CN.md)。

## 文档

- [docs/quick-start_zh-CN.md](docs/quick-start_zh-CN.md) — 快速开始
- [docs/faq_zh-CN.md](docs/faq_zh-CN.md) — 常见问题
- [docs/troubleshooting_zh-CN.md](docs/troubleshooting_zh-CN.md) — 故障排查
- [docs/architecture.md](docs/architecture.md) — 架构设计

## License

MIT

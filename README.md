# FlutterWrapper

[English](README.md) | [中文](README_zh-CN.md)

> Windows Android Studio + WSL Flutter 兼容编排层 (Compatibility Orchestration Layer)
> v3.0 — 让 Windows IDE 与 WSL Flutter 工具链无缝协作，并提供诊断、修复、版本管理对接能力。

## 项目目的

在 Windows + WSL2 混合开发环境中，开发者通常会把 Flutter SDK 装在 WSL 里（性能更好、Linux 工具链完整、便于版本管理）。但 Android Studio 的 Flutter 插件只会把 SDK 路径指向一个 Windows 目录，无法直接调用 WSL 内的 `flutter`。

FlutterWrapper 通过在 Windows 侧模拟一个 Flutter SDK 目录结构，把 Android Studio 发起的 `flutter` / `dart` 命令透明地转发到 WSL 内执行，并对路径进行双向翻译，让 IDE 感觉不到差异。

```
Android Studio Flutter Plugin
   │  调用 D:\Android\FlutterWrapper\bin\flutter.bat
   ▼
flutter.bat  ──>  flutter.ps1  ──>  wsl.exe  ──>  WSL 内 flutter
                   │                              ▲
                   │  Windows 路径 → WSL 路径       │
                   │  返回值 → Windows 风格         │
                   ▼                              │
                 logs/flutter.log                    ──┘
```

## 核心功能

| 功能 | 说明 |
|------|------|
| **SDK 结构模拟** | 伪装成完整的 Flutter SDK（`bin/flutter.bat`、`bin/dart.bat`、`bin/cache/dart-sdk`、`packages/flutter/pubspec.yaml`、`bin/cache/flutter.version.json`），让 Android Studio 识别为合法 SDK |
| **命令转发** | `flutter <args>` 和 `dart <args>` 直接转发到 WSL，stdin/stdout/stderr/退出码全保留 |
| **路径双向翻译** | 自动转换 cwd 和参数中的路径：`D:\foo` ↔ `/mnt/d/foo`、`\\wsl.localhost\Ubuntu-24.04\home\user` ↔ `/home/user` |
| **daemon 模式翻译** | `flutter daemon` 走 TCP 9876 翻译器（两 Runspace 文本模式），对 `daemon.getSupportedPlatforms`、`device.startApp`、`app.start`、`app.debugPort` 等帧做路径字段翻译 |
| **UTF-8 安全** | 全链路 UTF-8 编码，正确处理中文路径和 emoji |
| **日志记录** | 所有命令按类型记录到独立日志：`logs/flutter.log`（普通命令）、`logs/dart.log`（dart 命令）、`logs/bridge.log`（daemon），含 cwd、命令、退出码、耗时 |
| **配置文件** | 所有环境相关参数集中在 `config/wrapper.yaml`，修改后无需改脚本 |
| **一键安装** | `install.ps1` 自动检测 WSL、Flutter（含 FVM 支持）、生成配置、创建 dart-sdk Junction、配置 WSL 路径符号链接、跑 smoke test。支持 `-Auto` 无交互模式 |
| **诊断工具** | `fw doctor` 一键检查 13 大类（WSL、Flutter/Dart SDK、路径映射、daemon 翻译、Dart 分析层、Android SDK、Gradle、项目 `.vfox.toml`/`.fvmrc` 配置等），支持 `--quick`、`--json`、`--fix-safe` |
| **自动修复** | `fw repair <模块>` 7 个修复模块：`package-config`、`dart-sdk`、`symlinks`、`config`、`vfox`、`daemon`、`cache`。全部幂等安全 |
| **Provider 对接** | `fw provider` 检测 vfox / FVM 状态；`fw flutter current` / `fw flutter use` 代理版本管理，不替代而是打通已有工具 |
| **统一 CLI** | `fw` 命令统一入口：`fw doctor`、`fw repair`、`fw provider`、`fw status`、`fw setup`、`fw version` |

## 目录结构

```
FlutterWrapper/
├── bin/
│   ├── flutter.bat              # AS 入口（一行委托给 flutter.ps1）
│   ├── flutter.ps1              # 参数转换 + 日志 + 转发
│   ├── dart.bat                 # Dart 入口
│   ├── dart.ps1                 # Dart 版本的 flutter.ps1
│   ├── wrapper.ps1              # daemon 模式 TCP 翻译器
│   ├── doctor.bat               # 诊断工具入口
│   ├── doctor.ps1               # 13 大类系统诊断
│   ├── fw.bat                   # v3 统一 CLI 入口
│   ├── fw.ps1                   # CLI 路由器 + Repair 引擎 + Provider 适配
│   └── cache/
│       ├── dart-sdk             # Junction → Windows 侧 dart-sdk（供 AS Dart 插件分析）
│       └── flutter.version.json # flutter --version --machine 快照
├── config/
│   └── wrapper.yaml             # 配置文件（distro、Flutter 路径、UNC 前缀等）
├── packages/
│   └── flutter/
│       └── pubspec.yaml         # 占位 pubspec（满足 isFlutterSdkHome 检查）
├── logs/
│   ├── flutter.log              # 普通 Flutter 命令日志
│   ├── dart.log                 # Dart 命令日志
│   └── bridge.log               # daemon 翻译器日志
├── tools/
│   ├── run-all-tests.ps1        # 完整测试矩阵（23 项）
│   ├── daemon-test.ps1          # daemon.connected + daemon.version 测试
│   ├── daemon-platforms-test.ps1# 路径翻译测试
│   ├── daemon-tcp-win-test.ps1  # WSL TCP daemon 连通性测试
│   ├── daemon-direct-test.ps1   # 直接字节流测试
│   └── path-convert-test.ps1    # 路径转换单元测试（40 个用例）
├── docs/                        # 调研文档
│   ├── architecture.md
│   ├── sdk-layout.md
│   ├── flutter-plugin.md
│   ├── daemon.md
│   ├── path-convert.md
│   ├── plan.md
│   └── risks.md
└── install.ps1                  # 一键安装脚本
```

## 安装

### 前置要求

- Windows 10/11 + WSL2（已安装 Ubuntu 或其他发行版）
- WSL 内已安装 Flutter SDK（推荐用 [vfox](https://github.com/version-fox/vfox) 管理）
- Android Studio + Flutter 插件

### 一键安装

在项目根目录执行：

```powershell
# 交互式安装（会提示确认）
powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1

# 无交互模式（CI/CD 友好，自动检测 Flutter/Dart/JDK/FVM）
powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1 -Auto

# 跳过冒烟测试 + 指定发行版
powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1 -Auto -SkipSmoke -Distro Ubuntu-24.04
```

安装脚本会自动：

1. 检查 `wsl.exe` 和 `powershell.exe`
2. 列出可用 WSL 发行版（自动选 `Ubuntu-24.04`，否则第一个；`-Distro` 参数覆盖）
3. 在 WSL 中检测 Flutter 路径（`command -v flutter` → `~/.vfox/sdks/flutter/...` → FVM `~/fvm/`/`~/.fvm/versions/` → 交互询问或 -Auto 报错退出）
4. 验证 `flutter --version` 能跑
5. 推导 dart + JDK + Chrome 路径
6. 检测 UNC 前缀（`\\wsl.localhost\<distro>`）和盘符挂载点（`/mnt`）
7. **映射网络驱动器**（W: → `\\wsl.localhost\<distro>`，绕过 CMD 不支持 UNC cwd 的限制）
8. **配置 WSL 路径符号链接**（需 sudo）：建 `/w:` 与 `/W:` → 根目录的符号链接
9. 生成 `config/wrapper.yaml`（含 `mappedDrive: W`）
10. 创建 `bin/cache/dart-sdk` Junction + `flutter.version.json`
11. 创建 Android SDK build-tools Linux shell 包装器
12. 禁用 Linux 桌面平台（WSL 无显示服务器）
13. 跑 smoke test：`flutter --version`（可 `-SkipSmoke` 跳过）
14. **-Auto 模式下自动运行 `flutter-wrapper doctor -quick` 做安装验证**

### ⚠️ 必须用映射盘符打开 WSL 项目

**Windows CMD.EXE 不支持 UNC 路径作为当前目录**。如果 Android Studio 用 UNC 路径（如 `\\wsl.localhost\Ubuntu-24.04\home\user\project`）打开项目，CMD 会静默回退到 `C:\Windows`，导致 flutter 在错误目录下运行，报错 `No pubspec.yaml file found`。

`install.ps1` 会自动映射 `W:` → `\\wsl.localhost\<distro>`。**在 Android Studio 中打开 WSL 项目时，必须用映射盘符路径**：

```
✅ 正确：W:\home\berial\workspace\my_project
❌ 错误：\\wsl.localhost\Ubuntu-24.04\home\berial\workspace\my_project
```

映射是非持久化的（重启后失效）。如需持久化，手动执行：

```powershell
net use W: \\wsl.localhost\Ubuntu-24.04 /persistent:yes
```

或重启后重跑 `install.ps1`。

### 在 Android Studio 中配置

安装完成后，按提示在 Android Studio 设置：

1. **Settings → Languages & Frameworks → Flutter**
   - Flutter SDK path: `D:\Android\FlutterWrapper`
2. **Settings → Languages & Frameworks → Dart**
   - Dart SDK path: `D:\Android\FlutterWrapper\bin\cache\dart-sdk`
3. **打开项目时用映射盘符路径**（如 `W:\home\user\project`，不要用 UNC）
4. 重启 Android Studio

## 使用

安装完成后，所有 Android Studio 发起的 Flutter 操作（pub get、run、hot reload、debug、daemon）都会自动走 WSL。

也可以在终端直接调用：

```powershell
# === fw 统一 CLI (v3) ===
fw doctor                 # 完整诊断（13 大类 + 项目配置检测）
fw doctor --fix-safe      # 诊断 + 自动修复安全项
fw repair dart-sdk        # 修复特定模块
fw repair --list          # 列出所有修复模块
fw provider               # 查看 SDK 管理器 (vfox/FVM)
fw flutter current        # 当前 Flutter 版本
fw flutter use 3.44.6     # 切换版本 (路由到 vfox)
fw status                 # 快速状态摘要

# === Flutter / Dart 命令 ===
D:\Android\FlutterWrapper\bin\flutter.bat --version
D:\Android\FlutterWrapper\bin\flutter.bat pub get
D:\Android\FlutterWrapper\bin\dart.bat analyze
```

命令的实际执行位置是 WSL 内的 Flutter，所有输出（包括中文、emoji）都是 UTF-8。

## 配置

`config/wrapper.yaml` 示例：

```yaml
version: 1

wsl:
  distro: Ubuntu-24.04

flutter:
  # 用 vfox 的版本无关符号链接，切版本时无需改配置
  executable: /home/berial/.vfox/sdks/flutter/bin/flutter

dart:
  executable: /home/berial/.vfox/sdks/flutter/bin/dart

workspace:
  uncPrefix: \\wsl.localhost\Ubuntu-24.04
  driveMount: /mnt
  mappedDrive: W  # net use W: -> \\wsl.localhost\<distro> (绕过 CMD UNC cwd 限制)
```

修改配置后无需改任何脚本。如更换 WSL 发行版或 Flutter 路径变化，重跑 `install.ps1` 即可。

## 测试

### 完整测试矩阵

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\run-all-tests.ps1
```

覆盖 23 项测试：

| 类别 | 测试数 | 说明 |
|------|--------|------|
| SDK 结构检测 | 9 | 检查 `bin/*.bat`、`bin/cache/dart-sdk` Junction、`flutter.version.json` 等 |
| 路径转换 | 1 | 40 个 Windows ↔ WSL 路径转换用例 |
| 命令转发 | 4 | `flutter --version`、`--version --machine`、`devices`、`dart --version` |
| Daemon 模式 | 2 | `daemon.connected` + `daemon.version`、路径翻译 |
| Pub Get | 1 | 在测试项目中执行 `flutter pub get` |
| 手动测试 | 6 | Run/Hot Reload/Debug/Build/Test（需设备，自动 SKIP） |

预期输出：`17 PASS / 0 FAIL / 6 SKIP`。

### 单独运行测试

```powershell
# daemon 核心测试
powershell -NoProfile -ExecutionPolicy Bypass -File tools\daemon-test.ps1

# daemon 路径翻译测试
powershell -NoProfile -ExecutionPolicy Bypass -File tools\daemon-platforms-test.ps1

# 路径转换单元测试
powershell -NoProfile -ExecutionPolicy Bypass -File tools\path-convert-test.ps1
```

## 架构要点

### 普通命令（flutter / dart）

`flutter.bat` → `flutter.ps1`：
1. 读 `config/wrapper.yaml`
2. 转换 cwd（`D:\foo` → `/mnt/d/foo`）
3. 扫描参数，转换路径类参数（`--project-dir=D:\bar` → `--project-dir=/mnt/d/bar`）
4. `wsl.exe -d <distro> --cd <wsl-cwd> -e <flutter-exe> <args>`
5. 继承 stdin/stdout/stderr（UTF-8 安全，无 PS 字符串管道污染）
6. 返回 wsl.exe 的退出码

### daemon 命令（`flutter daemon`）

走单独的 [bin/wrapper.ps1](bin/wrapper.ps1)（TCP 文本模式翻译器）：

```
AS stdin  → [Console]::In     ─┐
                                ├─ Runspace 1: Translate-Frame('in')  → TCP 9876 ─┐
                                │                                                  ▼
                                                                                 WSL flutter daemon
                                │                                                  ▲
                                ├─ Runspace 2: Translate-Frame('out') ← TCP 9876 ─┘
AS stdout ← [Console]::Out    ─┘
```

**关键设计**：
- wsl.exe 启动用 `RedirectStandardInput=true`（关闭，防止继承 wrapper stdin）+ `RedirectStandardOutput=false`（继承 console，避免 TTY 检测问题）
- TCP stream 用 `StreamReader/Writer`（UTF-8、LF）
- 主线程检测 TCP EOF 后主动 kill wsl.exe
- 用 `[System.Environment]::Exit()` 强制退出进程（绕过 PowerShell `exit` 等待 Runspace 的陷阱）

更多细节见 [docs/daemon.md](docs/daemon.md) §9。

## 路径翻译规则

| Windows 路径 | WSL 路径 |
|--------------|----------|
| `D:\Android\demo` | `/mnt/d/Android/demo` |
| `D:/Android/demo` | `/mnt/d/Android/demo` |
| `\\wsl.localhost\Ubuntu-24.04\home\berial\demo` | `/home/berial/demo` |
| `\\wsl$\Ubuntu-24.04\home\berial\demo` | `/home/berial/demo` |
| `lib/main.dart`（相对路径） | `lib/main.dart`（不变） |

反向（WSL → Windows）：

| WSL 路径 | Windows 路径 |
|----------|--------------|
| `/mnt/d/Android/demo` | `D:\Android\demo` |
| `/home/berial/demo` | `\\wsl.localhost\Ubuntu-24.04\home\berial\demo` |
| `lib/main.dart`（相对路径） | `lib/main.dart`（不变） |

## 日志

命令按类型记录到三个独立日志文件：

| 日志文件 | 来源 | 内容 |
|---------|------|------|
| `logs/flutter.log` | `flutter.ps1` | 普通 Flutter 命令（doctor / pub / run / build） |
| `logs/dart.log` | `dart.ps1` | Dart 命令（analyze / format / test） |
| `logs/bridge.log` | `wrapper.ps1` | daemon 翻译器事件（帧翻译 / TCP 连接 / 进程生命周期） |

日志格式：
```
[2026-07-21 11:40:15] exit=0 683.2ms cwd=D:\Android\FlutterWrapper -> /mnt/d/Android/FlutterWrapper cmd=flutter --version
[2026-07-21 11:40:16] [daemon] in  projectRoot: D:\flutter_01 -> /mnt/d/flutter_01
```

## 已知限制

- **需要 Windows 侧 dart-sdk**：AS 的 Dart 分析服务器需要 Windows 原生 `dart.exe`（通过 Junction 指向 Windows 侧已安装的 Flutter 的 dart-sdk）。若 Windows 没装 Flutter，分析功能会受限，但运行/调试/热重载不受影响。
- **手动测试需设备**：`flutter run` / Hot Reload / Debug / Build 等需要连接真实设备或模拟器，无法自动化测试。
- **daemon 端口固定 9876**：多开 AS 实例会冲突（后续可改为动态端口）。
- **PS 5.1 限制**：本项目针对 Windows PowerShell 5.1（AS 调用 `flutter.bat` 时的默认 shell）。PS 7+ 未测试。
- **Web 设备（Edge/Chrome）不在 WSL 运行列表**：Flutter 只在 Windows/macOS 注册 Edge 设备；WSL 内无 `chrome (web)` 除非装 Linux Chromium。可用 `flutter run -d web-server` + 手动 Windows Edge 绕过。详见 Known Issues #2。

## Known Issues

### Issue #1: Analysis Server 无法索引 WSL 项目（import 全红）

**Title**: Analysis Server cannot index WSL project opened via mapped drive or UNC.

**Symptom**: Android Studio 中所有 `import 'package:xxx/...'` 报红 `Target of URI doesn't exist`，但 `flutter run` / `flutter build` / `flutter daemon` 全部正常工作。

**Root cause** (已确认，2026-07-20 修订):

analyzer 的 `_PhysicalResource.exists`（[`pkg/analyzer/lib/file_system/physical_file_system.dart`](https://github.com/dart-lang/sdk/blob/main/pkg/analyzer/lib/file_system/physical_file_system.dart)）在 3.11.5 stable 缺少 try-catch，导致 `dart:io` 的 `_Directory.existsSync()` 在某些 Windows UNC 路径上抛 `FileSystemException` (errno 161 = `ERROR_INVALID_PATH`) 时直接传播，破坏 Analysis Server 索引。

```
FileSystemException: Exists failed, path = '\\\wsl.localhost\Ubuntu-24.04\home\berial\.pub-cache\hosted\pub.dev\animated_stack_widget-0.0.4\lib\fix_data' (OS Error: 指定的路径无效。, errno = 161)
#0  _Directory.existsSync (dart:io/directory_impl.dart:97)
#1  _PhysicalResource.exists (package:analyzer/file_system/physical_file_system.dart:368)
```

- 报错路径 `animated_stack_widget-0.0.4\lib\fix_data` 实际不存在（lib 下只有 `src/` 和 `animated_stack_widget.dart`）
- Windows 对这类无效 UNC 子路径抛 errno 161，而不是返回 `false`
- **main 分支已修复并回填 stable**：`_PhysicalResource.exists` 和 `_PhysicalLink.exists` 都加了 `try { ... } on FileSystemException { return false; }`
- 该修复已随 **Dart 3.12.2 stable**（及当前 stable HEAD）发布；**Dart 3.11.5 及以下**未含此修复

> ⚠️ 前期曾误判根因为 `package:path` 的 `FormatException`。已纠正：analyzer 用 `Uri.file()` 而非 `path.toUri()`，`Uri.file()` 能正确处理 `\\?\UNC\...`，**不会触发 FormatException**。`package:path` 的 `FormatException` 是独立 bug，单独提 Issue 到 `dart-lang/core`，但不是 AS import 全红的根因。

**Affected**: Android Studio / IntelliJ Dart 插件 / Dart Analysis Server（snapshot 内嵌 analyzer 副本，无法用 dependency_overrides 绕过）。

**Not FlutterWrapper's bug**: FlutterWrapper 的 run/build/daemon 全部正常，此问题超出 Wrapper 职责范围。

**Status**: ✅ **Resolved in Dart 3.12.2 stable (2026-07-20 verified)**.
- analyzer 的 try-catch 已回填 stable（**3.12.2 起**），当前 stable HEAD 也含
- 主 Issue（analyzer 缺 try-catch）：https://github.com/dart-lang/sdk/issues/63855 —— **已将标题/正文更新为「已修复」记录**（保留作根因锚点，供仍卡在 3.11.x 的用户）
- 次要 Issue（`package:path` 的 `FormatException`）：https://github.com/dart-lang/core/issues/980 —— **仍然有效**，与 analyzer 修复无关

**Workarounds**（Dart < 3.12.2 时期的临时规避，升级后不再需要）:
> 升级到 **Dart ≥ 3.12.2**（即 Flutter ≥ 3.44.6，本项目已验证）后，import 全红问题已彻底消失，以下方案无需采用。

1. **AS Remote Development + WSL** — AS 在 WSL 内运行，路径全部 Linux 化
2. **本地项目副本** — Windows 副本用于编辑/分析，WSL 副本用于编译
3. **关闭 AS Dart 分析器** — 最快但损失大
4. **等待 stable SDK 回填 main 的 try-catch** — 现已随 Dart 3.12.2 完成

**详细技术分析**: [docs/analysis-server-wsl-bug.md](docs/analysis-server-wsl-bug.md)
**Issue 草稿**: [docs/issue-dart-lang-core.md](docs/issue-dart-lang-core.md)

### Issue #2: Web 设备（Edge / Chrome）不在 WSL 运行列表

**现象**：Android Studio 的 Run/Devices 下拉里只有 `Linux (desktop)`，没有 `Chrome (web)` / `Edge (web)`；`flutter devices`（WSL 内）也只列出 Linux。

**根因**（确认，2026-07-20）：
- Flutter **只在 Windows/macOS 上注册 Edge 设备**，Linux（WSL）上根本不生成 `edge (web)` 设备类型 —— 平台硬限制，**Edge 永远不会出现在 WSL 列表**。
- WSL 内若没装 Linux Chrome，`chrome (web)` 也不会出现。
- ⚠️ **`CHROME_EXECUTABLE` 指向 Windows `msedge.exe` 不可行**：`flutter doctor` 能认出 `[✓] Chrome - develop for the web`，但 `flutter devices` 会因 msedge 从 WSL 启动不按 `--version` 静默退出（拉起完整 GUI 进程）而**卡死超时（>4.5 分钟）**。wrapper 当前仍向 WSL 注入该变量，仅对 `doctor` 有效，**不能用于设备发现**。

**可行的 web 开发路径**（WSL 侧运行 Flutter）：
1. **`web-server` + 手动 Windows Edge（推荐，零安装）**：`flutter run -d web-server`（或在 AS 自定义 Run Configuration 加 `-d web-server`），日志打印 `http://localhost:PORT`，在 **Windows Edge** 打开即可，热重载正常。依赖 WSL2 localhost 转发（Windows 默认开启）。注意 3.44.6 下 `flutter devices` 默认不列 `web-server`，需从终端/自定义配置启动。
2. **装 Linux Chromium（原生 web 设备下拉）**：WSL 内 `sudo apt install chromium-browser`，重启 AS 后下拉出现 `chrome (web)`（标签为 Chrome 而非 Edge，同内核），窗口经 WSLg 显示在 Windows 上。

**Status**: 平台限制，非 FlutterWrapper 缺陷。不计划伪造 edge 设备。

## 故障排查

### 首选：运行诊断工具

```powershell
fw doctor                 # 完整诊断，13 大类
fw doctor --fix-safe      # 诊断 + 自动修复安全项（Junction、符号链接等）
```

会检查 WSL 连通性、Flutter/Dart SDK、路径映射、daemon 翻译、Dart 分析层、Android SDK、Gradle、项目 `.vfox.toml`/`.fvmrc` 配置等，失败项附带修复建议。

### 常见修复

```powershell
fw repair dart-sdk        # 重建 bin/cache/dart-sdk Junction
fw repair symlinks        # 重建 WSL 符号链接
fw repair package-config  # 修复 package_config.json 路径
fw repair daemon          # 清理残留 daemon 进程
fw repair cache           # 清理构建缓存
fw repair --list          # 查看全部修复模块
```

### `flutter --version` 卡住或无输出

- 检查 `config/wrapper.yaml` 的 `wsl.distro` 和 `flutter.executable` 是否正确
- 在 WSL 内手动跑 `<flutter-executable> --version` 验证
- 查看 `logs/flutter.log`

### `No pubspec.yaml file found`（从 Android Studio 启动时）

**根因**：Android Studio 用 UNC 路径（`\\wsl.localhost\...`）作为 cwd 调用 `flutter.bat`，Windows CMD.EXE 不支持 UNC cwd，静默回退到 `C:\Windows`，导致 flutter 在错误目录运行。

**解决**：
1. 确认 `install.ps1` 已运行（会自动 `net use W: \\wsl.localhost\<distro>`）
2. 在 Android Studio 里**关闭当前项目**
3. 用映射盘符路径重新打开：`File → Open → W:\home\<user>\<project>`
4. **不要用** `\\wsl.localhost\...` 路径打开

验证方法：在 cmd 里执行 `net use W:`，应显示 `\\wsl.localhost\Ubuntu-24.04`。

### daemon 模式无响应

- `taskkill /F /IM wsl.exe /T` 清理残留进程
- 重跑 `tools\daemon-test.ps1` 验证
- 确认端口 9876 没被占用：`netstat -ano | findstr :9876`

### Android Studio 报 "Flutter SDK not found"

- 确认 `bin\cache\dart-sdk` Junction 存在且指向有效目录
- 确认 `bin\cache\flutter.version.json` 存在
- 重跑 `install.ps1` 修复

### 路径翻译错误

- 跑 `tools\path-convert-test.ps1` 验证规则
- 查看 `logs/flutter.log`（如为 daemon 问题则看 `logs/bridge.log`）中的翻译记录

## 技术文档

- [docs/new_target_v3.md](docs/new_target_v3.md) - **v3 架构：Compatibility Orchestration Layer**
- [docs/new_target_v2.md](docs/new_target_v2.md) - v2 架构规范（已全部实现）
- [docs/architecture.md](docs/architecture.md) - 整体架构
- [docs/sdk-layout.md](docs/sdk-layout.md) - SDK 目录结构模拟
- [docs/flutter-plugin.md](docs/flutter-plugin.md) - AS Flutter 插件调用方式
- [docs/daemon.md](docs/daemon.md) - daemon 协议与 TCP 翻译实现
- [docs/path-convert.md](docs/path-convert.md) - 路径转换规则
- [docs/risks.md](docs/risks.md) - 风险与限制
- [docs/plan.md](docs/plan.md) - 项目阶段规划

## License

私有项目，未发布。

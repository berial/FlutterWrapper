# 架构设计

> 定位：一个**可长期维护的兼容层（Compatibility Layer）**，让 Android Studio 认为它使用的是正常的 Windows Flutter SDK，而所有 Flutter/Dart 命令实际在 WSL 中执行。

## 1. 核心矛盾

Android Studio 的 Flutter 插件 + JetBrains Dart 插件运行在 **Windows 侧**，期望一个**本地 Windows SDK**：
- 通过 `bin/flutter.bat` 直接 spawn 子进程
- 通过 `bin/cache/dart-sdk/bin/dart.exe` 启动分析服务器
- 通过文件系统读取 `version` / `flutter.version.json` 校验 SDK

而开发者真实的 Flutter 工具链在 **WSL 侧**（Linux 环境），项目源码也可能在 WSL 文件系统里。直接把 WSL 的 Flutter 路径配给 Android Studio 行不通——Windows 无法以原生方式执行 Linux ELF，且路径体系不兼容。

## 2. 关键架构发现（来自 Phase 0 调研）

调研揭示了一个**双 SDK 现实**，决定了架构必须是"混合式"而非"全转发式"：

| 组件 | 运行位置 | 原因 |
|---|---|---|
| `flutter` 命令（doctor / pub / run / daemon / build / test） | **WSL** | 需要 Linux 工具链、Linux 文件系统访问、Linux 设备栈 |
| Dart 分析服务器（代码补全/索引/错误检查） | **Windows** | JetBrains Dart 插件**直接 spawn** `bin/cache/dart-sdk/bin/dart.exe`，不走 daemon、不走 wrapper |
| SDK 校验文件（`bin/flutter` / `pubspec.yaml` / `flutter.version.json`） | **Windows** | 插件用 `java.io.File` 直接读 |

> 详见 [flutter-plugin.md](flutter-plugin.md) 第 5 节：Dart 分析服务器机制。

这意味着 `bin/cache/dart-sdk/` **不能是 wrapper**，必须是一个**真实可运行的 Windows Dart SDK**。否则 JetBrains Dart 插件起不来分析服务器，代码补全和分析全失效。

## 3. 整体调用链

### 3.1 普通命令（doctor / pub / build / test 等）

```
Android Studio Flutter Plugin
  │
  │  spawn <sdk>/bin/flutter.bat <args>     (Windows 进程)
  ▼
flutter.bat  ──┐
              │  仅作入口，立即转交给 PowerShell
              ▼
flutter.ps1  ──┐
              │  读 config/wrapper.yaml
              │  转换 cwd（Windows → WSL）
              │  转换参数中的路径
              │  写日志
              ▼
wrapper.ps1  ──┐
              │  构造 wsl.exe 命令行
              │  wsl.exe -d Ubuntu-24.04 -e flutter <args>
              ▼
wsl.exe  ──────────────────────────────────►  WSL 内 flutter
  │                                              │
  │  透传 stdin / stdout / stderr                │
  │  返回 exit code                              │
  ▼                                              ▼
Android Studio 拿到输出
```

### 3.2 daemon 命令（设备发现 / hot reload / 调试运行）

daemon 是**长进程 + JSON-RPC 流**，wrapper 必须做**双向路径翻译**：

```
Android Studio DaemonApi
  │
  │  写 stdin:  [{"id":"1","method":"daemon.getSupportedPlatforms","params":{"projectRoot":"D:\\demo"}}]
  ▼
flutter.bat → flutter.ps1 → wrapper.ps1
  │
  │  ⚠️ 不能用 PowerShell 字符串管道（会破坏二进制/UTF-8）
  │  必须用 .NET 原始字节流：Console.OpenStandardInput/BaseStream
  │  按帧解析 [{...}]\n + _binaryLength 二进制段
  │  翻译 params.projectRoot: D:\demo → /mnt/d/demo
  │  重写帧: [{"id":"1","method":"daemon.getSupportedPlatforms","params":{"projectRoot":"/mnt/d/demo"}}]\n
  ▼
wsl.exe flutter daemon
  │
  │  返回事件流（持续）:
  │  [{"event":"app.start","params":{"directory":"/mnt/d/demo",...}}]\n
  ▼
wrapper.ps1
  │  按帧解析 stdout
  │  翻译 params.directory: /mnt/d/demo → D:\demo
  │  重写帧转发给 Android Studio
  ▼
Android Studio 收到 Windows 路径
```

> daemon 协议细节见 [daemon.md](daemon.md)。

### 3.3 Dart 分析服务器（不走 wrapper！）

```
JetBrains Dart Plugin (Windows 进程)
  │
  │  读 Dart SDK 路径 = <flutterSdk>/bin/cache/dart-sdk
  │  spawn bin/cache/dart-sdk/bin/dart.exe language_server --protocol=lsp
  ▼
dart.exe (原生 Windows 程序，真实 Dart SDK)
  │
  │  分析项目代码、提供补全/索引
  │  读取 .dart_tool/package_config.json
  ▼
⚠️ 风险点：package_config.json 由 WSL 侧 flutter pub get 生成，
   其中的包路径是 WSL 路径（如 /home/berial/.pub-cache/...），
   Windows dart.exe 无法直接访问。
```

> 这是本项目最大的风险点，见 [risks.md](risks.md)。

### 3.4 SDK 校验（启动时一次）

```
Android Studio 启动 / SDK 设置变更
  │
  │  FlutterSdkUtil.isFlutterSdkHome("D:\Android\FlutterWrapper")
  │    检查 packages/flutter/pubspec.yaml 是文件  ✓
  │    检查 bin/flutter 是文件（注意：不带 .bat！） ✓
  │    检查 bin/cache/dart-sdk/lib 是目录          ✓
  ▼
FlutterSdkVersion.readFromSdk
  │  读 bin/cache/flutter.version.json → frameworkVersion
  ▼
识别成功，版本号显示在 UI
```

## 4. 目录结构

```
D:\Android\FlutterWrapper\
│
├── bin\
│   ├── flutter                              [占位文件，仅为通过 isFlutterSdkHome 校验]
│   ├── flutter.bat                          [入口，转 flutter.ps1]
│   ├── dart.bat                             [可选，Plugin 不直接调用根 dart]
│   ├── flutter.ps1                          [参数处理 + 日志]
│   ├── dart.ps1                             [dart 命令处理]
│   ├── wrapper.ps1                          [WSL 调用 + 路径转换 + daemon 翻译]
│   └── cache\
│       ├── dart-sdk\                        [⚠️ 真实 Windows Dart SDK，非 wrapper]
│       │   ├── bin\dart.exe
│       │   └── lib\core\core.dart ...
│       └── flutter.version.json             [伪造版本 JSON]
│
├── packages\
│   └── flutter\
│       └── pubspec.yaml                     [占位：name: flutter]
│
├── config\
│   └── wrapper.yaml                         [WSL 发行版 / Flutter 路径 / UNC 前缀配置]
│
├── logs\
│   └── wrapper.log                          [调用日志]
│
├── cache\                                   [预留，flutter 工具运行时用]
├── tools\                                   [预留，辅助脚本]
└── docs\                                    [本文档所在]
```

> 详见 [sdk-layout.md](sdk-layout.md)。

## 5. 配置驱动

所有环境相关参数集中在 `config/wrapper.yaml`，脚本不硬编码路径：

```yaml
version: 1

wsl:
  distro: Ubuntu-24.04

flutter:
  # vfox 的版本无关符号链接（切换版本时自动更新指向）
  executable: /home/berial/.vfox/sdks/flutter/bin/flutter
  # 注意：vfox 激活只在 .zshrc 里（eval "$(vfox activate zsh)"），
  # bash 非 zsh 交互模式下 flutter 不在 PATH，所以必须用绝对路径。

dart:
  executable: /home/berial/.vfox/sdks/flutter/bin/dart

workspace:
  uncPrefix: \\wsl.localhost\Ubuntu-24.04 # 用于 WSL→Windows 路径翻译
  driveMount: /mnt                        # WSL 挂载 Windows 盘符的根
```

> ✅ WSL 内已通过 vfox 安装 Flutter 3.41.9（stable）/ Dart 3.11.5，路径 `~/.vfox/sdks/flutter/bin/flutter`（符号链接，跟随 vfox 当前版本）。详见 [risks.md](risks.md) R1。

## 6. 技术路线选择

| 方案 | 优点 | 缺点 | 结论 |
|---|---|---|---|
| 纯 Batch | 兼容性最好 | 路径处理/JSON 解析极难写 | ❌ 仅作入口 |
| PowerShell（ps1） | 开发快、调试方便、可调 .NET | 二进制流处理需小心 | ✅ **当前阶段采用** |
| C#/.NET 单文件 exe | 二进制安全、性能好、daemon 翻译可靠 | 开发慢、编译复杂 | 🔜 后期若 PS 不足以承载 daemon 翻译再迁移 |

**分阶段策略**：
1. **Phase 4-6**：用 PowerShell 实现普通命令转发 + SDK 模拟，先跑通 `flutter --version` / `doctor` / `pub get`
2. **Phase 6 daemon**：先用 PS 的 .NET `Stream` 尝试 daemon 字节流翻译；若二进制/性能有问题，**只把 daemon 翻译核心迁移到 C#**，其余仍走 PS
3. **后期**：若整体稳定性需要，再考虑全量迁移到 C#/.NET

## 7. 不做的事（范围边界）

- ❌ 不在 WSL 里安装 Flutter（那是用户的前置工作，wrapper 只负责调用）
- ❌ 不替换 JetBrains Dart 插件的分析服务器（用真实 Windows Dart SDK）
- ❌ 不翻译 Dart 分析服务器的协议（它走 LSP/自有协议，路径问题通过 `package_config.json` 层面解决）
- ❌ 不支持多发行版切换（v1 只锁定配置里的一个 distro）
- ❌ 不做 Flutter SDK 升级/版本管理（交给 WSL 侧的 version-fox 或手动）

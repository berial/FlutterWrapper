# SDK 目录结构模拟方案

> 目标：在 `D:\Android\FlutterWrapper` 伪造一个最小但合法的 Windows Flutter SDK，让 Android Studio Flutter 插件识别并正常工作。

## 1. 插件校验逻辑（来自源码核实）

`flutter-intellij` 的 `FlutterSdkUtil.isFlutterSdkHome`（`src/io/flutter/sdk/FlutterSdkUtil.java:174-179`）是核心校验，**只检查 3 个路径**：

```java
public static boolean isFlutterSdkHome(@NotNull final String path) {
    final File flutterPubspecFile = new File(path + "/packages/flutter/pubspec.yaml");
    final File flutterToolFile    = new File(path + "/bin/flutter");
    final File dartLibFolder      = new File(path + "/bin/cache/dart-sdk/lib");
    return flutterPubspecFile.isFile()
        && flutterToolFile.isFile()       // ⚠️ 注意：是 bin/flutter，不是 bin/flutter.bat！
        && dartLibFolder.isDirectory();
}
```

`getErrorMessageIfWrongSdkRootPath` 的分级错误：
- 路径不是目录 → "folder not exists"
- 前 2 个文件存在但 `dart-sdk/lib` 缺失 → "Flutter SDK without Dart SDK"（专门错误）
- 上述任一不满足 → "SDK not found"

## 2. 最小可识别目录树

```
D:\Android\FlutterWrapper\
│
├── bin\
│   ├── flutter                              [占位文件，仅需存在]
│   ├── flutter.bat                          [wrapper 入口，转发 WSL]
│   └── cache\
│       ├── dart-sdk\                        [⚠️ 真实 Windows Dart SDK]
│       │   ├── bin\
│       │   │   └── dart.exe                 [JetBrains Dart 插件用]
│       │   └── lib\
│       │       └── core\
│       │           └── core.dart            [Dart 标准库]
│       └── flutter.version.json             [伪造版本 JSON]
│
└── packages\
    └── flutter\
        └── pubspec.yaml                     [内容：name: flutter]
```

## 3. 各文件/目录说明

### 3.1 必需（缺一不可，否则校验失败）

| 路径 | 类型 | 作用 | 内容要求 |
|---|---|---|---|
| `bin/flutter` | 文件 | `isFlutterSdkHome` 校验硬条件 | **空文件即可**，只要 `isFile()==true`。⚠️ Windows 下也必须有这个不带 `.bat` 的文件 |
| `bin/flutter.bat` | 文件 | 所有 flutter 命令的实际执行入口 | **必须是可工作的 wrapper**，转发到 WSL |
| `packages/flutter/pubspec.yaml` | 文件 | `isFlutterSdkHome` 校验 | 最小内容：`name: flutter` |
| `bin/cache/dart-sdk/lib` | 目录 | `isFlutterSdkHome` 校验 + JetBrains Dart 插件使用 | **必须放真实 Windows Dart SDK**，不能是空目录或 wrapper |
| `bin/cache/flutter.version.json` | 文件 | 版本号读取（主路径） | JSON，含 `frameworkVersion` 字段，值 `>= 3.19.4` |

### 3.2 不需要（插件不读，可省略）

| 路径 | 原因 |
|---|---|
| `bin/dart.bat` | Flutter 插件从不直接调根目录 dart（dart 命令走 `bin/cache/dart-sdk/bin/dart`） |
| `bin/internal/engine.version` | 插件不读，是 flutter 工具内部用的 |
| `bin/cache/artifacts/engine/` | 插件不直接校验，仅在 build/run 时由 flutter 工具自己用（在 WSL 侧） |
| `version`（根目录） | 有 `flutter.version.json` 即可，旧版 fallback 文件可省 |
| `bin/cache/flutter_tools.stamp` | 仅用于判断 SDK 是否过期，缺失只让 `isOlderThanToolsStamp` 返回 false |
| `packages/flutter/lib/` | 插件校验的是 `pubspec.yaml`，不是 lib 目录 |

## 4. `flutter.version.json` 内容

插件只读 `frameworkVersion` 字段，其他字段可伪造。版本需 `>= 3.19.4`（`MIN_SDK_SUPPORTED`）。

**建议直接用 WSL 侧真实 Flutter 的版本**，避免伪造版本与实际能力不符。当前 WSL 侧实测 `flutter --version --machine` 输出：

```json
{
  "frameworkVersion": "3.41.9",
  "channel": "stable",
  "repositoryUrl": "https://github.com/flutter/flutter.git",
  "frameworkRevision": "00b0c91f06209d9e4a41f71b7a512d6eb3b9c694",
  "frameworkCommitDate": "2026-04-29 10:03:19 -0700",
  "engineRevision": "42d3d75a56efe1a2e9902f52dc8006099c45d937",
  "engineCommitDate": "2026-04-28 17:31:55.000Z",
  "engineContentHash": "9161402dc0e134b3fb5adee5046b6e84b1a5e1c1",
  "dartSdkVersion": "3.11.5",
  "devToolsVersion": "2.54.2",
  "flutterVersion": "3.41.9",
  "flutterRoot": "/home/berial/.vfox/cache/flutter/v-3.41.9/flutter-3.41.9"
}
```

> 3.41.9 > 3.38.0-0.0.pre，**解锁全部功能开关**（含 Widget 预览）。

### 版本阈值与功能开关（`FlutterSdkVersion`）

| 版本常量 | 阈值 | 解锁功能 |
|---|---|---|
| `MIN_SDK_SUPPORTED` | 3.19.4 | 最低支持，低于则拒绝 |
| `MIN_SDK_WITHOUT_SUNSET_WARNING` | 3.22.2 | 低于此会警告即将废弃 |
| `MIN_SUPPORTS_TOOL_EVENT_STREAM` | 3.7.1 | tool event stream |
| `MIN_SUPPORTS_DEEP_LINKS_TOOL` | 3.19.0 | deep links 工具 |
| `MIN_SUPPORTS_DEVTOOLS_MULTI_EMBED` | 3.23.0-0.1.pre | DevTools 多实例 |
| `MIN_SUPPORTS_DTD` | 3.22.0 | Dart Tooling Daemon |
| `MIN_SUPPORTS_PROPERTY_EDITOR` | 3.32.0-0.1.pre | 属性编辑器 |
| `MIN_SUPPORTS_WIDGET_PREVIEW` | 3.38.0-0.0.pre | Widget 预览 |

**建议**：伪造 `3.32.0`（解锁除 Widget 预览外全部），或 `3.38.0`（全解锁）。但要注意伪造版本不应远超 WSL 侧真实 Flutter 版本，否则功能开关与实际能力不符。

## 5. Dart SDK 的特殊处理（关键）

### 5.1 为什么必须是真实 Windows Dart SDK

JetBrains Dart 插件（`com.jetbrains.lang.dart`）会：
1. 读 Flutter 插件设置的 Dart SDK 路径 = `<flutterSdk>/bin/cache/dart-sdk`
2. 直接 spawn `bin/dart.exe language_server --protocol=lsp`（或类似）
3. 通过自有 JSON-RPC 协议通信（不是 LSP，是 `org.dartlang.analysis.server.protocol`）

**这是 Windows 原生进程，不走 wrapper、不走 WSL。** 所以 `bin/cache/dart-sdk/` 必须包含可运行的 `dart.exe` + 完整标准库。

### 5.2 Dart SDK 来源

| 方案 | 说明 | 推荐度 |
|---|---|---|
| **Junction 到 Windows Flutter SDK 的 dart-sdk** | `mklink /J` 指向 Windows 侧 vfox/flutter 的 `bin/cache/dart-sdk`，零空间占用，vfox 升级时自动同步 | ✅ **当前采用（2026-07-17）** |
| 从独立 Dart SDK 发行包下载 Windows 版 | 与 WSL Flutter 解耦，版本可独立控制 | ✅ 备选 |
| 从一个真实 Windows Flutter SDK 拷贝 `bin/cache/dart-sdk/` | 版本与某 Windows Flutter 一致 | ✅ 可行（但占 700MB） |
| 软链接到 WSL 内的 Dart SDK | ❌ Windows 不能软链到 WSL 内部，且 dart.exe 是 Linux ELF | ❌ 不可行 |
| 用 wrapper 伪装 dart.exe | ❌ JetBrains Dart 插件对 dart.exe 的协议交互复杂，wrapper 难以承载（详见 architecture.md 第 2 节） | ❌ 不可行 |

### 5.2.1 当前 Junction 配置

```powershell
# 创建（在 PowerShell 管理员或普通会话中）
$link   = 'D:\Android\FlutterWrapper\bin\cache\dart-sdk'
$target = 'C:\Users\Berial\vfox-global\flutter\bin\cache\dart-sdk'
# 注意：必须先删除已存在的空目录
if (Test-Path $link) { Remove-Item $link -Recurse -Force }
New-Item -ItemType Junction -Path $link -Target $target
```

**验证**：
- `isFlutterSdkHome` 三条件全部 OK（`bin/flutter` / `packages/flutter/pubspec.yaml` / `bin/cache/dart-sdk/lib`）
- `& D:\Android\FlutterWrapper\bin\cache\dart-sdk\bin\dart.exe --version` → `Dart SDK version: 3.11.5 (stable) on "windows_x64"`
- 与 WSL 侧 Dart 3.11.5 版本完全一致

**Junction 维护注意**：
- 删除 junction 用 `Remove-Item` 或 `rmdir`，**不要用 `del`**（会递归删目标目录内容！）
- vfox 升级 Windows flutter 时，junction 自动指向新版本（因为 vfox 的 `current` 符号链接会更新）
- 若用户不使用 vfox Windows 版，可改为独立 Dart SDK 或拷贝方案

### 5.3 版本同步要求

Windows Dart SDK 版本应与 WSL 侧 Flutter 捆绑的 Dart SDK **大版本一致**，否则：
- 分析服务器（Windows）和运行时（WSL）语言特性不一致
- `package_config.json` 的 SDK 约束可能不匹配

当前 WSL 侧 Flutter 3.41.9 捆绑 **Dart 3.11.5**，Windows 侧应下载 Dart 3.11.5 (stable) Windows 版。

建议：安装脚本（Phase 10）从 WSL 读取 `flutter --version --machine` 的 `dartSdkVersion` 字段，下载对应 Windows Dart SDK。

## 6. `pubspec.yaml` 占位内容

```yaml
name: flutter
description: Placeholder for FlutterWrapper SDK validation.
```

插件只校验文件存在和 `isFile()`，不解析内容。但保持最小合法 YAML 以防未来版本插件加强校验。

## 7. 占位文件 `bin/flutter` 的内容

可以是空文件，或一行注释：

```
# Placeholder for isFlutterSdkHome validation. Real entry is flutter.bat.
```

⚠️ **不要**把这个文件做成可执行脚本——插件校验时只看 `isFile()`，不会执行它。真正的执行入口是 `flutter.bat`。

## 8. 校验后的运行时目录补充

校验通过后，flutter 工具运行时可能还会在 SDK 目录下创建一些缓存（在 WSL 侧，不影响 Windows 模拟目录）：
- `bin/cache/dart-sdk/` 内的 SDK 不会被修改（Windows 侧独立）
- Windows 侧 `D:\Android\FlutterWrapper` 目录应保持**只读性质**，除日志和配置外不让 wrapper 写入

## 9. 与 Phase 1 目录结构的对应

```
D:\Android\FlutterWrapper\
├── bin\                    ← 校验目录 + wrapper 脚本
├── cache\                  ← 预留（Phase 1 计划，flutter 工具在 WSL 侧用）
├── packages\               ← 校验目录
├── version\                ← ⚠️ Phase 1 计划里有，但插件不读根 version 文件，可省略
├── config\                 ← wrapper.yaml
├── logs\                   ← wrapper.log
├── tools\                  ← 预留
└── docs\                   ← 调研文档
```

⚠️ **对 Phase 1 计划的修正**：原计划根目录有 `version` 文件，但插件优先读 `bin/cache/flutter.version.json`，根 `version` 文件可省略。建议保留 `bin/cache/flutter.version.json` 作为唯一版本源。

# Android Studio Flutter Plugin 调用方式

> 调研来源：`flutter/flutter-intellij` 仓库 `main` 分支（截至 2026-07-14）。所有结论基于实际抓取的源码。

## 1. SDK 路径定位

### 1.1 关键发现：插件不读 `FLUTTER_ROOT` 环境变量

源码中没有任何地方读取 `FLUTTER_ROOT`。`FLUTTER_HOST` 环境变量是插件**写入**给 flutter 工具用于标识宿主 IDE 的，与 SDK 定位无关。

### 1.2 真实定位链路

**主路径 —— 通过 JetBrains Dart 插件反推**（`FlutterSdk.getFlutterSdk`，`FlutterSdk.java:100-114`）：

```java
final DartSdk dartSdk = DartPlugin.getDartSdk(project);
final String dartPath = dartSdk.getHomePath();
if (!dartPath.endsWith(DART_SDK_SUFFIX)) return null;  // DART_SDK_SUFFIX = "/bin/cache/dart-sdk"
final String sdkPath = dartPath.substring(0, dartPath.length() - DART_SDK_SUFFIX.length());
return FlutterSdk.forPath(sdkPath);
```

**含义**：插件把 Dart SDK 配置当成"真理之源"。Dart SDK 路径必须以 `/bin/cache/dart-sdk` 结尾，去掉后缀就是 Flutter SDK 根。

**降级路径 —— 从 Dart SDK 库反推**（`FlutterSdk.getIncomplete:121-130`）：在 project library table 找名为 `"Dart SDK"` 的 Library，检查 CLASSES URL 是否以 `/bin/cache/dart-sdk/lib/core` 结尾。

### 1.3 候选路径收集（`FlutterSdkUtil.getKnownFlutterSdkPaths:121-146`）

1. 当前所有已打开 project 的 Flutter SDK 路径
2. `PropertiesComponent` 持久化属性 `FLUTTER_SDK_KNOWN_PATHS`（用户历史输入，仅填下拉框）
3. **PATH 查找**：`locateSdkFromPath()` → `SystemUtils.which("flutter")` → 取 `parentFile.parentFile`（从 `bin/flutter` 回退两级到 SDK 根）
4. Linux snap 固定路径 `$HOME/snap/flutter/common/flutter`

### 1.4 从 `.dart_tool/package_config.json` 推断（`FlutterSdkUtil.guessFlutterSdkFromPackagesFile:227-245`）

读取 `.dart_tool/package_config.json`，找 name 为 `"flutter"` 的包，取其 `rootUri`，向上回退两级（去掉 `packages/flutter/lib/`）。

### 1.5 优先级总结

1. **Dart 插件里配的 Dart SDK 路径**（最高优先级，真理之源）
2. 用户在 Flutter 设置页手填的 Flutter SDK 路径 → `setFlutterSdkPath` → 反向设置 Dart SDK 为 `<flutterSdk>/bin/cache/dart-sdk`
3. 历史 `FLUTTER_SDK_KNOWN_PATHS`（仅下拉框填充）
4. PATH 中的 `flutter` 命令位置（仅下拉框填充）
5. `.dart_tool/package_config.json`（fallback 推断）

> **对 Wrapper 的启示**：只要让 Dart SDK 路径以 `\bin\cache\dart-sdk` 结尾，插件就能反推到 Flutter SDK 根。用户在设置页配 `D:\Android\FlutterWrapper` 后，插件会自动把 Dart SDK 设为 `D:\Android\FlutterWrapper\bin\cache\dart-sdk`。

## 2. SDK 合法性校验

### 2.1 核心校验（`FlutterSdkUtil.isFlutterSdkHome:174-179`）

```java
public static boolean isFlutterSdkHome(@NotNull final String path) {
    final File flutterPubspecFile = new File(path + "/packages/flutter/pubspec.yaml");
    final File flutterToolFile    = new File(path + "/bin/flutter");
    final File dartLibFolder      = new File(path + "/bin/cache/dart-sdk/lib");
    return flutterPubspecFile.isFile()
        && flutterToolFile.isFile()
        && dartLibFolder.isDirectory();
}
```

### 2.2 校验文件清单

| 路径（相对 SDK 根） | 校验 | 作用 | 必需 |
|---|---|---|---|
| `packages/flutter/pubspec.yaml` | `isFile()` | 标识 Flutter 仓库结构 | **必需** |
| `bin/flutter` | `isFile()` | ⚠️ **不带 `.bat`！** Windows 也校验这个 | **必需** |
| `bin/cache/dart-sdk/lib` | `isDirectory()` | 验证 Dart SDK 已下载 | **必需** |

### 2.3 错误分级（`getErrorMessageIfWrongSdkRootPath:191-200`）

- 路径不是目录 → `error.folder.specified.as.sdk.not.exists`
- 前 2 个文件存在但 `dart-sdk/lib` 缺失 → `error.flutter.sdk.without.dart.sdk`（专门错误）
- 任一不满足 → `error.sdk.not.found.in.specified.location`

### 2.4 其他被读取的文件（非校验，运行时用）

| 路径 | 用途 |
|---|---|
| `bin/cache/flutter.version.json` | 新版版本文件（JSON，读 `frameworkVersion` 字段） |
| `version`（根目录） | 旧版 fallback（纯文本，取第一个非空非 `#` 行） |
| `bin/cache/flutter_tools.stamp` | flutter_tools 编译时间戳，判断 SDK 是否过期 |
| `bin/cache/dart-sdk/lib/core` | Dart core 库，用于 Dart SDK library URL 推断 fallback |

## 3. 版本号读取

### 3.1 版本来源（`FlutterSdkVersion.readFromSdk:90-96`）

```java
public static FlutterSdkVersion readFromSdk(@NotNull VirtualFile sdkHome) {
    final VirtualFile versionFile = sdkHome.findFileByRelativePath("bin/cache/flutter.version.json");
    if (versionFile != null && versionFile.exists() && !versionFile.isDirectory()) {
        return readFromFile(versionFile);  // 新版 JSON
    }
    return readFromFile(sdkHome.findChild("version"));  // 旧版纯文本
}
```

### 3.2 文件格式

**新版 `bin/cache/flutter.version.json`**：
```json
{
  "frameworkVersion": "3.32.0",
  "channel": "stable",
  "repositoryUrl": "...",
  "frameworkRevision": "...",
  "frameworkCommitDate": "...",
  "engineRevision": "...",
  "dartSdkVersion": "..."
}
```
插件**只读 `frameworkVersion` 字段**。

**旧版 `version`**：纯文本，取第一个非空且不以 `#` 开头的行。

### 3.3 版本号字符串格式

- 标准：`3.19.4`、`3.22.2`、`3.32.0`
- 预发布：`3.23.0-0.1.pre`、`3.38.0-0.0.pre`
- 解析：先按 `-` 拆主版本和 beta 后缀，主版本按 `.` 拆
- 读不到 → "unknown version"

### 3.4 版本号用途

**A. UI 显示**（`FlutterSettingsConfigurable.onVersionChanged:331-340`）：
- 执行 `flutter --version`（**不带 `--machine`**）
- 取 stdout 第一行作显示文本
- 源码有 TODO 说要切 `--version --machine`，目前仍是纯文本

**B. 功能开关**（`FlutterSdkVersion` 各 `supportsVersion` 判断）：

| 阈值 | 解锁 |
|---|---|
| 3.19.4 | 最低支持（`MIN_SDK_SUPPORTED`） |
| 3.22.2 | 无废弃警告 |
| 3.7.1 | tool event stream |
| 3.19.0 | deep links 工具 |
| 3.23.0-0.1.pre | DevTools 多实例 |
| 3.22.0 | Dart Tooling Daemon |
| 3.32.0-0.1.pre | 属性编辑器 |
| 3.38.0-0.0.pre | Widget 预览 |

> **对 Wrapper 的启示**：伪造版本 `>= 3.19.4`，建议 `3.32.0` 或 `3.38.0`。但不应远超 WSL 真实 Flutter 版本。

## 4. 插件主动调用的命令

所有命令通过 `FlutterCommand` 构造，在 `FlutterCommand.createGeneralCommandLine:272-291` spawn：
- ExePath：`<sdkHome>/bin/flutter.bat`（Windows）
- 默认参数：`--no-color`（**`doctor` 不加 `--no-color`**）
- 环境变量：`FLUTTER_HOST`、`ANDROID_HOME`

### 4.1 命令清单

| Type | 命令 | 用途 / 解析 |
|---|---|---|
| `VERSION` | `flutter --version` | 取 stdout 第一行 UI 显示，**不带 `--machine`** |
| `DOCTOR` | `flutter doctor --verbose` | 唯一不加 `--no-color` |
| `UPGRADE` | `flutter upgrade` | 升级 |
| `CHANNEL` | `flutter channel` | 解析当前 channel |
| `CREATE` | `flutter create [args] <dir>` | 创建项目，附加 `--platforms android,ios --project-name X` |
| `CLEAN` | `flutter clean` | 清理 |
| `CONFIG` | `flutter config [args]` | 配置 SDK |
| `PUB_GET` | `flutter pub get` | 获取依赖（设 `DartPlugin.setPubActionInProgress(true)`） |
| `PUB_UPGRADE` | `flutter pub upgrade` | 升级依赖 |
| `PUB_OUTDATED` | `flutter pub outdated` | 检查过期 |
| `PUB_ADD` | `flutter pub add <name>` | 添加依赖 |
| `PUB` | `flutter pub [args]` | 通用 pub |
| `BUILD` | `flutter build [args]` | 构建 |
| `RUN` | `flutter run --machine --track-widget-creation --device-id=<id> [--start-paused] [--profile/--release] <main>` | **走 `--machine` JSON 协议** |
| `ATTACH` | `flutter attach --machine [--device-id=<id>] [--profile/--release] <main>` | attach |
| `TEST` | `flutter test --machine [--start-paused] [--plain-name X \| --name REGEX] [--coverage] <path>` | 走 `--machine` JSON 协议 |
| `WIDGET_PREVIEW` | `flutter widget-preview [args]` | Widget 预览（3.38+） |

### 4.2 daemon 命令（`DeviceDaemon.chooseCommand:125-158`）

```java
final String path = FlutterSdkUtil.pathToFlutterTool(sdk.getHomePath());  // bin/flutter.bat
final ImmutableList<String> list = ImmutableList.of("daemon");
return new Command(sdk.getHomePath(), path, list, androidHome);
```

- 命令：`<sdk>/bin/flutter.bat daemon`
- WorkDir：SDK 根
- 通信：JSON 行协议（每行一个 JSON 对象），由 `DaemonApi` + `StdoutJsonParser` 解析
- 作用：设备发现、app 启停、热重载、热重启

### 4.3 输出解析方式

- `VERSION`：stdout 第一行（纯文本）
- `RUN/ATTACH/TEST`：`--machine` 输出 JSON 事件流，由 `DaemonApi` + `StdoutJsonParser` 按行读 JSON
- `CHANNEL`：解析 stdout 文本
- `PUB_GET` 等：仅看 exit code + stderr
- **没有直接调用 `dart language_server` 或 `dart analyze`** —— 分析服务器走 Dart 插件（见第 5 节）

### 4.4 主动 spawn 的子进程汇总

1. `<flutter>/bin/flutter.bat daemon` —— 设备/app daemon
2. `<flutter>/bin/flutter.bat --version` —— 版本探测
3. `<flutter>/bin/flutter.bat doctor --verbose` —— 健康检查
4. `<flutter>/bin/flutter.bat pub get/upgrade/outdated/add` —— pub 操作
5. `<flutter>/bin/flutter.bat run --machine ...` —— 调试运行
6. `<flutter>/bin/flutter.bat attach --machine ...` —— attach
7. `<flutter>/bin/flutter.bat test --machine ...` —— 测试
8. `<flutter>/bin/flutter.bat create/build/clean/config/channel/upgrade/widget-preview` —— 其他

> **对 Wrapper 的启示**：`flutter.bat` 必须能正确处理上述所有命令，透传 stdin/stdout/stderr 和 exit code。其中 `daemon` / `run --machine` / `attach --machine` / `test --machine` 是**长进程 + JSON 流**，需要特殊处理（见 [daemon.md](daemon.md)）。

## 5. Dart 分析服务器机制

### 5.1 关键发现：Flutter 插件不 spawn 分析服务器

`FlutterDartAnalysisServer.java` 只是个 wrapper：
- 不启动任何进程
- 通过 `getAnalysisService()` 拿到 JetBrains Dart 插件的 `DartAnalysisServerService`
- 订阅 `flutter.outline` 等 Flutter 特有事件
- 发送 `analysis.setSubscriptions` 请求

### 5.2 真正的启动方

JetBrains Dart 插件（`com.jetbrains.lang.dart`）启动分析服务器，用的 SDK 路径是 Flutter 插件通过 `setFlutterSdkPath` 设置的：

```java
// FlutterSdkUtil.setFlutterSdkPath:201-211
final String dartSdk = flutterSdkPath + "/bin/cache/dart-sdk";
OpenApiUtils.safeRunWriteAction(() -> DartPlugin.ensureDartSdkConfigured(project, dartSdk));
```

Dart 插件内部会 spawn `<flutterSdk>/bin/cache/dart-sdk/bin/dart.exe language_server --protocol=lsp`（或类似）。

### 5.3 通信协议

- **不是 LSP**，是 Dart 分析服务器的自有 JSON-RPC 协议
- 使用 `org.dartlang.analysis.server.protocol` 包里的协议类
- 事件如 `flutter.outline`、`server.connected`、`computedErrors`

### 5.4 对 Wrapper 的关键启示

- **必须**让 `bin/cache/dart-sdk/` 是真实可用的 Windows Dart SDK（JetBrains Dart 插件会用它启动分析服务器）
- **不需要**让根目录的 `bin/dart.bat` 能工作（Flutter 插件从不直接调它）
- **必须**让 `bin/flutter.bat` 能正常工作（插件大量直接调用）
- Dart SDK 路径必须严格位于 `<flutterSdk>/bin/cache/dart-sdk/`

## 6. Windows 特殊处理

### 6.1 脚本名选择（`FlutterSdkUtil.flutterScriptName:156-158`）

```java
public static String flutterScriptName() {
    return SystemInfo.isWindows ? "flutter.bat" : "flutter";
}
```

### 6.2 两种"flutter 文件"的差异

| 用途 | Windows 用的文件 | 校验函数 |
|---|---|---|
| **合法性校验**（`isFlutterSdkHome`） | `bin/flutter`（**不带 .bat！**） | `new File(path + "/bin/flutter").isFile()` |
| **执行命令**（`pathToFlutterTool` + `createGeneralCommandLine`） | `bin/flutter.bat` | `findDescendant(sdkPath, "/bin/" + flutterScriptName())` |

**重要**：校验和执行用**不同**的文件名。Windows 上必须**同时**有：
- `bin/flutter`（文件，可为空占位，仅为通过校验）
- `bin/flutter.bat`（真实可执行的 wrapper）

### 6.3 路径分隔符

- 校验代码用 `/`（Java File 在 Windows 上正反斜杠都能识别）
- 执行时通过 `FileUtil.toSystemDependentName()` 转本地分隔符
- `findDescendant` 用 `LocalFileSystem.getInstance().refreshAndFindFileByPath()` —— VirtualFile 系统能处理 `/`

### 6.4 其他

- 没有 Windows 特殊硬编码路径
- 没有 registry 读取
- 没有调用 `where flutter` —— `locateSdkFromPath()` 用 `SystemUtils.which("flutter")`（跨平台 which 封装）

## 7. 涉及的核心类

| 类 | 作用 |
|---|---|
| `FlutterSdk` | SDK 模型 + 命令构造工厂 + 缓存 |
| `FlutterSdkManager` | project 级服务，**轮询**（1 秒间隔 `JobScheduler`）检测 SDK 增删，发事件 |
| `FlutterSdkUtil` | 路径定位、合法性校验、Dart SDK 配置 |
| `FlutterSdkVersion` | 版本号解析与功能开关判断 |
| `FlutterCommand` | 命令构造与 spawn |
| `DartPlugin` | JetBrains Dart 插件桥接层 |
| `FlutterDartAnalysisServer` | 分析服务订阅 wrapper |
| `FlutterSettingsConfigurable` | 设置页 UI |
| `DeviceDaemon` / `DaemonApi` | daemon 通信 |

## 8. 参考源码

- [FlutterSdk.java](https://github.com/flutter/flutter-intellij/blob/main/src/io/flutter/sdk/FlutterSdk.java)
- [FlutterSdkUtil.java](https://github.com/flutter/flutter-intellij/blob/main/src/io/flutter/sdk/FlutterSdkUtil.java)
- [FlutterSdkVersion.java](https://github.com/flutter/flutter-intellij/blob/main/src/io/flutter/sdk/FlutterSdkVersion.java)
- [FlutterSdkManager.java](https://github.com/flutter/flutter-intellij/blob/main/src/io/flutter/sdk/FlutterSdkManager.java)
- [FlutterCommand.java](https://github.com/flutter/flutter-intellij/blob/main/src/io/flutter/sdk/FlutterCommand.java)
- [DartPlugin.java](https://github.com/flutter/flutter-intellij/blob/main/src/io/flutter/dart/DartPlugin.java)
- [FlutterDartAnalysisServer.java](https://github.com/flutter/flutter-intellij/blob/main/src/io/flutter/dart/FlutterDartAnalysisServer.java)
- [DeviceDaemon.java](https://github.com/flutter/flutter-intellij/blob/main/src/io/flutter/run/daemon/DeviceDaemon.java)
- [DaemonApi.java](https://github.com/flutter/flutter-intellij/blob/main/src/io/flutter/run/daemon/DaemonApi.java)

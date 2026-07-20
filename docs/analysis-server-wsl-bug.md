# Analysis Server 在 WSL 项目上崩溃的技术分析

> **状态**：✅ 已在 Dart 3.12.2 stable 修复并验证（2026-07-20 升级 Flutter 3.44.6 / Dart 3.12.2 后 Android Studio import 全红消失）；Issue #63855 已更新为「已修复」记录
> **影响范围**：Android Studio / IntelliJ Dart 插件 / Dart Analysis Server
> **不属于**：FlutterWrapper 自身问题（FlutterWrapper 的 run/build/daemon 全部正常）

---

## 0. 修订记录

| 日期 | 修订内容 |
|------|---------|
| 2026-07-20 | 初版，根因误判为 `package:path` 的 `FormatException` |
| 2026-07-20 | **重大修订**：根因实际为 `dart:io` 的 `_Directory.existsSync` 抛 `FileSystemException` (errno 161)，analyzer 在 3.11.5 缺 try-catch；main 分支已修复。`FormatException` 是次要问题且实际不会被 analyzer 触发（analyzer 用 `Uri.file()` 而非 `path.toUri()`）。 |
| 2026-07-20 | **已修复验证**：升级到 Flutter 3.44.6 / Dart 3.12.2 后 Android Studio import 全红消失；确认修复已回填 stable（3.12.2 起，当前 stable HEAD 也含），Issue #63855 标题/正文改为「已修复」记录。另确认 `package_config.json` 实际用 W: 映射盘符格式（非 UNC），依赖 `/w:`、`/W:` 符号链接。 |

---

## 1. 现象

在 Windows 上让 Android Studio 打开位于 WSL 内的 Flutter/Dart 项目（通过映射盘 `W:\` 或 UNC `\\wsl.localhost\...` 访问），所有 `import 'package:xxx/...'` 都报红：

```
Target of URI doesn't exist: 'package:flutter/foundation.dart'.
Try creating the file referenced by the URI, or try using a URI for file that does exist.
```

文件实际存在，`flutter run` / `flutter build` / `flutter daemon` 均正常工作。
仅 AS 的 Dart Analysis Server 报错。

---

## 2. 复现步骤

### 2.1 AS 日志中的实际异常

从 Android Studio 的 Dart Analysis Server 日志中捕获到的真实异常堆栈：

```
FileSystemException: Exists failed, path = '\\\wsl.localhost\Ubuntu-24.04\home\berial\.pub-cache\hosted\pub.dev\animated_stack_widget-0.0.4\lib\fix_data' (OS Error: 指定的路径无效。, errno = 161)
#0  _Directory.existsSync (dart:io/directory_impl.dart:97)
#1  _PhysicalResource.exists (package:analyzer/file_system/physical_file_system.dart:368)
#2  ...
```

**关键观察**：
- 异常类型是 `FileSystemException`，**不是** `FormatException`
- 异常源在 `_Directory.existsSync` (dart:io)，被 `_PhysicalResource.exists` 直接传播
- errno 161 = `ERROR_INVALID_PATH` ("指定的路径无效")
- 报错路径 `animated_stack_widget-0.0.4\lib\fix_data` 实际上**不存在**（lib 下只有 `src/` 和 `animated_stack_widget.dart`）

### 2.2 最小复现

```dart
// test_exists_sync.dart
import 'dart:io';

void main() {
  // 模拟 analyzer 调用 _PhysicalResource.exists 的行为
  final paths = [
    r'\\wsl.localhost',                                              // 无 share
    r'\\wsl.localhost\Ubuntu-24.04\home\berial',                     // 完整 UNC
    r'\\?\UNC\wsl.localhost\Ubuntu-24.04\home\berial',               // 扩展 UNC
    r'\\wsl.localhost\Ubuntu-24.04\home\berial\.pub-cache\hosted\pub.dev\animated_stack_widget-0.0.4\lib\fix_data',  // 不存在的子目录
  ];

  for (final p in paths) {
    try {
      final exists = Directory(p).existsSync();
      print('OK   $p  exists=$exists');
    } catch (e) {
      print('FAIL $p  -> $e');
    }
  }
}
```

### 2.3 实际输出

```
FAIL \\wsl.localhost  -> FileSystemException: Exists failed, path = '\\wsl.localhost' (OS Error: 指定的路径无效。, errno = 161)
OK   \\wsl.localhost\Ubuntu-24.04\home\berial  exists=true
OK   \\?\UNC\wsl.localhost\Ubuntu-24.04\home\berial  exists=true
FAIL \\wsl.localhost\Ubuntu-24.04\home\berial\.pub-cache\hosted\pub.dev\animated_stack_widget-0.0.4\lib\fix_data  -> FileSystemException: Exists failed, ... (errno = 161)
```

**关键发现**：
- `\\wsl.localhost`（无 share）→ 抛 errno 161
- 不存在的子目录 → 也抛 errno 161（不是返回 `false`）
- 完整 UNC（无论是否带 `\\?\UNC\` 前缀）→ 正常

---

## 3. 根因分析

### 3.1 完整调用链（已纠正）

```
Analysis Server 索引文件
    ↓
_PhysicalResource.exists                                  ← analyzer API
    ↓
_entry.existsSync()                                       ← dart:io API
    ↓
对 \\wsl.localhost（无 share）或不存在的子目录抛 errno 161
    ↓
FileSystemException 直接传播（3.11.5 缺 try-catch）
    ↓
Analysis Server 索引中断
    ↓
所有 import 'package:...' 报红
```

### 3.2 出问题的代码（3.11.5 stable SDK）

[`pkg/analyzer/lib/file_system/physical_file_system.dart`](https://github.com/dart-lang/sdk/blob/main/pkg/analyzer/lib/file_system/physical_file_system.dart) 中 `_PhysicalResource.exists`：

```dart
// 3.11.5 及以下 stable（有问题）
@override
bool get exists => _entry.existsSync();   // 直接传播 FileSystemException
```

### 3.3 main 分支已修复

main 分支已经添加 try-catch（且已回填 stable：**Dart 3.12.2 起包含此修复**，当前 stable HEAD 也含）：

```dart
// main 分支（已修复）
@override
bool get exists {
  try {
    return _entry.existsSync();
  } on FileSystemException {
    return false;   // 把 errno 161 等异常吞掉，返回 false
  }
}
```

`_PhysicalLink.exists` 同样有此修复。

### 3.4 为什么前期会误判为 FormatException

前期假设的调用链是：

```
Directory.resolveSymbolicLinksSync() → 返回 \\?\UNC\... → path.toUri() → FormatException
```

**这个假设在三个环节都站不住脚**：

1. **`resolveSymbolicLinksSync()` 返回值没有传给 `path.toUri()`**
   - analyzer 中 `resolveSymbolicLinksSync()` 的 4 个调用点（`context_root.dart` 等），返回值都只用于 `Set.add()` 去重或资源查找
   - 唯一调用 `context.toUri()` 的地方在 `uri_converter.dart`，且只对**相对路径**调用，不会接收 `\\?\UNC\...` 形式

2. **analyzer 的 `toUri()` 用 `Uri.file()`，不是 `path.toUri()`**
   - `_PhysicalFile.toUri() => Uri.file(path)`
   - `_PhysicalFolder.toUri() => Uri.directory(path)`
   - `Uri.file()` / `Uri.directory()` 能正确处理 `\\?\UNC\...`（自动剥离前缀），**不会抛 FormatException**

3. **AS log 实际捕获的是 `FileSystemException`，不是 `FormatException`**
   - 异常发生在 `_PhysicalResource.exists` → `_entry.existsSync()`
   - 与 `resolveSymbolicLinksSync` 无关
   - 与 `path.toUri` 无关

### 3.5 `package:path` 的 `FormatException` 是次要问题

`package:path` 的 `WindowsStyle.absolutePathToUri` 确实对 `\\?\UNC\...` 抛 `FormatException`（已通过 `tools/test_path_unc_full.dart` 验证），但 **analyzer 不会触发它**。这是独立的上游 bug，可单独提 Issue，但不是 AS import 全红的根因。

---

## 4. 验证：不调用 `resolveSymbolicLinksSync()` 是否就正常？

> 用户问题："验证 Analysis Server 不调用 `resolveSymbolicLinksSync()` 就正常"

**结论：不调用 `resolveSymbolicLinksSync()` 也不会正常**。

| 验证点 | 结果 |
|--------|------|
| analyzer 中 `resolveSymbolicLinksSync()` 返回值是否传给 `path.toUri()` | ❌ 否，只用于 Set 去重和资源查找 |
| analyzer 的 `_PhysicalResource.toUri()` 用什么 | `Uri.file()` / `Uri.directory()`，不是 `path.toUri()` |
| `Uri.file()` 处理 `\\?\UNC\...` 是否抛异常 | ❌ 不抛，能正确剥离前缀 |
| AS log 中实际异常类型 | `FileSystemException` (errno 161)，**不是** `FormatException` |
| 异常发生位置 | `_PhysicalResource.exists` → `_entry.existsSync()` |
| 是否与 `resolveSymbolicLinksSync` 有关 | ❌ 无关 |

**真正修复点**：`_PhysicalResource.exists` 添加 try-catch（main 分支已做，3.11.5 未回填）。

---

## 5. 为什么不能用 dependency_override 绕过

`D:\Android\FlutterWrapper\bin\cache\dart-sdk\lib\_internal` 内**没有 analyzer / path 包 dart 源码**。
但 `bin\snapshots\analysis_server.dart.snapshot` 中**内嵌了 analyzer 和 path 包代码**：

```
FOUND: absolutePathToUri in analysis_server snapshot
FOUND: WindowsStyle in analysis_server snapshot
FOUND: package:path reference
FOUND: _PhysicalResource in analysis_server snapshot
```

即 Analysis Server 用的是 SDK 编译期打入 snapshot 的 analyzer / path 副本，
项目级 `dependency_overrides:` **完全无效**（已实测验证）。

修复只能通过：
1. 等 dart-lang/sdk 把 main 分支的 try-catch 回填到 stable
2. 等 Dart SDK 下个版本重新编译 analysis_server snapshot
3. 或本地 patch snapshot（不推荐，每个 SDK 版本都要重做）

---

## 6. 上游状态

### 6.1 真正根因（analyzer）

- 仓库：[dart-lang/sdk](https://github.com/dart-lang/sdk)
- 文件：`pkg/analyzer/lib/file_system/physical_file_system.dart`
- main 分支已修复：`_PhysicalResource.exists` 和 `_PhysicalLink.exists` 都加了 try-catch
- 3.11.5 及以下 stable：**未修复**
- **Dart 3.12.2 stable 起已含修复**（当前 stable HEAD 也含）—— 本地升级到 3.12.2+ 即可彻底解决，无需等回填
- Issue #63855：2026-07-20 已将标题/正文更新为「已修复」记录（保留作根因 + 修复位置锚点，供仍卡在 3.11.x 的用户）

### 6.2 次要问题（path 包）

- 仓库：[dart-lang/core/pkgs/path](https://github.com/dart-lang/core/tree/main/pkgs/path)
- 文件：`pkgs/path/lib/src/style/windows.dart`
- main 分支 `windows.dart` 与 1.9.1 完全一致，**未修复**
- 这是独立 bug，不影响 analyzer（analyzer 用 `Uri.file()`），但影响其他直接调用 `path.toUri()` 的代码
- **已提交 Issue**：https://github.com/dart-lang/core/issues/980

---

## 7. 临时规避方案

> ✅ **2026-07-20 已通过升级 Dart SDK 到 3.12.2（Flutter 3.44.6）彻底解决**，Android Studio import 全红消失。以下为 3.11.5 时期的临时规避方案，升级后无需采用。

| 方案 | 评估 |
|------|------|
| 关闭 AS Dart 分析器 | 失去代码补全/跳转；最快但损失大 |
| AS Remote Development + WSL | AS 在 WSL 内运行，路径全部 Linux 化；推荐但需要重新搭环境 |
| 本地项目副本 | Windows 副本用于编辑/分析，WSL 副本用于编译；同步成本高 |
| Patch analysis_server snapshot | 每个 SDK 版本都要重做；不推荐 |
| 等待 stable SDK 回填 main 的 try-catch | 不可控时间 |

FlutterWrapper 不再修改 run/build/daemon 来尝试修复此问题——已经稳定的部分不应被破坏。

---

## 8. 对 FlutterWrapper 的定位影响

这次验证反而让 FlutterWrapper 的职责更清晰：

```
FlutterWrapper
  ├─ flutter / dart / pub        ✅ 已完成
  ├─ run / build                 ✅ 已完成
  ├─ daemon (TCP 翻译)           ✅ 已完成
  └─ Analysis Compatibility      ✅ 上游 Dart 3.12.2 已修复（无需 wrapper 改动）
```

详见 [README.md - Known Issues](../README.md#known-issues)。

---

## 9. 附录：诊断脚本

| 脚本 | 用途 |
|------|------|
| [tools/test_exists_sync.dart](../tools/test_exists_sync.dart) | 复现 AS log 中的 `FileSystemException` (errno 161) |
| [tools/test_uri_file.dart](../tools/test_uri_file.dart) | 验证 `Uri.file()` 能正确处理 `\\?\UNC\...`（不抛 FormatException） |
| [tools/test_path_unc_full.dart](../tools/test_path_unc_full.dart) | 验证 `package:path` 的 `FormatException` 是独立 bug（不被 analyzer 触发） |

环境：
- Windows 11
- WSL2 (Ubuntu-24.04)
- Dart SDK 3.11.5 (stable) on windows_x64 —— **问题版本；3.12.2 stable 已修复**
- Flutter 3.44.6 / Dart 3.12.2（2026-07-20 验证修复）
- path 1.9.1
- Android Studio (最新版)

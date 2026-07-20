# 上游 Issue 草稿

> **状态**：✅ 两个 Issue 均已提交（2026-07-20）
> **修订记录**：2026-07-20 重大修订——根因从 `package:path` 的 `FormatException` 改为 `analyzer` 的 `_PhysicalResource.exists` 缺 try-catch。

## 提交结果

| Issue | 仓库 | URL | 状态 |
|-------|------|-----|------|
| #1（主，根因） | dart-lang/sdk | https://github.com/dart-lang/sdk/issues/63855 | ✅ Open |
| #2（次，独立 bug） | dart-lang/core | https://github.com/dart-lang/core/issues/980 | ✅ Open |

---

## Issue #1（主 Issue，提交到 dart-lang/sdk）

**Repository**: [dart-lang/sdk](https://github.com/dart-lang/sdk)
**Title**: `[analyzer] _PhysicalResource.exists` propagates `FileSystemException` on Windows UNC paths (fixed on main, please backport to stable)

### Body

#### Summary

`_PhysicalResource.exists` in `pkg/analyzer/lib/file_system/physical_file_system.dart` propagates `FileSystemException` when `dart:io`'s `_Directory.existsSync` throws on certain Windows UNC paths. This breaks the Dart Analysis Server when a project is opened via a network drive / UNC path (including WSL2's `\\wsl.localhost\<distro>\...`), causing all `import 'package:...'` URIs to be marked as unresolved in Android Studio / IntelliJ.

**The fix is already on `main`** — `_PhysicalResource.exists` and `_PhysicalLink.exists` both wrap `existsSync()` in `try { ... } on FileSystemException { return false; }`. This Issue is to request that the fix be backported to the current stable channel (3.11.5).

#### Reproduction

1. Open a Dart/Flutter project located in WSL2 via mapped drive (`W:\` → `\\wsl.localhost\Ubuntu-24.04\...`) or directly via UNC in Android Studio on Windows.
2. All `import 'package:xxx/...'` show red: `Target of URI doesn't exist: 'package:flutter/foundation.dart'.`
3. `flutter run` / `flutter build` / `flutter daemon` all work normally — only the Analysis Server is affected.

#### Actual exception (from AS log)

```
FileSystemException: Exists failed, path = '\\\wsl.localhost\Ubuntu-24.04\home\berial\.pub-cache\hosted\pub.dev\animated_stack_widget-0.0.4\lib\fix_data' (OS Error: 指定的路径无效。, errno = 161)
#0  _Directory.existsSync (dart:io/directory_impl.dart:97)
#1  _PhysicalResource.exists (package:analyzer/file_system/physical_file_system.dart:368)
#2  ...
```

`errno = 161` is Windows `ERROR_INVALID_PATH` ("The specified path is invalid"). Note that the reported path `animated_stack_widget-0.0.4\lib\fix_data` does **not exist** on disk (lib/ only contains `src/` and `animated_stack_widget.dart`). On Windows, `Directory.existsSync()` throws `FileSystemException` instead of returning `false` for certain invalid UNC paths.

#### Minimal reproduction

```dart
// test_exists_sync.dart
import 'dart:io';

void main() {
  final paths = [
    r'\\wsl.localhost',                                              // no share
    r'\\wsl.localhost\Ubuntu-24.04\home\berial\.pub-cache\hosted\pub.dev\animated_stack_widget-0.0.4\lib\fix_data',  // non-existent subpath
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

Output on Windows 11 + WSL2:
```
FAIL \\wsl.localhost  -> FileSystemException: Exists failed, ... (errno = 161)
FAIL \\wsl.localhost\Ubuntu-24.04\home\berial\.pub-cache\hosted\pub.dev\animated_stack_widget-0.0.4\lib\fix_data  -> FileSystemException: ... (errno = 161)
```

#### Current behavior (3.11.5 stable)

[`pkg/analyzer/lib/file_system/physical_file_system.dart`](https://github.com/dart-lang/sdk/blob/stable/pkg/analyzer/lib/file_system/physical_file_system.dart) on stable:

```dart
abstract class _PhysicalResource implements Resource {
  // ...
  @override
  bool get exists => _entry.existsSync();   // propagates FileSystemException
}
```

The `FileSystemException` from `existsSync()` propagates up and breaks Analysis Server indexing.

#### Expected behavior (main branch — already fixed)

```dart
abstract class _PhysicalResource implements Resource {
  // ...
  @override
  bool get exists {
    try {
      return _entry.existsSync();
    } on FileSystemException {
      return false;
    }
  }
}
```

`_PhysicalLink.exists` has the same fix on main.

#### Why this matters

The WSL2 + Android Studio workflow is increasingly common (Linux toolchain in WSL, IDE on Windows). Without this fix, Dart/Flutter development against a WSL-located project is essentially unusable — users have to disable the analyzer entirely, switch to AS Remote Development, or maintain a duplicate Windows-side copy of the project.

Since the fix is already on `main`, could it please be backported to the current stable channel so end users on stable Dart SDK can benefit?

#### Environment

- Dart SDK: 3.11.5 (stable) on `windows_x64`
- OS: Windows 11 + WSL2 (Ubuntu-24.04)
- Android Studio (latest) with Dart plugin

#### Related (separate but similar) issue

`package:path`'s `WindowsStyle.absolutePathToUri` also has a bug with `\\?\UNC\...` paths (throws `FormatException`). That is a separate issue and **not** the root cause of this one (analyzer uses `Uri.file()` which handles `\\?\UNC\...` correctly). Will be filed separately to `dart-lang/core`.

---

## Issue #2（次 Issue，提交到 dart-lang/core）

**Repository**: [dart-lang/core](https://github.com/dart-lang/core)
**Title**: `[path]` `WindowsStyle.absolutePathToUri` throws `FormatException` on Windows Extended-Length UNC paths (`\\?\UNC\...`)

### Body

#### Summary

`package:path`'s `WindowsStyle.absolutePathToUri` throws `FormatException` when given a Windows Extended-Length UNC path of the form `\\?\UNC\server\share\...`. These paths are returned by `Directory.resolveSymbolicLinksSync()` (which calls the Windows API `GetFinalPathNameByHandle`) for any UNC path, and are also the documented way to bypass MAX_PATH limits on Windows.

Note: this is **not** the root cause of Analysis Server failing on WSL projects (that's [analyzer's `_PhysicalResource.exists` missing try-catch](https://github.com/dart-lang/sdk), filed separately). But it is a real bug that affects any code calling `path.toUri()` on a `resolveSymbolicLinksSync()` result.

#### Reproduction

`pubspec.yaml`:
```yaml
name: test_path_unc
environment:
  sdk: ^3.0.0
dependencies:
  path: ^1.9.0
```

`test.dart`:
```dart
import 'dart:io';
import 'package:path/path.dart' as p;

void main() {
  final resolved = Directory.current.resolveSymbolicLinksSync();
  print('resolved: $resolved');

  final uri = p.toUri(resolved);   // <- throws
  print('uri: $uri');
}
```

Run from a UNC/mapped-drive directory:
```
cd W:\tmp\test_path_unc   (W: -> \\wsl.localhost\Ubuntu-24.04)
dart run test.dart
```

#### Actual output

```
resolved: \\?\UNC\wsl.localhost\Ubuntu-24.04\tmp\test_path_unc

FormatException: Invalid character (at character 1)
?
^

#0  _Uri._fail (dart:core/uri.dart:2050:5)
#1  _Uri._normalizeRegName (dart:core/uri.dart:2598:9)
#2  _Uri._makeHost (dart:core/uri.dart:2453:12)
#3  new _Uri (dart:core/uri.dart:1955:12)
#4  WindowsStyle.absolutePathToUri (package:path/src/style/windows.dart:121:14)
#5  Context.toUri (package:path/src/context.dart:1062:20)
#6  toUri (package:path/path.dart:459:35)
```

#### Boundary test

| Input | Result |
|-------|--------|
| `\\?\UNC\wsl.localhost\Ubuntu-24.04\home\berial` | FAIL |
| `\\?\UNC\localhost\c$\Users` | FAIL |
| `\\?\UNC\127.0.0.1\c$\Users` | FAIL |
| `\\?\UNC\someserver\share\path` | FAIL (even non-existent server) |
| `\\wsl.localhost\Ubuntu-24.04\home\berial` | OK |
| `\\localhost\c$\Users` | OK |
| `\\someserver\share\path` | OK |
| `W:\home\berial` | OK |

So the bug is not WSL-specific — it affects **all** Windows Extended UNC paths (`\\?\UNC\*`).

Note: `Uri.file()` (from `dart:core`) handles `\\?\UNC\...` correctly (strips the prefix), so this is specifically a `package:path` issue, not a `dart:core` issue.

#### Root cause

[`pkgs/path/lib/src/style/windows.dart:29`](https://github.com/dart-lang/core/blob/main/pkgs/path/lib/src/style/windows.dart#L29):

```dart
final rootPattern = RegExp(r'^(\\\\[^\\]+\\[^\\/]+|[a-zA-Z]:[/\\])');
```

The first alternative `\\\\[^\\]+\\[^\\/]+` is meant to match `\\server\share`, but it also matches `\\?\UNC` because `[^\\]+` happily matches `?`.

Then in `absolutePathToUri` ([line 121](https://github.com/dart-lang/core/blob/main/pkgs/path/lib/src/style/windows.dart#L121)):

```dart
final rootParts = parsed.root!.split('\\').where((part) => part != '');
parsed.parts.insert(0, rootParts.last);
// ...
return Uri(scheme: 'file', host: rootParts.first, pathSegments: parsed.parts);
```

- `parsed.root` = `\\?\UNC`
- `split('\\')` → `['', '', '?', 'UNC']`
- `where((part) => part != '')` → `['?', 'UNC']`
- `rootParts.first` = `'?'`
- `Uri(host: '?')` → FormatException (`?` is not a valid URI host)

#### Suggested fix

Either strip the `\\?\` / `\\?\UNC\` prefix before parsing, or refine the `rootPattern` to not match `\\?\`:

```dart
// Option A: strip extended-length prefix in absolutePathToUri
Uri absolutePathToUri(String path) {
  if (path.startsWith(r'\\?\UNC\\')) {
    path = r'\\' + path.substring(8);
  } else if (path.startsWith(r'\\?\')) {
    path = path.substring(4);
  }
  // ... existing logic
}
```

```dart
// Option B: refine rootPattern
final rootPattern = RegExp(r'^(\\\\[^\\?][^\\]*\\[^\\/]+|[a-zA-Z]:[/\\])');
```

#### Environment

- Dart SDK: 3.11.5 (stable) on `windows_x64`
- package:path: 1.9.1 (also confirmed `main` branch is affected)
- OS: Windows 11 + WSL2 (Ubuntu-24.04)

---

## 提交说明

两个 Issue 都是独立 bug，可以分别提交：

| Issue | 仓库 | 优先级 | 是否影响 AS |
|-------|------|--------|------------|
| #1 | dart-lang/sdk | 高 | ✅ 是（根因） |
| #2 | dart-lang/core | 中 | ❌ 否（独立 bug，analyzer 不触发） |

**gh CLI 提交命令**（需要用户在终端执行，因为 AI 的 OAuth token 无 issue:write 权限）:

```powershell
# Issue #1: dart-lang/sdk
gh issue create --repo dart-lang/sdk `
  --title "[analyzer] _PhysicalResource.exists propagates FileSystemException on Windows UNC paths (fixed on main, please backport to stable)" `
  --body-file docs/issue-dart-lang-core.md

# Issue #2: dart-lang/core
gh issue create --repo dart-lang/core `
  --title "[path] WindowsStyle.absolutePathToUri throws FormatException on Windows Extended-Length UNC paths" `
  --body-file docs/issue-dart-lang-core.md
```

> ⚠️ 上面两条命令用同一个 `--body-file`，需要分别截取对应章节。建议手动复制对应章节到临时文件再提交，或手动编辑提交。

### Summary

`_PhysicalResource.exists` in `pkg/analyzer/lib/file_system/physical_file_system.dart` propagates `FileSystemException` when `dart:io`'s `_Directory.existsSync` throws on certain Windows UNC paths. This breaks the Dart Analysis Server when a project is opened via a network drive / UNC path (including WSL2's `\\wsl.localhost\<distro>\...`), causing all `import 'package:...'` URIs to be marked as unresolved in Android Studio / IntelliJ.

**The fix is already on `main`** — `_PhysicalResource.exists` and `_PhysicalLink.exists` both wrap `existsSync()` in `try { ... } on FileSystemException { return false; }`. This Issue is to request that the fix be backported to the current stable channel (3.11.5).

### Reproduction

1. Open a Dart/Flutter project located in WSL2 via mapped drive (`W:\` → `\\wsl.localhost\Ubuntu-24.04\...`) or directly via UNC in Android Studio on Windows.
2. All `import 'package:xxx/...'` show red: `Target of URI doesn't exist: 'package:flutter/foundation.dart'.`
3. `flutter run` / `flutter build` / `flutter daemon` all work normally — only the Analysis Server is affected.

### Actual exception (from AS log)

```
FileSystemException: Exists failed, path = '\\\wsl.localhost\Ubuntu-24.04\home\berial\.pub-cache\hosted\pub.dev\animated_stack_widget-0.0.4\lib\fix_data' (OS Error: 指定的路径无效。, errno = 161)
#0  _Directory.existsSync (dart:io/directory_impl.dart:97)
#1  _PhysicalResource.exists (package:analyzer/file_system/physical_file_system.dart:368)
#2  ...
```

`errno = 161` is Windows `ERROR_INVALID_PATH` ("The specified path is invalid"). Note that the reported path `animated_stack_widget-0.0.4\lib\fix_data` does **not exist** on disk (lib/ only contains `src/` and `animated_stack_widget.dart`). On Windows, `Directory.existsSync()` throws `FileSystemException` instead of returning `false` for certain invalid UNC paths.

### Minimal reproduction

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

### Current behavior (3.11.5 stable)

[`pkg/analyzer/lib/file_system/physical_file_system.dart`](https://github.com/dart-lang/sdk/blob/stable/pkg/analyzer/lib/file_system/physical_file_system.dart) on stable:

```dart
abstract class _PhysicalResource implements Resource {
  // ...
  @override
  bool get exists => _entry.existsSync();   // propagates FileSystemException
}
```

The `FileSystemException` from `existsSync()` propagates up and breaks Analysis Server indexing.

### Expected behavior (main branch — already fixed)

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

### Why this matters

The WSL2 + Android Studio workflow is increasingly common (Linux toolchain in WSL, IDE on Windows). Without this fix, Dart/Flutter development against a WSL-located project is essentially unusable — users have to disable the analyzer entirely, switch to AS Remote Development, or maintain a duplicate Windows-side copy of the project.

Since the fix is already on `main`, could it please be backported to the current stable channel so end users on stable Dart SDK can benefit?

### Environment

- Dart SDK: 3.11.5 (stable) on `windows_x64`
- OS: Windows 11 + WSL2 (Ubuntu-24.04)
- Android Studio (latest) with Dart plugin

### Related (separate but similar) issue

`package:path`'s `WindowsStyle.absolutePathToUri` also has a bug with `\\?\UNC\...` paths (throws `FormatException`). That is a separate issue and **not** the root cause of this one (analyzer uses `Uri.file()` which handles `\\?\UNC\...` correctly). Will be filed separately to `dart-lang/core`.

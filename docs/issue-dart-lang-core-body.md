### Summary

`package:path`'s `WindowsStyle.absolutePathToUri` throws `FormatException` when given a Windows Extended-Length UNC path of the form `\\?\UNC\server\share\...`. These paths are returned by `Directory.resolveSymbolicLinksSync()` (which calls the Windows API `GetFinalPathNameByHandle`) for any UNC path, and are also the documented way to bypass MAX_PATH limits on Windows.

Note: this is **not** the root cause of Analysis Server failing on WSL projects (that's [analyzer's `_PhysicalResource.exists` missing try-catch](https://github.com/dart-lang/sdk), filed separately). But it is a real bug that affects any code calling `path.toUri()` on a `resolveSymbolicLinksSync()` result.

### Reproduction

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

### Actual output

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

### Boundary test

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

### Root cause

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

### Suggested fix

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

### Environment

- Dart SDK: 3.11.5 (stable) on `windows_x64`
- package:path: 1.9.1 (also confirmed `main` branch is affected)
- OS: Windows 11 + WSL2 (Ubuntu-24.04)

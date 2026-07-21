Hi @lrhn, thanks for the response.

I'd recommend **option B** (recognize `wsl.localhost` as host, strip `?\UNC\` prefix):

```
\\?\UNC\wsl.localhost\Ubuntu-24.04\tmp\foo
  → file://wsl.localhost/Ubuntu-24.04/tmp/foo
```

**Rationale:**

1. **Consistency with `Uri.file()`** — Dart SDK's `Uri.file()` already does this. `Uri.file(r'\\?\UNC\wsl.localhost\Ubuntu-24.04\tmp\foo')` correctly returns `file://wsl.localhost/Ubuntu-24.04/tmp/foo` without throwing. Having `path.toUri()` throw on the same input creates an inconsistency that bites real-world tools (e.g., analyzer internals).

2. **WSL paths are a real Windows use case** — `\\wsl.localhost\<distro>\...` is how Windows natively exposes WSL filesystems. Users hit this path format whenever they cross the Windows/WSL boundary, which is increasingly common.

3. **Option A (`file:////?/UNC/...`) leaks implementation detail** — the `\\?\` prefix is a Windows API artifact (GetFinalPathNameByHandle always returns it for UNC paths), not user intent. Exposing it in URIs just pushes the problem downstream.

**Repro:**

```dart
import 'package:path/path.dart' as p;

void main() {
  // Works fine
  print(Uri.file(r'\\?\UNC\wsl.localhost\Ubuntu-24.04\tmp\foo'));
  // → file://wsl.localhost/Ubuntu-24.04/tmp/foo

  // Throws FormatException
  print(p.toUri(r'\\?\UNC\wsl.localhost\Ubuntu-24.04\tmp\foo'));
  // → FormatException: Illegal character in path
}
```

Happy to submit a PR if you confirm the direction.

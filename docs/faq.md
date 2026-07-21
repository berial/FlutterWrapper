# FAQ

## Why WSL Flutter instead of Windows Flutter?

- **Linux toolchain**: Native NDK, cmake, and build tools run natively without cross-compilation overhead.
- **File system performance**: WSL ext4 outperforms NTFS for many small files (typical in Flutter projects).
- **Version management**: vfox and FVM provide excellent Flutter SDK version management on Linux.
- **Docker/CI parity**: Your dev environment matches Linux CI runners.

## Why does the project need to be on WSL filesystem?

Flutter toolchain (Gradle, NDK, cmake) runs inside WSL. If your project is on Windows NTFS (`C:\` or `D:\`), every file access crosses the WSL/NTFS boundary, causing significant slowdowns (especially for `pub get` and Gradle builds).

## Why is W: drive mapping required?

CMD.EXE (which Android Studio uses to spawn `flutter.bat`) **does not support UNC paths** as the current directory. If you open a project via `\\wsl.localhost\...`, CMD silently falls back to `C:\Windows`, and Flutter fails with "No pubspec.yaml file found".

Mapping a drive letter (W:) makes the WSL filesystem accessible as a normal drive that CMD can use as cwd.

## Why does FlutterWrapper modify package_config.json?

The Dart Analysis Server runs natively on **Windows** (via `dart.exe` from the Junction). It needs Windows-style paths to find packages. The WSL Flutter compiler needs Linux paths.

FlutterWrapper translates the file to use `file:///w:/...` format after `pub get`. Windows Dart reads it via `W:\`, WSL Dart resolves it via `/w:` symlinks. Both sides share one file.

## Does this work with VS Code?

VS Code has native [Remote - WSL](https://code.visualstudio.com/docs/remote/wsl) support. There's no need for FlutterWrapper in VS Code — just open your project directly from WSL.

FlutterWrapper targets Android Studio specifically because IntelliJ-based IDEs don't have native WSL remote development.

## What Flutter versions are supported?

Flutter 3.22+. Recommended: 3.44+ (Dart 3.12.2+ fixes a UNC path bug in the Dart analysis server).

## What if I already have Flutter on Windows?

FlutterWrapper can coexist. The Junction at `bin/cache/dart-sdk` points to the Windows Flutter's Dart SDK for analysis. The WSL Flutter is used for all build/run operations.

## Which SDK manager should I use?

- **vfox**: General-purpose version manager. Supports Flutter, Java, Node.js, Python, Go, etc. One tool for all SDKs. Recommended for polyglot developers.
- **FVM**: Flutter-specific version manager. Deeper Flutter integration (`.fvmrc` is the community standard for Flutter projects). Recommended for Flutter-only developers.

Both work with FlutterWrapper. Run `fw provider` to see which one is detected.

## How do I switch Flutter versions?

```powershell
fw flutter use 3.44.6    # Routes to vfox or FVM automatically
```

Or directly:
```bash
# vfox in WSL
vfox use -g flutter@3.44.6

# FVM in WSL
fvm global 3.44.6
```

After switching, restart Android Studio for the Dart plugin to pick up the new Dart SDK version.

## Why "not a FlutterWrapper bug"?

FlutterWrapper is a compatibility layer — it translates between Windows and WSL. Some issues (like the old Dart analysis server UNC bug, or web device discovery on Linux) originate in Flutter/Dart itself and affect all WSL users, not just FlutterWrapper users.

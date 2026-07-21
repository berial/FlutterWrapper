# Quick Start

## Prerequisites

- Windows 10 or 11 with WSL2 enabled
- A WSL distribution installed (Ubuntu 24.04 recommended)
- Flutter SDK installed inside WSL (via [vfox](https://vfox.dev) or [FVM](https://fvm.app))
- Android Studio with Flutter plugin

## 1. Install FlutterWrapper

```powershell
git clone https://github.com/<user>/FlutterWrapper.git %USERPROFILE%\FlutterWrapper
cd %USERPROFILE%\FlutterWrapper
powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1 -Auto
```

The installer auto-detects:
- WSL distro (auto-selects Ubuntu-24.04, or first available)
- Flutter SDK path (checks `command -v flutter` → vfox → FVM → manual)
- Dart SDK path (derived from Flutter)
- JDK path (vfox → JAVA_HOME → PATH)
- Android SDK path
- Maps W: drive to WSL filesystem

## 2. Run diagnostics

```powershell
fw doctor
```

Should show all ✓. If any ✗, run:

```powershell
fw doctor --fix-safe    # auto-repair safe items
# or
fw repair <module>      # repair specific component
```

## 3. Configure Android Studio

1. Open Android Studio
2. **File → Settings → Languages & Frameworks → Flutter**
   - Flutter SDK path: `%USERPROFILE%\FlutterWrapper`
3. **File → Settings → Languages & Frameworks → Dart**
   - Dart SDK path: `%USERPROFILE%\FlutterWrapper\bin\cache\dart-sdk`
4. Restart Android Studio

## 4. Open a Flutter project

**Critical**: Open projects via the mapped drive letter, NOT UNC path.

```
✅ Correct:  W:\home\<user>\projects\my_app
❌ Wrong:    \\wsl.localhost\Ubuntu-24.04\home\<user>\projects\my_app
```

The installer creates `net use W: \\wsl.localhost\<distro>`. If it's lost after reboot, re-run:

```powershell
net use W: \\wsl.localhost\<your-distro> /persistent:yes
```

## 5. Start developing

All Flutter operations (pub get, run, hot reload, debug, build) now work through WSL.

```powershell
# In terminal:
fw status
fw flutter current

# Or use flutter.bat directly:
%USERPROFILE%\FlutterWrapper\bin\flutter.bat devices
%USERPROFILE%\FlutterWrapper\bin\flutter.bat run
```

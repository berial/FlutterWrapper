# Troubleshooting

## First step: Run diagnostics

```powershell
fw doctor
```

This checks 13 categories and gives fix suggestions for each failure.

## Common issues and fixes

### "No pubspec.yaml file found" in Android Studio

**Cause**: Project opened via UNC path (`\\wsl.localhost\...`).

**Fix**:
1. Close the project in Android Studio
2. Re-open via mapped drive: `W:\home\<user>\<project>`
3. Verify mapping: `net use W:` should show `\\wsl.localhost\<distro>`

### All imports show red in Android Studio

**Cause**: Dart analysis server bug (pre-3.12.2) on UNC paths.

**Fix**: Upgrade to Flutter ≥ 3.44.6 (Dart ≥ 3.12.2). Then:
```powershell
fw repair dart-sdk
fw repair package-config
```
Restart Android Studio.

### flutter --version hangs or has no output

**Fix**:
```powershell
fw repair config       # re-detect and rewrite config
fw repair daemon       # kill stale daemon processes
fw doctor              # verify
```

Check logs at `logs/flutter.log`.

### Daemon mode not responding

**Fix**:
```powershell
fw repair daemon       # kills stale daemon on port 9876
```

Or manually:
```powershell
wsl -e bash -c "fuser -k 9876/tcp"
```

### "Flutter SDK not found" in Android Studio

**Fix**:
```powershell
fw repair dart-sdk     # re-create Junction
fw doctor --fix-safe   # auto-repair safe items
```

### W: drive not accessible after reboot

**Fix**:
```powershell
net use W: \\wsl.localhost\<your-distro> /persistent:yes
```

Or re-run: `install.ps1 -Auto -SkipSmoke`

### Path translation errors

```powershell
fw doctor               # Section 5 checks path mapping
```

If specific paths aren't translating correctly, check `logs/flutter.log` for the actual conversion.

### Package resolution errors in WSL build (`/w:/.../No such file`)

**Fix**:
```powershell
fw repair symlinks      # re-create /w: and /W: symlinks
```

This requires sudo in WSL. If it fails, run manually:
```bash
wsl -e sudo bash tools/setup-wsl-symlink.sh <distro> W
```

## Getting a diagnostic report

```powershell
fw doctor --json > doctor-report.json
```

Attach this file when opening GitHub issues.

## Still stuck?

Open an issue at our GitHub repository with the diagnostic report and a description of what you're seeing.

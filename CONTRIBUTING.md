# Contributing

Thanks for your interest in FlutterWrapper!

## Development Environment

- Windows 10/11 with WSL2
- PowerShell 5.1+ (use `$ErrorActionPreference = 'Stop'` in scripts)
- ShellCheck for `.sh` files (`sudo apt install shellcheck` in WSL)

No Flutter SDK or Android Studio is needed to contribute to the wrapper itself — only for full integration testing.

## Code Structure

```
bin/          CLI entry points (.bat for Windows, .ps1 for logic)
  fw.ps1        Unified CLI router
  flutter.ps1   WSL command bridge
  doctor.ps1    Diagnostic orchestrator
lib/          Reusable modules (dot-sourced)
  config.ps1    YAML parser + output helpers
  repair.ps1    7 repair modules
  provider.ps1  Provider facade
  providers/    vfox.ps1, fvm.ps1
  doctor/       check-env, check-paths, check-tools, check-project
tools/        Maintenance scripts (not shipped in release)
docs/         User documentation
```

## Architecture Rules

1. **Config is external**: all paths come from `config/wrapper.yaml`, never hardcoded.
2. **lib/ for shared logic**: move common functions under `lib/`, dot-source from `bin/` scripts.
3. **Idempotent repair**: every `Repair-*` function must be safe to run multiple times.
4. **No PowerShell 7 features**: target PowerShell 5.1 (what Android Studio invokes).
5. **UTF-8 everywhere**: set `[Console]::OutputEncoding = [System.Text.Encoding]::UTF8`.

## Commit Convention

```
feat:     New feature
fix:      Bug fix
docs:     Documentation only
refactor: Code restructuring (no behavior change)
chore:    Maintenance (CI, .gitignore, etc.)
ci:       CI/CD changes
```

## Testing

```powershell
# PowerShell syntax check
$tokens = $null; $errors = $null
[System.Management.Automation.Language.Parser]::ParseFile("bin/fw.ps1", [ref]$tokens, [ref]$errors)

# Shell scripts
shellcheck tools/*.sh
```

CI runs these checks automatically on every push and PR.

## Adding a Provider

1. Create `lib/providers/<name>.ps1` with:
   - `Write-Provider<Name>` — output detection results
   - `Get-<Name>Current` — return current version string
   - `Set-<Name>Version` — switch version, return success
2. Dot-source it in `lib/provider.ps1`
3. Add dispatch in `Detect-Provider`, `Invoke-FlutterCurrent`, `Invoke-FlutterUse`

## Adding a Doctor Check

1. Create `lib/doctor/check-<topic>.ps1`
2. Use `Write-Check` with name/status/detail/fix parameters
3. Use script-scope variables: `$config`, `$distro`, `$quick`, `$jsonOut`
4. Dot-source it in `bin/doctor.ps1`
5. It runs automatically as part of `fw doctor`

## Release Process

1. Update `VERSION` file
2. Commit: `git commit -m "chore: bump version to X.Y.Z"`
3. Tag: `git tag -a vX.Y.Z -m "vX.Y.Z: <summary>"`
4. Push: `git push --tags`
5. CI auto-builds and uploads the release zip

## Questions?

Open an issue with `fw doctor --collect` output attached.

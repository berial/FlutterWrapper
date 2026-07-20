# 路径转换规则

> 基于 `wslpath` 实测（本机 Ubuntu-24.04 / WSL 2）+ 手工规则补充。
> wslpath 是 WSL 内置工具（`/usr/bin/wslpath`），用于 Windows ↔ WSL 路径互转，但有**重要盲区**。

## 1. wslpath 实测对照表

### 1.1 Windows 盘符路径 → WSL 路径（无 `-w`）

| 输入 | 输出 | 结果 |
|---|---|---|
| `D:\Android\FlutterWrapper` | `/mnt/d/Android/FlutterWrapper` | ✅ 正确 |
| `D:/Android/FlutterWrapper`（正斜杠） | `/mnt/d/Android/FlutterWrapper` | ✅ 正确（正反斜杠都认） |
| `D:\`（盘符根） | `/mnt/d/` | ✅ 正确 |
| `C:\Windows` | `/mnt/c/Windows` | ✅ 正确 |

### 1.2 WSL 路径 → Windows 路径（`-w`）

| 输入 | 输出 | 结果 |
|---|---|---|
| `/mnt/d/Android/FlutterWrapper` | `D:\Android\FlutterWrapper` | ✅ 正确（→ 盘符形式） |
| `/tmp` | `\\wsl.localhost\Ubuntu-24.04\tmp` | ✅ 正确（→ UNC 形式） |
| `/`（根） | `\\wsl.localhost\Ubuntu-24.04\` | ✅ 正确 |
| `/home/berial`（$HOME） | `\\wsl.localhost\Ubuntu-24.04\home\berial` | ✅ 正确（→ UNC 形式） |

### 1.3 UNC 路径 → WSL 路径（⚠️ wslpath 失败！）

| 输入 | 输出 | 结果 |
|---|---|---|
| `\\wsl.localhost\Ubuntu-24.04\home\berial` | `/mnt/d/wsl.localhost/Ubuntu-24.04/home/berial` | ❌ **错误！** 当成普通 Windows 网络路径 |
| `\\wsl.localhost\Ubuntu-24.04\`（尾斜杠） | `/mnt/d/wsl.localhost/Ubuntu-24.04/` | ❌ 错误 |
| `\\WSL.LOCALHOST\Ubuntu-24.04\home\berial`（大写） | `/mnt/d/WSL.LOCALHOST/Ubuntu-24.04/home/berial` | ❌ 错误（大小写不同被当成不同路径） |
| `\\wsl$\Ubuntu-24.04\home\berial` | `/mnt/d/wsl$/Ubuntu-24.04/home/berial` | ❌ 错误 |

### 1.4 相对路径

| 输入 | 输出 | 结果 |
|---|---|---|
| `lib/main.dart` | `lib/main.dart` | ✅ 原样返回 |
| `./lib` | `lib` | ✅ 规范化（去 `./`） |

## 2. wslpath 的盲区与手工补充规则

### 2.1 盲区：UNC 路径无法转回 WSL

wslpath 把 `\\wsl.localhost\<distro>\path` 当成普通 Windows 网络路径，映射到 `/mnt/d/wsl.localhost/...`，**完全错误**。

**正确转换**需要手工识别前缀并剥离：

```
\\wsl.localhost\<distro>\<path>  →  /<path>           （path 里的 \ 换成 /）
\\wsl$\<distro>\<path>           →  /<path>           （path 里的 \ 换成 /）
```

例如：
- `\\wsl.localhost\Ubuntu-24.04\home\berial\demo` → `/home/berial/demo`
- `\\wsl$\Ubuntu-24.04\tmp\foo` → `/tmp/foo`

### 2.2 大小写处理

UNC 前缀大小写不敏感：
- `\\wsl.localhost\` = `\\WSL.LOCALHOST\` = `\\Wsl.LocalHost\`
- `\\wsl$\` = `\\WSL$\` = `\\Wsl$\`

匹配前缀时应**大小写不敏感**比较，但 distro 名 `Ubuntu-24.04` 通常区分大小写（按实际发行版名）。

### 2.3 尾斜杠处理

- `\\wsl.localhost\Ubuntu-24.04\`（尾斜杠）→ `/`
- `\\wsl.localhost\Ubuntu-24.04`（无尾斜杠后无路径）→ `/`

## 3. 完整路径转换规则

### 3.1 Windows → WSL（用于翻译入参、cwd）

```
输入：Windows 路径（盘符形式 或 UNC 形式）

if 以 \\wsl.localhost\ 或 \\wsl$\ 开头（大小写不敏感）:
    剥离前缀 \\wsl.localhost\<distro>\ 或 \\wsl$\<distro>\
    剩余部分 \ → /
    前补 / （若不以 / 开头）
    return 结果

elif 匹配 /^[A-Za-z]:[\\/]/ （盘符路径）:
    return wslpath "<输入>"   # 依赖 wslpath

elif 是相对路径（不以 / \ 或盘符开头）:
    return 原样   # 相对路径不转换

else:
    return wslpath "<输入>"   # 兜底
```

### 3.2 WSL → Windows（用于翻译 daemon 事件里的路径）

```
输入：WSL 路径（/mnt/x/... 或 /home/... 等）

if 以 /mnt/<盘符>/ 开头:
    return wslpath -w "<输入>"   # → D:\... 盘符形式

elif 以 / 开头（WSL 内部路径，如 /home/berial/demo）:
    return wslpath -w "<输入>"   # → \\wsl.localhost\Ubuntu-24.04\home\berial\demo UNC 形式

else:
    return 原样   # 相对路径不转换
```

### 3.3 UNC 形式选择

WSL → Windows 翻译时，`wslpath -w` 对不同路径产生不同形式：
- `/mnt/d/...` → `D:\...`（盘符形式，Android Studio 原生支持）
- `/home/...` → `\\wsl.localhost\Ubuntu-24.04\home\...`（UNC 形式，Android Studio 通过 Windows 文件系统访问 WSL）

两种形式 Android Studio 都应能处理（JetBrains 平台支持 UNC）。但**优先用盘符形式**（性能更好，不走 9P 协议）。

## 4. cwd 转换

Android Studio 在 spawn `flutter.bat` 时会设置工作目录（cwd）为项目根目录，通常是 Windows 盘符路径如 `D:\workspace\demo`。

### 4.1 转换策略

```
Windows cwd: D:\workspace\demo
  ↓ wslpath
WSL cwd: /mnt/d/workspace/demo
  ↓ wsl.exe --cd <WSL cwd>
实际工作目录设置
```

### 4.2 PowerShell 实现

```powershell
$winCwd = Get-Location           # Windows 形式
$wslCwd = & wsl wslpath "$winCwd"  # 转成 WSL 形式
# 或直接用 wsl.exe 的 --cd 参数（自动转换）
wsl.exe -d Ubuntu-24.04 --cd "$winCwd" -e flutter @args
```

⚠️ `wsl.exe --cd` 参数支持 Windows 路径，会自动转换。这是最简方案。

### 4.3 特殊情况：cwd 在 WSL 内部

如果 Android Studio 打开的项目本身在 WSL 文件系统里（通过 `\\wsl.localhost\...` 访问），cwd 会是 UNC 形式。此时：
- `wsl.exe --cd` 可能无法正确处理 UNC 路径
- 需要手工把 UNC 转成 WSL 路径再传给 `--cd`

## 5. 参数中的路径转换

除了 cwd，命令参数里也可能有路径，例如：
- `flutter create D:\workspace\new_app`
- `flutter run --target=D:\workspace\demo\lib\main.dart`
- `flutter build apk --target=D:\workspace\demo\lib\main.dart`

### 5.1 转换策略

参数转换比 cwd 转换复杂，因为需要**识别哪些参数是路径**。保守策略：

| 策略 | 说明 | 风险 |
|---|---|---|
| **全参数扫描转换** | 遍历所有参数，凡是匹配 Windows 路径模式（`^[A-Za-z]:[\\/]` 或 `^\\\\wsl`）的都转换 | 可能误转非路径参数（罕见） |
| **按命令白名单转换** | 只对已知带路径参数的命令（create / run --target / build --target 等）转换 | 漏转风险 |
| **不转换，依赖 cwd** | 只转 cwd，参数用相对路径 | 不适用绝对路径参数 |

**推荐**：全参数扫描转换。Windows 路径模式（盘符开头或 UNC 开头）足够独特，误转概率极低。

### 5.2 路径模式识别正则

```
Windows 盘符路径：^[A-Za-z]:[\\/]
UNC 路径：^\\\\[^\\]+\\[^\\]+    （\\server\share\... 形式）
```

注意 `--target=D:\path` 这种 `key=value` 形式，要分离 `key=` 和 value 再转换 value。

### 5.3 不转换的参数

以下参数虽然像路径，但不应转换：
- `--device-id=emulator-5554`（设备 ID，不是路径）
- `--dart-define=KEY=value`（定义变量）
- URL 参数（`http://...`、`ws://...`）

识别关键：参数值以 `[A-Za-z]:[\\/]` 开头（盘符+反斜杠/正斜杠）才转。`emulator-5554` 不匹配这个模式。

## 6. daemon 协议中的路径转换

daemon 走 JSON-RPC，路径在结构化字段里，转换更精准。详见 [daemon.md](daemon.md) 第 6 节。

### 6.1 需要翻译的字段（汇总）

| 方向 | 消息 | 字段 | 翻译 |
|---|---|---|---|
| 入（请求） | `daemon.getSupportedPlatforms` | `params.projectRoot` | Windows → WSL |
| 入（请求） | `device.startApp` | `params.mainPath` | Windows → WSL（若绝对路径） |
| 出（事件） | `app.start` | `params.directory` | WSL → Windows |
| 出（事件） | `app.debugPort` | `params.baseUri` | 若 `file://` 则翻译 |

### 6.2 不翻译的字段（禁止翻译）

- `daemon.connected` 的 `version`/`pid`（**无 sdk 字段**）
- 设备 map 的 `emulatorId`/`category`/`platformType`/`platform`/`sdk`/`connectionInterface`
- emulator map 的 `id`/`name`/`category`/`platformType`
- 所有 `appId`/`deviceId`/`applicationPackageId`
- `proxy.*` 的 `path`（相对 temp 目录，非项目路径）
- `wsUri`/`devTools.uri`/`dtd.uri`（网络 URI，非文件路径，除非 WSL2 localhost 转发失败）

## 7. 边界情况与陷阱

### 7.1 带空格的路径

Windows 路径带空格（`D:\My Projects\demo`）：
- wslpath 能正确处理
- 传给 wsl.exe 时需要正确引号

### 7.2 中文路径

- wslpath 能正确处理 UTF-8 中文路径
- PowerShell 脚本必须设 `[Console]::OutputEncoding = [System.Text.Encoding]::UTF8`
- 否则中文路径在传递过程中会乱码

### 7.3 符号链接

WSL 内的符号链接（如 `/home/berial/flutter` → 某处）：
- `wslpath -w` 只做路径形式转换，不解析符号链接
- daemon 返回的路径可能是符号链接路径，翻译后 Android Studio 访问的可能是未解析的 UNC 路径
- 一般无影响，但若 Android Studio 要求真实路径可能出问题

### 7.4 大小写敏感

- Windows 路径大小写不敏感
- WSL（Linux）路径大小写敏感
- Windows → WSL 转换时，盘符后的路径大小写需要与 WSL 实际一致
- `D:\Android\demo` → `/mnt/d/Android/demo`，若 WSL 实际是 `/mnt/d/android/demo`（小写），会找不到

### 7.5 路径分隔符混合

Windows 路径里可能混用 `\` 和 `/`（如 `D:\Android/FlutterWrapper`）：
- wslpath 能正确处理
- 但 daemon 返回的 WSL 路径是纯 `/`，翻译回 Windows 时 `wslpath -w` 会统一成 `\`

## 8. 推荐实现：封装路径转换函数

建议在 `wrapper.ps1` 里封装两个核心函数：

```powershell
# Windows 路径 → WSL 路径
function ConvertTo-WslPath {
    param([string]$Path)
    if (-not $Path) { return $Path }
    # UNC \\wsl.localhost\<distro>\ 或 \\wsl$\<distro>\
    if ($Path -match '^\\\\wsl\.localhost\\([^\\]+)\\(.*)$' -or
        $Path -match '^\\\\wsl\$\\([^\\]+)\\(.*)$') {
        $rest = $Matches[2] -replace '\\', '/'
        if ($rest) { return "/$rest" } else { return "/" }
    }
    # 盘符路径
    if ($Path -match '^[A-Za-z]:[\\/]') {
        return & wsl wslpath "$Path"
    }
    # 相对路径或其他
    return $Path
}

# WSL 路径 → Windows 路径
function ConvertTo-WindowsPath {
    param([string]$Path)
    if (-not $Path) { return $Path }
    if ($Path -match '^/') {
        return & wsl wslpath -w "$Path"
    }
    return $Path
}
```

⚠️ 实际实现需考虑 wslpath 调用的性能开销（每次 spawn wsl.exe 约 100-300ms）。对 daemon 翻译这种高频场景，应考虑：
- 缓存常见路径转换结果
- 或用纯字符串规则实现（不调 wslpath），仅对 /mnt/x/ 和 UNC 做字符串变换

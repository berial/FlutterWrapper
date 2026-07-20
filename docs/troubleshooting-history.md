# FlutterWrapper 问题排查记录

> 本文档按时间顺序记录项目从搭建至今遇到的所有运行时问题、根因分析与解决方案，供后续维护参考。

## 目录

- [Phase 1：路径转换](#phase-1路径转换)
- [Phase 2：UNC 路径与 mapped drive](#phase-2unc-路径与-mapped-drive)
- [Phase 3：Daemon TCP 模式稳定性](#phase-3daemon-tcp-模式稳定性)
- [Phase 4：包依赖与 AS 分析器](#phase-4包依赖与-as-分析器)
- [Phase 5：Web 设备发现](#phase-5web-设备发现)
- [Phase 6：Gradle 构建链](#phase-6gradle-构建链)
- [Phase 7：原生构建（NDK + CMake）](#phase-7原生构建ndk--cmake)
- [Phase 8：AS 分析器 package 路径（import 全红）](#phase-8as-分析器-package-路径import-全红)
- [附录：未解决问题](#附录未解决问题)

---

## Phase 1：路径转换

### 1.1 `Target file "lib\main.dart" not found`

**现象**：执行 `flutter run lib\main.dart` 时，WSL flutter 报找不到目标文件。

**根因**：Windows CMD 传给 wsl.exe 的参数保留了 Windows 反斜杠 `lib\main.dart`，WSL flutter 将其视为单个文件名而非路径。

**修复**：在 [bin/flutter.ps1](../bin/flutter.ps1) 和 [bin/dart.ps1](../bin/dart.ps1) 的 `ConvertTo-WslPath` 函数末尾添加规则：对包含反斜杠的相对路径，将 `\` 替换为 `/`。

```powershell
if ($Path -match '\\') {
    return ($Path -replace '\\', '/')
}
```

---

## Phase 2：UNC 路径与 mapped drive

### 2.1 `No pubspec.yaml file found`

**现象**：AS 启动 flutter.bat 时，CMD 无法将 UNC 路径（`\\wsl.localhost\Ubuntu-24.04\...`）作为当前目录，导致 flutter 找不到 pubspec.yaml。

**根因**：Windows CMD 不支持 UNC 作为 cwd。

**修复**：
1. 在 [install.ps1](../install.ps1) 中通过 `net use W: \\wsl.localhost\Ubuntu-24.04` 映射 W 盘
2. 在 [config/wrapper.yaml](../config/wrapper.yaml) 配置 `mappedDrive: W`
3. `ConvertTo-WslPath` 识别 `W:\...` 并转换为 `/...`

---

## Phase 3：Daemon TCP 模式稳定性

### 3.1 PowerShell 5.1 启动 wsl.exe daemon 时延迟 45 秒

**现象**：直接通过 PowerShell ProcessStartInfo 启动 wsl.exe daemon，TCP 端口 45 秒后才能接收数据；而 bash pipe 模式立即响应。

**根因**：怀疑是 wsl.exe 在 `RedirectStandardInput=true` 时检测到非交互终端，flutter daemon 内部初始化被阻塞。

**修复**：改用 TCP 文本模式架构（[bin/wrapper.ps1](../bin/wrapper.ps1)），两个 Runspace 分别处理输入/输出。

### 3.2 TCP EOF 后 wsl.exe 不退出

**现象**：daemon 关闭 TCP 连接后，wsl.exe 进程仍残留。

**根因**：TCP EOF 检测本身不足以终止进程。

**修复**：主线程在 `handle2.IsCompleted` 后主动调用 `$wslProc.Kill()`。

### 3.3 PowerShell 5.1 Stream 不可靠

**现象**：`[Console]::OpenStandardInput().Read()` 在宿主环境中阻塞；`OpenStandardOutput().Write()` 数据不到达父进程管道。

**根因**：PS 5.1 的 Stream API 在 stdin/stdout 被重定向时行为异常。

**修复**：改用 `[Console]::In`（TextReader）和 `[Console]::Out`（TextWriter）。

### 3.4 PowerShell `exit` 等待 Runspace 完成

**现象**：in-pump Runspace 阻塞在 `[Console]::In.ReadLine()`，`exit` 无法中断，导致进程挂起。

**修复**：使用 `[System.Environment]::Exit()` 强制终止进程，而非 `exit`。

详见 [docs/daemon.md §9.6](daemon.md)。

---

## Phase 4：包依赖与 AS 分析器

### 4.1 `package_config.json does not exist`（BOM 问题）

**现象**：`flutter run` 报 `.dart_tool/package_config.json does not exist`，但文件实际存在。

**根因**：PowerShell 5.1 的 `Set-Content -Encoding UTF8` 写入 UTF-8 BOM（`EF BB BF`），Dart JSON 解析器无法处理 BOM，报 "file does not exist"。

**修复**：改用 `[System.IO.File]::ReadAllBytes` 读取并手动剥离 BOM，用 `UTF8Encoding($false)` + `WriteAllText` 写入无 BOM UTF-8。

```powershell
$bytes = [System.IO.File]::ReadAllBytes($path)
if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    $bytes = $bytes[3..($bytes.Length - 1)]
}
$content = [System.Text.Encoding]::UTF8.GetString($bytes)
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($path, $content, $utf8NoBom)
```

### 4.2 WSL flutter 无法读取 Windows UNC 路径

**现象**：`flutter run` 报 `Error when reading '///wsl.localhost/Ubuntu-24.04/home/berial/.vfox/...'`。

**根因**：[flutter.ps1](../bin/flutter.ps1) 在 `pub get` 后将 `package_config.json` 中的 `file:///home/...` 翻译为 `file://///wsl.localhost/Ubuntu-24.04/home/...`（Windows UNC 格式），供 AS Windows Dart 分析器使用。但 WSL flutter 编译器无法读取 UNC 路径。

**修复**：双格式策略
- `pub get` 后保存 WSL 原始格式到 `.dart_tool/package_config.wsl.json`
- 主文件翻译为 Windows UNC 格式（供 AS 分析器）
- 非 `pub get` 命令运行前：备份 Windows 格式 → 用 WSL 格式覆盖主文件 → 运行 → 恢复 Windows 格式

### 4.3 `Target of URI doesn't exist` 错误

**现象**：AS 中所有依赖（如 `package:package_info_plus/package_info_plus.dart`）报 URI 不存在。

**根因**：`package_config.json` 未生成或格式错误（BOM/路径错误）。

**修复**：综合 4.1 和 4.2 的解决方案，确保 AS 分析器读到 Windows UNC 格式的 `package_config.json`。

---

## Phase 5：Web 设备发现

### 5.1 Edge (web) / Chrome (web) 不显示在设备列表（WSL 限制）

**现象**：`flutter devices` 只显示 `Linux (desktop)`，不显示 Edge/Chrome web 设备；Android Studio 的 Run/Devices 下拉同样缺 web 选项。

**根因**（确认，2026-07-20）：
- Flutter **只在 Windows/macOS 上注册 Edge 设备**；Linux（WSL）上根本不生成 `edge (web)` 设备类型 —— 平台硬限制，**Edge 永远不会出现在 WSL 列表**。
- WSL 内没装 Linux Chrome 时，`chrome (web)` 也不会出现。

**⚠️ 已证伪的旧方案**：早期在 [config/wrapper.yaml](../config/wrapper.yaml) 设 `chrome.executable: /mnt/c/.../msedge.exe` 并通过 WSLENV 注入 `CHROME_EXECUTABLE`。实测 `flutter doctor` 能认出 `[✓] Chrome - develop for the web`，但 **`flutter devices` 会卡死（>4.5 分钟超时）**——msedge 从 WSL 启动时不按 `--version` 静默退出，而是拉起完整 GUI 进程。故该注入**仅对 doctor 有效，不能用于设备发现**。代码目前仍注入此变量（见 [bin/flutter.ps1](../bin/flutter.ps1)），属历史遗留，需注意。

**实际可行路径**：
1. **`web-server` + 手动 Windows Edge（零安装，推荐）**：`flutter run -d web-server`（或 AS 自定义 Run Configuration 加 `-d web-server`），日志打印 `http://localhost:PORT`，在 Windows Edge 打开即可，热重载正常。依赖 WSL2 localhost 转发（Windows 默认开启）。注意 3.44.6 下 `flutter devices` 默认不列 `web-server`，需从终端/自定义配置启动。
2. **装 Linux Chromium（原生 web 下拉）**：WSL 内 `sudo apt install chromium-browser`，重启 AS 后下拉出现 `chrome (web)`（标签为 Chrome 非 Edge，同内核），窗口经 WSLg 显示在 Windows。

**Status**：平台限制，非 FlutterWrapper 缺陷。未计划伪造 edge 设备。

---

## Phase 6：Gradle 构建链

### 6.1 Gradle 下载超时（`Connection timed out`）

**现象**：`flutter run` 触发 gradle 下载时 `java.net.ConnectException: Connection timed out`，下载 gradle 发行版和依赖失败。

**根因**：WSL 代理 + Java TLS + dl.google.com 组合导致 TLS 握手失败。

**修复**：
1. 创建 [tools/init-mirror.gradle](../tools/init-mirror.gradle)，使用 `beforeSettings` hook 重定向到阿里云镜像
   - `dl.google.com` / `maven.google.com` → `maven.aliyun.com/repository/google`
   - `repo.maven.apache.org` / `repo1.maven.org` → `maven.aliyun.com/repository/public`
   - `plugins.gradle.org` → `maven.aliyun.com/repository/gradle-plugin`
2. 通过 [tools/setup-gradle-mirror.sh](../tools/setup-gradle-mirror.sh) 复制到 `~/.gradle/init.d/mirror.gradle`
3. 删除 `~/.gradle/gradle.properties` 中的代理设置（与阿里云镜像冲突）

### 6.2 init-mirror.gradle 闭包内 `project` 不可用

**现象**：`Could not get unknown property 'project' for repository container`。

**根因**：在 `beforeSettings` 闭包内使用 `project.ext.rewriteRepos`，但 `project` 在此上下文不可用。

**修复**：将闭包改为顶层 `def rewriteRepos`，通过 `delegate` 传递 repository handler。

### 6.3 init-mirror.gradle `settingsEvaluated` 太晚

**现象**：镜像重定向不生效，仍从 dl.google.com 下载。

**根因**：`settingsEvaluated` 在 plugin 解析后才执行，时机太晚。

**修复**：改用 `beforeSettings` hook（在 settings 脚本执行前介入）。

### 6.4 重复下载 gradle 发行版

**现象**：用户已有 Windows 的 `D:\Android\Gradle\wrapper\dists`，但 WSL 内重新下载。

**用户反馈**："为什么要下载gradle，不能使用win中的gradle吗路径是D:\Android\Gradle"

**修复**：创建 [tools/setup-gradle-share.sh](../tools/setup-gradle-share.sh)，软链接 `~/.gradle/wrapper/dists` → `/mnt/d/Android/Gradle/wrapper/dists`。同一份 gradle zip 含 `gradle`（bash）和 `gradle.bat`（Windows），可跨平台共享。

---

## Phase 7：原生构建（NDK + CMake）

### 7.1 `Ninja not found`

**现象**：`[CXX1416] Could not find Ninja on PATH or in SDK CMake bin folders`。

**根因**：WSL 内未安装 ninja。

**修复**：`sudo apt install -y ninja-build cmake`

### 7.2 `DioExceptionType` 代码错误

**现象**：项目代码 `switch` 语句缺少 case（与项目本身相关，非 FlutterWrapper 问题）。

**修复**：项目代码补充 switch case。

### 7.3 `cmake.exe` 无法执行

**现象**：`Cannot run program "/mnt/d/Android/Sdk/cmake/3.22.1/bin/cmake"` — Linux gradle 找到的是无扩展名路径，但 Windows SDK 只有 `cmake.exe`。

**根因**：Linux gradle/cmake 调用 cmake 时，AGP 给出的路径不带 `.exe` 后缀，WSL 无法执行 `.exe`（除非显式带后缀）。

**初步修复**：在 `~/.android-sdk-wsl/cmake/bin/` 创建符号链接指向 `/usr/bin/cmake` 和 `/usr/bin/ninja`，在 `local.properties` 添加 `cmake.dir`。

**最终修复**：用 `setup-wsl-ndk.sh` 在 WSL 内安装 Linux 原生 cmake 3.22.1（见 7.5）。

### 7.4 NDK 编译器识别失败

**现象**：`The C compiler identification is unknown` — Windows NDK 只有 `windows-x86_64` 工具链。

**根因**：Windows NDK 的编译器是 `.exe`，WSL Linux cmake 无法调用。

**修复**：用 [tools/setup-wsl-ndk.sh](../tools/setup-wsl-ndk.sh) 在 WSL 内安装 Linux NDK 28.2.13676358 + cmake 3.22.1 到 `~/.android-sdk-wsl/`。

### 7.5 flutter 覆盖 `sdk.dir` 指向 Windows SDK

**现象**：手动将 `local.properties` 的 `sdk.dir` 改为 WSL SDK，flutter 运行后被重写回 `/mnt/d/Android/Sdk`（Windows SDK），AGP 随后从 Windows SDK 查找 NDK 失败。

**根因**：flutter 的 `writeLocalProperties`（`gradle_utils.dart:1151`）每次运行用 `ANDROID_HOME` 环境变量的值重写 `sdk.dir`。

**初步尝试**：让 wrapper.ps1 注入 `ANDROID_HOME=<WSL SDK>`，但发现 WSL SDK 缺少 `platform-tools`（adb）和 `build-tools`（aapt2 等），导致 `flutter doctor` 报 `adb not found`。

**最终方案**：混合 SDK 配置
- `ANDROID_HOME` 继续指向 Windows SDK（提供 build-tools，已通过 shell 包装器调用 `.exe`）
- `ndk.dir`（local.properties）→ WSL Linux NDK（AGP 优先级最高，flutter 不重写此键）
- `cmake.dir`（local.properties）→ WSL Linux cmake（flutter 不重写此键）
- 通过 WSLENV 注入 `ANDROID_NDK_HOME`/`ANDROID_NDK_ROOT` 作为双保险

详见 [tools/fix-local-properties.sh](../tools/fix-local-properties.sh)。

### 7.6 CMake 仍带旧 NDK 路径（`-DANDROID_NDK=/mnt/d/Android/Sdk/...`）

**现象**：修改 `local.properties` 后，CMake 命令行仍带 `-DANDROID_NDK=/mnt/d/Android/Sdk/ndk/28.2.13676358`。

**根因**：`.cxx` 缓存目录中残留旧的 NDK 路径配置。

**修复**：清理所有 `.cxx` 缓存目录
- `<project>/android/.cxx`
- `<project>/build/jni`
- `~/.pub-cache/hosted/pub.dev/jni-*/android/.cxx`

### 7.7 CMake 编译器找不到（`is not a full path to an existing compiler`）

**现象**：
```
The CMAKE_C_COMPILER:
  /mnt/d/Android/Sdk/ndk/28.2.13676358/toolchains/llvm/prebuilt/linux-x86_64/bin/clang
is not a full path to an existing compiler tool.
```

**根因**：AGP 仍从 Windows SDK 查找 NDK（路径 `/mnt/d/Android/Sdk/ndk/...`），但该路径下只有 `windows-x86_64` 工具链，没有 `linux-x86_64`。

**修复**：
1. 确保 `local.properties` 中 `ndk.dir` 指向 WSL Linux NDK（`/home/berial/.android-sdk-wsl/ndk/28.2.13676358`）
2. 清理 `.cxx` 缓存（见 7.6）
3. 通过 [flutter.ps1](../bin/flutter.ps1) 和 [wrapper.ps1](../bin/wrapper.ps1) 注入 `ANDROID_NDK_HOME`/`ANDROID_NDK_ROOT` 环境变量，覆盖 AGP 的默认 NDK 查找逻辑

---

## Phase 8：AS 分析器 package 路径（import 全红）

### 8.1 `Target of URI doesn't exist` —— 项目可运行但 import 全红

**现象**：WSL 中的 Flutter 项目 `flutter run` 正常（编译器侧 WSL 路径解析 OK），但在 Android Studio 中所有 `package:xxx/...` import 报红色错误：

```
Target of URI doesn't exist: 'package:flutter/foundation.dart'. (Documentation)

Try creating the file referenced by the URI, or try using a URI for a file that does exist.
```

**根因**：AS Dart 分析器（Windows）读取项目的 `.dart_tool/package_config.json`，发现其中的包路径是 **WSL 原生格式**（`file:///home/berial/.pub-cache/...`），Windows dart.exe 无法访问 WSL 路径，导致所有 package 解析失败。

这是 [bin/flutter.ps1](../bin/flutter.ps1) 的「双格式切换策略」失效：`flutter run` 是长跑命令，用户点 AS Stop 按钮时 flutter.ps1 进程被强杀，post-run restore 块未执行，`package_config.json` 留在 WSL 格式。

**临时修复**：手动从 `.dart_tool/package_config.win.json`（备份文件）恢复：
```bash
cd <project>
cp .dart_tool/package_config.win.json .dart_tool/package_config.json
rm -f .dart_tool/package_config.win.json
```

### 8.2 双格式切换策略的脆弱性

**前置背景**：[bin/flutter.ps1](../bin/flutter.ps1) 原有的双格式策略：
- `pub get` 后保存 WSL 原始格式到 `.dart_tool/package_config.wsl.json`
- 主文件翻译为 Windows UNC 格式（供 AS 分析器）
- 非 `pub get` 命令运行前：备份 Windows 格式 → 用 WSL 格式覆盖主文件 → 运行 → 恢复 Windows 格式

**问题**：该策略对 `flutter run` 这类长跑命令极其脆弱：
1. **进程被强杀**：AS Stop 按钮杀整个进程树，`finally` 块和 post-run restore 都不执行
2. **崩溃路径不可控**：wsl.exe 异常退出、网络断开、电源中断等都会导致 swap 未恢复
3. **状态残留**：`.win.json` 残留在磁盘上，下次启动虽能自动恢复，但用户在两次启动之间看到红色 import

**曾尝试的加固**（未根本解决）：
- 启动时检测 `.win.json` 自动恢复（pre-run recovery）
- 用 `try/finally` 包裹 `$proc.WaitForExit()`
- 用 `[System.Environment]::Exit()` 替代 `exit`

这些措施只能保证「下次启动时恢复」，无法解决「run 期间 AS 分析器读到的就是 WSL 格式」这一根本问题。

### 8.3 符号链接方案（最终解决）

**核心思路**：让 WSL 内的 Dart 也能解析 Windows **映射盘符（mapped drive）** 格式的 file URI（`file:///w:/...`），从而**永远不需要 swap**。

**关键发现**：Dart 的 `Uri.parse` 把 `file:///w:/home/berial/...` 解析为路径 `/w:/home/berial/...`。只需在 WSL 根目录创建符号链接 `/w: -> /`（及大写 `/W:` 以兼容大小写），盘符路径就能解析到真实文件。

> 注：早期曾用 UNC 格式（`file://///wsl.localhost/<distro>/...`）配合 `/wsl.localhost/<distro> -> /` 符号链接，但 UNC 会触发 Windows analyzer 的 **Blaze workspace detector** 崩溃（`\\\\?\\UNC\\wsl.localhost\\blaze-out` 触发 `FileSystemException` errno 67），故最终改用映射盘符格式（[bin/flutter.ps1](../bin/flutter.ps1) §329 注释有说明）。[tools/setup-wsl-symlink.sh](../tools/setup-wsl-symlink.sh) 现已同时建两套符号链接（`/w:`、`/W:` 及 legacy `/wsl.localhost/<distro>`），双格式都兼容。

**验证**：
```dart
// test_uri.dart
import 'dart:io';
void main() {
  var uri = Uri.parse(
    'file://///wsl.localhost/Ubuntu-24.04/home/berial/.pub-cache/hosted/pub.dev/archive-4.0.9/lib/archive.dart',
  );
  var file = File.fromUri(uri);
  print('path: ${file.path}');
  print('exists: ${file.existsSync()}');  // true（符号链接后）
}
```

**修复**：

1. 创建 [tools/setup-wsl-symlink.sh](../tools/setup-wsl-symlink.sh)，在 WSL 内执行（同时建双格式符号链接）：
   ```bash
   sudo mkdir -p /w:
   sudo ln -sfn /home /w:/home     # 小写（flutter.ps1 生成的 file:///w:/... 用 .ToLower()）
   sudo ln -sfn /home /W:/home     # 大写（兼容潜在大写形式）
   # 另建 legacy /wsl.localhost/<distro> -> / 以兼容 UNC 格式
   ```

2. 简化 [bin/flutter.ps1](../bin/flutter.ps1)：
   - **移除** pre-run swap、post-run restore、pre-run recovery 三段逻辑
   - **移除** `$pkgConfigWslPath`、`$pkgConfigWinPath`、`$swappedToWsl` 变量
   - **保留** `pub get` 后的翻译（WSL 格式 → **映射盘符 W: 格式** `file:///w:/...` + 去 BOM）
   - `package_config.json` 永远是映射盘符格式，AS 分析器和 WSL flutter 编译器读同一个文件（WSL 侧经 `/w:` 符号链接解析）

**效果**：
- `package_config.json` 永远是映射盘符（W:）格式
- AS 分析器和 WSL flutter 编译器读同一个文件
- `flutter run` 被强杀不再导致 import 变红
- 不再需要 `.wsl.json` / `.win.json` 备份文件
- WSL 侧所有 run/build（含 web）路径解析正常（依赖 `/w:` 符号链接）

**注意事项**：
- 符号链接需要 sudo 创建，WSL 重启后保留（写入根目录，非 tmpfs）
- **安装时已自动配置**：[install.ps1](../install.ps1) Step 7c 会调用 `setup-wsl-symlink.sh` 建好符号链接（sudo 失败时会提示手动跑）
- 若映射盘符变化（默认 `W`），需重跑脚本并传新盘符：`bash setup-wsl-symlink.sh <distro> <drive>`
- 若 Dart SDK 升级后 URI 解析行为变化，需重新验证

---

## 附录：未解决问题

### A.1 sdkmanager 无法下载 manifest

**现象**：WSL 内执行 `sdkmanager "platform-tools"` 报 `Failed to download any source lists`。

**根因**：sdkmanager 使用 Java HTTP 客户端，不读 `HTTP_PROXY` 环境变量；即使通过 `JAVA_TOOL_OPTIONS` 传入代理，Java HTTPS 证书验证仍可能失败。

**影响**：无法在 WSL SDK 补装 `platform-tools`/`build-tools`（Linux 版）。当前通过 Windows SDK + shell 包装器绕过。

**潜在解决方案**：
- 手动 curl 下载 zip 包解压
- 配置 Java 信任代理证书
- 使用国内镜像源（如清华 TUNA）

### A.2 手动测试未覆盖

以下场景需要真机/模拟器验证：
- `flutter run` 热重载
- `flutter run` 调试断点
- `flutter build apk --release`
- AS 中点击 Run 按钮的完整流程

---

## 修改文件清单

本次问题排查过程中修改/创建的主要文件：

| 文件 | 用途 |
|------|------|
| [bin/flutter.ps1](../bin/flutter.ps1) | 路径转换、BOM 安全、package_config 翻译、WSLENV 注入（含 NDK） |
| [bin/wrapper.ps1](../bin/wrapper.ps1) | Daemon TCP 模式、TextReader/TextWriter、WSLENV 注入（含 NDK） |
| [bin/dart.ps1](../bin/dart.ps1) | 路径转换（反斜杠 → 正斜杠） |
| [config/wrapper.yaml](../config/wrapper.yaml) | mappedDrive、chrome.executable、android.wslSdkPath |
| [install.ps1](../install.ps1) | W 盘映射、Chrome/Edge 检测 |
| [tools/setup-gradle-share.sh](../tools/setup-gradle-share.sh) | 共享 Windows gradle dists |
| [tools/init-mirror.gradle](../tools/init-mirror.gradle) | 阿里云 Maven 镜像重定向 |
| [tools/setup-gradle-mirror.sh](../tools/setup-gradle-mirror.sh) | 安装 init.d/mirror.gradle |
| [tools/setup-wsl-ndk.sh](../tools/setup-wsl-ndk.sh) | WSL 内安装 Linux NDK + cmake |
| [tools/setup-local-properties.sh](../tools/setup-local-properties.sh) | 添加 cmake.dir 到 local.properties |
| [tools/fix-local-properties.sh](../tools/fix-local-properties.sh) | 混合 SDK 配置 + 清理 .cxx 缓存 |
| [tools/setup-wsl-symlink.sh](../tools/setup-wsl-symlink.sh) | 创建 `/wsl.localhost/<distro>` 符号链接（UNC 路径解析） |
| [tools/test_uri.dart](../tools/test_uri.dart) | 验证 Dart URI 解析行为（诊断脚本） |

---

## 关键经验总结

1. **PowerShell 5.1 编码陷阱**：`Set-Content -Encoding UTF8` 写入 BOM，破坏 Dart/JSON 解析。始终用 `[System.IO.File]::WriteAllText` + `UTF8Encoding($false)`。

2. **WSL 环境变量转发**：`wsl.exe` 不转发 Windows 进程环境变量，必须通过 `WSLENV` 声明（`/u` 后缀做路径转换）。

3. **AGP NDK 查找优先级**：`ndk.dir`（local.properties）> `ANDROID_NDK_HOME`（env）> `sdk.dir/ndk/<ver>`。用 `ndk.dir` 最稳定（flutter 不重写此键）。

4. **Windows SDK + WSL 混合架构**：
   - build-tools 的 `.exe` 可通过 shell 包装器（`aapt2` shell 脚本调用 `aapt2.exe`）在 WSL 内执行
   - NDK/cmake 必须用 Linux 原生版本（`.exe` 无法被 Linux cmake/ninja 调用）
   - `local.properties` 是混合配置的关键：`sdk.dir` 给 Windows SDK，`ndk.dir`/`cmake.dir` 给 WSL SDK

5. **.cxx 缓存陷阱**：AGP 的 `.cxx` 目录缓存 NDK 路径，修改 NDK 配置后必须清理 `<project>/android/.cxx`、`<project>/build/jni`、`~/.pub-cache/hosted/pub.dev/jni-*/android/.cxx`。

6. **Gradle init.d 时机**：`settingsEvaluated` 太晚（plugin 解析后），用 `beforeSettings` 才能在 plugin 仓库解析前介入。

7. **package_config.json 路径统一**：采用映射盘符（W:）格式 `file:///w:/...`（而非 UNC），配合 WSL 内 `/w:`、`/W:` → 根目录的符号链接，让 WSL Dart 能解析 Windows 盘符形式的 file URI，一份文件同时满足 AS 分析器（Windows）和 flutter 编译器（WSL）。避免双格式 swap 策略对长跑命令（`flutter run`）的脆弱性。UNC 格式因触发 Windows analyzer 的 Blaze workspace detector 崩溃（errno 67）被放弃。

8. **长跑命令与进程强杀**：`flutter run` 是长跑命令，AS Stop 按钮会杀整个进程树，`finally` 块和 post-run restore 都不执行。设计任何 swap/restore 机制时，必须假设进程可能在任意时刻被杀，要么用原子操作，要么用启动时恢复，最好直接避免 swap。

9. **Dart URI 解析行为**：`file:///w:/home/...` 会被 Dart 解析为 `/w:/home/...`（绝对路径），经 `/w: -> /` 符号链接即可映射到真实文件；同理 `file://///host/path`（5 斜杠）解析为 `/host/path`。这让我们能用符号链接把盘符/UNC 路径映射到本地路径。

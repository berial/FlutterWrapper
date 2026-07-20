# 风险清单与缓解措施

> 基于 Phase 0 调研结果，按严重程度排序。

## P0 - 阻塞性风险

### R1. ~~WSL 侧未安装 Flutter~~ ✅ 已解决

**复探结论**：WSL 内已通过 vfox 安装 Flutter 3.41.9 (stable) / Dart 3.11.5。
- 实际路径：`~/.vfox/sdks/flutter/bin/flutter`（符号链接 → `~/.vfox/cache/flutter/v-3.41.9/flutter-3.41.9/`）
- vfox 全局配置 `~/.vfox/.vfox.toml` 设定 `flutter = "3.41.9"`
- **重要陷阱**：vfox 激活只在 `~/.zshrc` 里（`eval "$(vfox activate zsh)"`），bash 非 zsh 交互模式下 flutter **不在 PATH**。初次探测用 `bash -lc` 导致 `which flutter` 为空，误判为未安装。

**对 wrapper 的影响**：
- `wrapper.yaml` 里 `flutter.executable` 必须用**绝对路径**（`/home/berial/.vfox/sdks/flutter/bin/flutter`），不能依赖 PATH
- 或 wrapper 调用时强制走 zsh：`wsl.exe -d Ubuntu-24.04 --shell-type zsh -e flutter`，但会增加开销，不推荐
- 绝对路径方案还有个好处：vfox 切换版本时符号链接自动更新，wrapper 配置无需改

### R2. Dart 分析服务器路径不匹配（最大技术风险）— 验证完成 ✅

**现象**：
- JetBrains Dart 插件在 **Windows 侧** 直接 spawn `bin/cache/dart-sdk/bin/dart.exe` 启动分析服务器
- 分析服务器读取项目的 `.dart_tool/package_config.json` 获取包路径
- 但 `package_config.json` 由 WSL 侧 `flutter pub get` 生成，包路径是 **WSL 路径**（如 `/home/berial/.pub-cache/hosted/pub.flutter-io.cn/...`、`/mnt/d/flutter/packages/flutter/lib/`）
- Windows 的 dart.exe **无法直接访问 WSL 路径**（除非走 UNC `\\wsl.localhost\...`，但 Dart 分析服务器可能不支持 UNC）

**影响**：
- 代码补全失效（找不到 Flutter 框架包）
- 错误检查误报（无法解析 import）
- 代码索引不完整

**验证结果（2026-07-17）**：
- R2a：在 WSL 建 `~/r2_test` Flutter 项目，`flutter pub get` 成功，生成 `.dart_tool/package_config.json`
- R2b：路径格式确认：
  - pub-cache 包：`file:///home/berial/.pub-cache/hosted/pub.flutter-io.cn/<pkg>-<ver>/`
  - flutter SDK 包：`file:///home/berial/.vfox/cache/flutter/v-3.41.9/flutter-3.41.9/packages/flutter`
  - 项目自身：`file:///home/berial/r2_test/lib/`
  - **全部是 WSL 路径**，Windows dart.exe 无法直接访问
- R2c：从 Windows 侧 UNC 访问 `\\wsl.localhost\Ubuntu-24.04\home\berial\.pub-cache\hosted\pub.flutter-io.cn\` 成功，能列出 `webview_flutter_web-0.2.3+4` 等包目录。**UNC 访问可行**。
- **结论**：R2 是真实问题（dart.exe 直接读 `file:///home/...` 会失败），但 UNC 缓解方案可行 — 把 `file:///home/berial/.pub-cache/...` 翻译成 `file://wsl.localhost/Ubuntu-24.04/home/berial/.pub-cache/...`

**缓解方案**（Phase 6 实现时采用）：
1. **方案 A：post-process package_config.json（推荐）**。wrapper 在 `flutter pub get` 执行后，自动把生成的 `.dart_tool/package_config.json` 里的 `file:///home/...` 翻译成 `file://wsl.localhost/Ubuntu-24.04/home/...`。已验证 UNC 路径 Windows 可访问。
2. **方案 D（备选）**：项目放 Windows 盘（`D:\workspace\demo`），WSL 通过 `/mnt/d/workspace/demo` 访问。项目路径会变成 `file:///mnt/d/...`，翻译成 `file:///D:/...`；但 pub-cache 路径仍是 WSL 路径，仍需方案 A 翻译。
3. 方案 B/C（独立 pub get / UNC PUB_CACHE）已弃用：维护成本高、易不一致。
4. **最终验证项**（Phase 6）：用真实 Windows Dart SDK + 翻译后的 package_config.json，确认 JetBrains Dart 插件能正确解析 import / 补全。

### R3. PowerShell 的二进制/编码安全 — 验证完成 ✅

**现象**：
- daemon 协议是 `[{json}]\n` + 可选二进制帧
- Flutter/Dart 输出大量 UTF-8（中文日志、emoji、source maps）
- PowerShell 默认编码不是 UTF-8，`[Console]::In/Out`、`$input`、字符串管道会破坏多字节字符和二进制

**影响**：
- daemon JSON 解析失败（UTF-8 多字节被截断）
- 中文日志乱码
- 二进制段损坏（proxy 域）
- stdin 卡死（编码不匹配导致管道阻塞）

**验证结果（2026-07-17）**：脚本 `tools/r3-byte-stream-test.ps1`，三项全部 PASS：
- **Test 1 UTF-8 字节透传**：WSL 用 `printf` 输出 `chinese:中文 emoji:joy`（24 字节，含 UTF-8 多字节 `e4 b8 ad e6 96 87`），PowerShell 通过 `Process.StandardOutput.BaseStream.CopyTo(MemoryStream)` 原始字节流接收，逐字节比对完全一致（24/24）。
- **Test 2 daemon 帧解析**：构造 `[{"event":"app.start","params":{"appId":"x1","directory":"/home/berial/demo"}}]\n` 帧，通过 UNC 写到 `/tmp/r3frame.json`（避开 shell 引用问题），再让 WSL `cat` 出来经字节流到 PowerShell，正则提取 JSON 后 `ConvertFrom-Json` 成功取到 `directory = /home/berial/demo`。
- **Test 3 二进制帧边界**：构造 `[{"id":"1","_binaryLength":5}]\n` + 5 字节二进制 payload `ABCDE`，PowerShell 字节流接收后用 `[Array]::IndexOf(..., 0x0a)` 定位 LF 边界，正确分离 JSON 行与二进制段，`_binaryLength=5` 与实际 5 字节 payload 匹配。

**结论**：PowerShell 通过 `System.Diagnostics.Process` + `BaseStream` 字节流转发**完全可行**：
- UTF-8 多字节字符字节级完整保留
- daemon `[{json}]\n` 帧可正确解析
- 二进制帧边界（`_binaryLength`）可正确识别
- **不需要迁移到 C#/.NET**，纯 PowerShell 即可胜任 daemon 翻译

**实现要点**（Phase 4 wrapper 编写时遵循）：
- **必须**设置 `[Console]::OutputEncoding = [System.Text.Encoding]::UTF8`
- daemon 翻译**必须用原始字节流**（`Process.StandardInput.BaseStream` / `Process.StandardOutput.BaseStream`），**不能用字符串管道**
- 用 `MemoryStream` 或固定大小 buffer 做字节级读写循环
- 字符串解析仅在需要翻译路径时进行，翻译后立即转回字节
- 通过 UNC 写文件（`\\wsl.localhost\<distro>\tmp\...`）传复杂参数可避开 shell 引用地狱

**Phase 4 实战发现（2026-07-17）**：
- `Get-Content` 读取 UTF-8 without BOM 文件时，PS 5.1 默认用系统编码（GBK）。中文字符的 UTF-8 字节在 GBK 解码时可能"吃掉"相邻的换行符（GBK 把 UTF-8 续字节和 `\n` 组合成无效序列，整体替换），导致注释行与下一行 `key: value` 合并成一行，YAML 解析失败。
- **修复**：`Get-Content -Path $Path -Encoding UTF8` 强制 UTF-8 读取。
- 普通命令转发（非 daemon）用 `& wsl.exe @args` 直接调用即可，wsl.exe 继承父进程 Console IO，UTF-8 字节不被 PS 介入，安全。

## P1 - 重要风险

### R4. daemon 路径翻译的完备性

**现象**：调研确认了当前 `main` 分支的路径字段，但：
- Flutter 版本演进可能新增路径字段
- 旧版/新版 Flutter daemon 协议可能有差异
- `flutter run --machine` 和 `flutter daemon` 的消息流可能不完全一致

**影响**：未翻译的路径字段会导致 Android Studio 拿到 WSL 路径，无法访问，功能失效。

**缓解**：
- wrapper 对**未知消息**原样透传（不阻塞通信）
- 翻译失败时原样透传 + 写 warning 日志
- Phase 6 测试矩阵覆盖所有 daemon 相关功能（hot reload / debug / devices）
- 日志记录所有未识别的带路径字段，便于后续补充翻译规则

### R5. wsl.exe 启动开销

**现象**：每次 `wsl.exe` 调用有启动开销（约 100-300ms），用于：
- 进程创建
- WSL 互操作层初始化
- PATH 环境变量转换

**影响**：
- 高频短命令（如 `flutter --version` 多次调用）累积延迟明显
- Android Studio 启动时可能调用多次 `flutter --version` / `doctor`，体验变慢

**缓解**：
- daemon 是长进程，启动一次后持续运行，无重复开销
- 普通命令的 wsl.exe 开销无法避免，但可：
  - 缓存 `flutter --version` 输出（Android Studio 多次调用时直接返回缓存）
  - 但缓存可能导致版本检测不准，谨慎使用
- 长期方案：C# wrapper 常驻进程，复用 WSL 互操作层

### R6. Windows Dart SDK 与 WSL Flutter 版本不一致

**现象**：
- `bin/cache/dart-sdk/` 是独立下载的 Windows Dart SDK
- WSL 侧 Flutter 3.41.9 捆绑 Dart 3.11.5
- 若 Windows Dart SDK 版本 ≠ 3.11.5，分析与运行可能不一致

**影响**：分析与运行不一致，开发体验差。

**缓解**：
- Windows 侧下载 **Dart 3.11.5 (stable) Windows 版**（与 WSL 一致）
- 安装脚本（Phase 10）从 WSL 读 `flutter --version --machine` 的 `dartSdkVersion` 字段获取版本
- 提供版本同步检查命令（`wrapper.ps1 --check-version`）

### R7. UNC 路径的性能

**现象**：WSL2 通过 9P 协议访问 Windows 文件系统（`/mnt/d/...`），反向 Windows 通过 UNC `\\wsl.localhost\...` 访问 WSL 文件系统。两个方向的性能都**显著低于原生**：
- `/mnt/d/` 读写比 ext4 慢 3-5 倍
- `\\wsl.localhost\` 读写比 NTFS 慢 5-10 倍

**影响**：
- 项目放在 `/mnt/d/`（Windows 盘）→ WSL 侧 `flutter pub get` / `build` 慢
- 项目放在 WSL 内 → Windows 侧 dart.exe 分析服务器访问慢

**缓解**：
- **推荐项目放在 WSL 内**（`/home/berial/projects/`），WSL 侧 flutter 全速运行
- 接受 Windows 侧分析服务器走 UNC 的性能损耗（分析服务器主要读源码，I/O 量可控）
- 或项目放 `/mnt/d/`（Windows 盘），接受 WSL 侧 flutter 的 I/O 损耗，换取 Windows 侧分析服务器原生速度
- 权衡取决于开发模式（频繁 build 还是频繁分析）

### R8. `flutter run --machine` 的调试通道 — 验证完成 ✅

**现象**：
- `flutter run --machine` 通过 daemon 协议输出 app 事件
- 调试时 vmService URI 走 `app.debugPort.wsUri`（`ws://127.0.0.1:<port>/<token>`）
- WSL2 默认 localhost forwarding 通常能让 Windows 访问 WSL 的 127.0.0.1
- 但**某些 WSL2 配置下 localhost forwarding 失效**（如 mirrored network mode、企业网络策略）

**影响**：Android Studio 无法连接 VM service，调试/hot reload 失效。

**验证结果（2026-07-17）**：脚本 `tools/r8-localhost-forwarding-test.ps1`，三项全部 PASS：
- **网络模式探测**：用户 `.wslconfig` 配置 `networkingMode=mirrored`（非默认 NAT）
- **Test 1 HTTP 跨 OS**：WSL 内 `python3 -m http.server 18765 --bind 127.0.0.1`，Windows 侧 `Invoke-WebRequest http://127.0.0.1:18765/` 返回 HTTP 200。**Windows → WSL 127.0.0.1 跨 OS HTTP 可达**。
- **Test 2 WebSocket 跨 OS**：WSL 内用 Dart 写的 WebSocket echo server（`HttpServer.bind(InternetAddress.loopbackIPv4, 18766)`，正是 `flutter run` 启动 VM service 的方式），Windows 侧 .NET `ClientWebSocket.ConnectAsync("ws://127.0.0.1:18766/")` 成功连上，发 `ping` 收 `echo:ping`。**VM service WebSocket 通道可用**。
- **Test 3 WSL 自环**：WSL 内 curl 自己的 127.0.0.1 返回 200。

**关键发现**：
- **mirrored 网络模式下，WSL 服务必须 bind 到 `127.0.0.1`（loopback），不能 bind 到 `0.0.0.0`**。bind 到 0.0.0.0 不会获得 mirrored loopback forwarding，Windows 侧无法通过 127.0.0.1 访问。
- 这点与 NAT 模式相反（NAT 模式下 localhostForwarding=true 会把 WSL 的 0.0.0.0 端口映射到 Windows 127.0.0.1）。
- `flutter run` 在 WSL 内启动 VM service 时默认 bind 127.0.0.1，**正好符合 mirrored 模式要求**，无需额外处理。

**结论**：
- vmService URI `ws://127.0.0.1:<port>/<token>` 可直接被 Android Studio (Windows) 访问
- **不需要做 URI 翻译**，wrapper 原样透传 `app.debugPort.wsUri` 即可
- R13（网络模式变化）也同步解决：mirrored 模式 + bind 127.0.0.1 是正确组合

**实现要点**（Phase 4 daemon 翻译编写时遵循）：
- daemon 事件 `app.debugPort.wsUri` / `app.devTools.uri` **原样透传**，不翻译 host
- 安装脚本（Phase 10）检测 `.wslconfig`，若为 NAT 模式需确认 `localhostForwarding=true`（默认），若为 mirrored 模式直接 OK
- 文档提示用户：mirrored 模式下不要 bind 0.0.0.0，但这是 Flutter 默认行为，通常无需干预

## P2 - 一般风险

### R9. 多 daemon 实例冲突

**现象**：Android Studio 可能启动多个 daemon 进程（不同 project、重启 daemon）。

**影响**：wrapper 需正确处理多进程，每个 daemon 独立翻译。

**缓解**：
- 每个 `flutter.bat daemon` 调用独立 spawn wsl.exe，独立翻译
- 无共享状态，天然支持多实例

### R10. Windows 路径大小写

**现象**：Windows 路径大小写不敏感，WSL 路径大小写敏感。`D:\Android\demo` → `/mnt/d/Android/demo`，若 WSL 实际是 `/mnt/d/android/demo`（小写），转换后找不到。

**影响**：罕见，但项目目录名大小写不一致时会出问题。

**缓解**：
- 转换后用 `wsl test -d` 验证路径存在
- 或用 `realpath` 解析实际路径
- 文档建议用户保持 Windows 和 WSL 路径大小写一致

### R11. 配置文件缺失或错误

**现象**：`config/wrapper.yaml` 配置错误（distro 名写错、Flutter 路径不对）。

**影响**：wrapper 调用失败，错误信息可能不清晰。

**缓解**：
- wrapper 启动时校验配置
- 提供 `wrapper.ps1 --check` 自检命令
- 错误信息明确指出哪个配置项有问题

### R12. Android Studio / Flutter Plugin 版本演进

**现象**：
- flutter-intellij 插件持续演进，校验逻辑、命令调用可能变化
- 新版可能增加校验文件、改变版本读取方式、新增命令

**影响**：wrapper 对新插件版本可能失效。

**缓解**：
- 文档记录调研时的插件版本（main 分支 2026-07-14）
- Phase 9 测试矩阵在多个插件版本上验证
- 关注 flutter-intellij 的 release notes

### R13. WSL2 网络模式变化 — 已在 R8 验证中解决 ✅

**现象**：WSL2 有两种网络模式：
- NAT 模式（默认，localhost forwarding）
- Mirrored 模式（Windows 11 22H2+，`.wslconfig` 里 `networkingMode=mirrored`）

mirrored 模式下 localhost 行为不同，可能影响 vmService URI 连接。

**用户环境**：`networkingMode=mirrored`（见 R8 验证）。

**结论**：mirrored 模式 + bind 127.0.0.1 已验证可工作（R8 Test 1/2 PASS）。详见 R8 章节。

**缓解**：
- 安装脚本检测 `.wslconfig` 网络模式
- 两种模式都可工作：NAT 需 `localhostForwarding=true`（默认），mirrored 需 bind 127.0.0.1（Flutter 默认行为）
- 文档说明两种模式差异

## 风险矩阵

| ID | 风险 | 严重度 | 概率 | 阶段 |
|---|---|---|---|---|
| R1 | ~~WSL 未装 Flutter~~ | ✅ 已解决 | — | Flutter 3.41.9 已装 |
| R2 | ~~Dart 分析服务器路径不匹配~~ | ✅ 已验证 | — | UNC 翻译可行，Phase 6 落地 |
| R3 | ~~PowerShell 二进制/编码安全~~ | ✅ 已验证 | — | 纯 PS 即可，无需 C# |
| R4 | daemon 路径翻译完备性 | P1 | 中 | Phase 6 |
| R5 | wsl.exe 启动开销 | P1 | 高 | 全程 |
| R6 | Dart SDK 版本不一致 | P1 | 中 | Phase 10 |
| R7 | UNC/mnt 性能 | P1 | 高 | 全程 |
| R8 | ~~调试通道 WSL2 网络~~ | ✅ 已验证 | — | mirrored + 127.0.0.1 可行 |
| R9 | 多 daemon 实例 | P2 | 低 | 天然解决 |
| R10 | 路径大小写 | P2 | 低 | 文档提示 |
| R11 | 配置错误 | P2 | 中 | Phase 2/10 |
| R12 | 插件版本演进 | P2 | 中 | 持续 |
| R13 | ~~WSL2 网络模式~~ | ✅ 已验证 | — | 随 R8 解决 |

## 最优先验证项 — 全部完成 ✅

进入 Phase 1 之前的最小原型验证已全部通过（2026-07-17）：

1. ✅ **R2 验证**（package_config.json 路径格式 + UNC 访问）：
   - 路径格式确认为 `file:///home/berial/.pub-cache/...` 和 `file:///home/berial/.vfox/cache/flutter/...`
   - Windows 侧 UNC 访问 `\\wsl.localhost\Ubuntu-24.04\home\berial\.pub-cache\` 成功
   - 结论：post-process 翻译方案可行（Phase 6 实现时落地）
2. ✅ **R3 验证**（PowerShell 字节流转发）：
   - UTF-8 字节透传 24/24 字节匹配
   - daemon `[{json}]\n` 帧解析成功，路径字段提取正确
   - 二进制帧边界（`_binaryLength`）识别正确
   - 结论：纯 PowerShell 可胜任 daemon 翻译，无需迁移 C#
3. ✅ **R8 验证**（WSL2 localhost forwarding）：
   - 用户环境 `networkingMode=mirrored`
   - HTTP 跨 OS（Windows → WSL 127.0.0.1:18765）PASS
   - WebSocket 跨 OS（Windows → WSL ws://127.0.0.1:18766）PASS，echo roundtrip 成功
   - 结论：vmService URI 原样透传即可，无需翻译 host

**三大假设全部验证通过，可以进入 Phase 1 目录结构搭建。**

剩余风险（R4/R5/R6/R7）均为性能或实现细节问题，不构成阻塞，在后续 Phase 逐步处理。

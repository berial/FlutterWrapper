# Flutter Daemon 协议与路径翻译策略

> 调研来源：`flutter/flutter` 仓库 `main` 分支（2026-07-17 实际抓取）。关键文件：
> - 传输层：`packages/flutter_tools/lib/src/daemon.dart`
> - 命令入口 + 全部 Domain 逻辑：`packages/flutter_tools/lib/src/commands/daemon.dart`（1873 行）
>
> ⚠️ 旧版 `src/daemon/{app,device,emulator}.dart` 子目录在当前 `main` 已**不存在**，调研时若用旧 URL 会 404。

## 1. 协议入口

- **命令**：`flutter daemon`（`DaemonCommand`，`src/commands/daemon.dart:41`）
- **协议版本**：`const protocolVersion = '0.6.1'`（`daemon.dart:34`）
- **两种运行模式**：
  1. **stdio 模式**（默认）：读 stdin / 写 stdout
  2. **TCP 模式**：`flutter daemon --listen-on-tcp-port=<port>`，绑 loopback IPv4（失败回退 IPv6），每个 socket 连接创建一个独立 `Daemon` 实例
- **机器模式**：`flutter run --machine` / `flutter attach --machine` 通过 `Daemon.createMachineDaemon()`（`daemon.dart:173`）创建 `logToStdout: true` 的 daemon，这是 IDE 调试 app 的实际通道

## 2. 消息格式（wire format，最关键）

**不是**纯换行分隔的裸 JSON，也**不是**长度前缀。源码注释和实现明确：

```
每条消息 = [{<JSON 对象>}]\n
```

- 每行是一个 **JSON 数组，数组里恰好一个对象**
- 以 `[` 开头（实际匹配 `[{`）、`]` 结尾（匹配 `}]`），以 `\n`（LF=10）结尾
- 发送方（`DaemonStreams.send`，`daemon.dart:182`）：
  ```dart
  _outputSink.add(utf8.encode('[${json.encode(message)}]\n'));
  ```
- 接收方（`DaemonInputStreamConverter`，`daemon.dart:47`）：按 LF 切行，剥掉外层 `[ ]`，`json.decode` 得到对象

### 2.1 二进制扩展（重要）

若 JSON 对象含字段 `"_binaryLength": N`（整数），则**紧跟在该 `\n` 之后的 N 个原始字节**是该消息的二进制载荷。状态机在 `json` / `binary` 间切换（`daemon.dart:83-96`）：

```
[{...,"_binaryLength":N}\n]<N 字节原始二进制>
```

然后状态机切到 binary 模式读取 N 字节。

### 2.2 编码

- 所有 JSON 文本用 **UTF-8** 编码（`utf8.encode`）
- 换行符是 **LF (10)**，**不是 CRLF**
- Windows 下注意不要让文本模式把 `\n` 转成 `\r\n` 污染二进制段

## 3. 请求格式（client → daemon）

```json
[{"id":"<string>","method":"<domain>.<name>","params":{...}}]
```

- `id`：字符串（`DaemonConnection.sendRequest` 用 `'${++_outgoingRequestId}'`，`daemon.dart:238`）。对 daemon 是 opaque
- `method`：`domain.name` 形式，按 `.` 拆分路由到对应 `Domain`（`daemon.dart:213-220`）
- `params`：可选对象。类型校验在 `Domain._getStringArg/_getBoolArg/_getIntArg`

### 3.1 关键方法清单

| 方法 | 参数 | 说明 |
|---|---|---|
| `daemon.version` | — | 返回 `"0.6.1"` |
| `daemon.shutdown` | — | `Timer.run(daemon.shutdown)`，异步关闭 |
| `daemon.getSupportedPlatforms` | **`projectRoot`(必填,String)** | 返回 `{platforms:[...], platformTypes:{...}}` |
| `daemon.setNotifyVerbose` | `verbose`(bool) | 开启 verbose 日志转发 |
| `device.getDevices` | — | 返回设备列表 |
| `device.discoverDevices` | `timeoutInMilliseconds`(int) | 重新发现设备 |
| `device.enable` / `device.disable` | — | 启停设备轮询（触发 added/removed 事件） |
| `device.forward` / `device.unforward` | `deviceId`,`devicePort`,`hostPort` | 端口转发 |
| `device.supportsRuntimeMode` | `deviceId`,`buildMode` | |
| `device.uploadApplicationPackage` | `targetPlatform`,`applicationBinary`(temp相对名) | 返回 `application_package_id` |
| `device.logReader.start` / `logReader.stop` | `deviceId` / `id` | |
| `device.startApp` | `deviceId`,`applicationPackageId`,`debuggingOptions`,`mainPath`,**`route`,`platformArgs`,`prebuiltApplication`,`userIdentifier`** | 返回 `{started, vmServiceUri}` |
| `device.stopApp` | `deviceId`,`applicationPackageId?` | |
| `device.takeScreenshot` | `deviceId` | 返回 base64 字符串 |
| `device.startDartDevelopmentService` | `deviceId`,`vmServiceUri`,`disableServiceAuthCodes`,`enableDevTools`,`devToolsServerAddress` | 返回 `{ddsUri, devToolsUri, dtdUri}` |
| `device.shutdownDartDevelopmentService` | `deviceId` | |
| `device.getDiagnostics` | — | |
| `device.startVMServiceDiscoveryForAttach` / `stopVMServiceDiscoveryForAttach` | `deviceId`,`appId?`,`fuchsiaModule?`,`filterDevicePort?`,`ipv6?` | 触发 `device.VMServiceDiscoveryForAttach.<id>` 事件 |
| `emulator.getEmulators` | — | 返回 `[{id,name,category,platformType}]` |
| `emulator.launch` | `emulatorId`(必填),`coldBoot`(bool) | |
| `emulator.create` | `name?` | 返回 `{success,emulatorName,error}` |
| `devtools.serve` | — | 返回 `{host, port}` |
| `app.restart` | `appId`(必填),`fullRestart`(bool),`pause`,`reason`,`debounce`,`debounceDurationOverrideMs` | **热重载 = `fullRestart:false`；热重启 = `fullRestart:true`** |
| `app.callServiceExtension` | `appId`(必填),`methodName`,`params` | VM service 扩展调用 |
| `app.stop` | `appId`(必填) | |
| `app.detach` | `appId`(必填) | |
| `proxy.writeTempFile` / `updateFile` / `write` | `path`(temp相对) + 二进制流 | 带二进制 |
| `proxy.calculateFileHashes` | `path`,`cacheResult` | |
| `proxy.connect` | `port`(int) | 返回 id；触发 `proxy.data.<id>` 二进制事件 |
| `proxy.disconnect` | `id` | |

### 3.2 重要纠正（与直觉不同的点）

- **没有 `daemon.connect` 方法** —— 连接是隐式的，daemon 启动立即发 `daemon.connected` 事件，无握手
- **没有 `app.start` 请求** —— `app.start` 只是**事件**（见 §4）。app 启动是通过 `flutter run --machine` 命令行触发，不是 RPC。`AppDomain` 只注册了 `restart`/`callServiceExtension`/`stop`/`detach` 四个 handler（`daemon.dart:647-650`）
- **`app.exposeUrl` 是反向请求**（daemon → client）：daemon 调 `daemon.connection.sendRequest('app.exposeUrl', {url})`（`daemon.dart:428`），client 须回 `{url}`。仅当 web 项目传 `--web-allow-expose-url` 时使用

## 4. 响应格式（daemon → client）

成功（`sendResponse`，`daemon.dart:248`）：
```json
[{"id":"<string>","result":<object|null>}]
```

错误（`sendErrorResponse`，`daemon.dart:252`）：
```json
[{"id":"<string>","error":<object>,"trace":"<string>"}]
```

⚠️ **字段名陷阱**：传输层 doc 注释写的是 `"stackTrace"`，但**实际线上字段是 `trace`**（`'trace': '$trace'`，`daemon.dart:252`；接收方读 `data['trace']`，`daemon.dart:290`）。wrapper 解析错误响应时必须用 `trace`。

## 5. 事件格式（daemon → client，主动推送）

```json
[{"event":"<name>","params":{...}}]
```

- 无 `id`。`params` 可选
- 可带二进制（`sendEvent(name, params, binary)`，`daemon.dart:255`）

### 5.1 daemon.* 域

| 事件 | params | 路径? |
|---|---|---|
| `daemon.connected` | `{version:"0.6.1", pid:<int>}` | ❌ **无 sdk 字段** |
| `daemon.logMessage` | `{level, message, stackTrace?}` | ❌（`message` 文本里可能含路径，但非结构化） |

### 5.2 device.* 域（`_deviceToMap`，`daemon.dart:1415`）

| 事件 | params |
|---|---|
| `device.added` / `device.removed` | 设备 map（见下） |

设备 map 结构：
```json
{
  "id":"emulator-5554",
  "name":"Pixel 7 API 33",
  "platform":"android-x64",
  "emulator":true,
  "category":"mobile",
  "platformType":"android",
  "cpuArch":"x64",
  "ephemeral":true,
  "emulatorId":"Pixel_7_API_33",
  "sdk":"Android SDK 33.0",
  "isConnected":true,
  "connectionInterface":"usb",
  "capabilities":{"hotReload":true,"hotRestart":true,"screenshot":true,"fastStart":false,"flutterExit":true,"hardwareRendering":true,"startPaused":true}
}
```

**全部无文件路径**。`emulatorId`/`category`/`platformType`/`sdk` 都是标识符或枚举，**不要误翻译**。

- **`device.changed` 不存在** —— 只有 `added` 和 `removed`（`daemon.dart:1051-1052`）
- 其它 device 事件：`device.logReader.logLines.<id>`(日志行)、`device.dds.done.<deviceId>`、`device.VMServiceDiscoveryForAttach.<id>`(uri 字符串)

### 5.3 app.* 域（`flutter run --machine` 时由 `AppDomain` 发，`_sendAppEvent` 拼 `app.<name>`，`daemon.dart:1002`）

| 事件 | params | 路径? |
|---|---|---|
| `app.start` | `{appId, deviceId, directory, supportsRestart, launchMode, mode}` | ✅ **`directory` 是项目目录路径** |
| `app.started` | `{appId}` | ❌ |
| `app.stop` | `{appId, error?, trace?}` | ❌ |
| `app.debugPort` | `{appId, port, wsUri, baseUri?}` | ⚠️ `wsUri`/`baseUri` 是 URI（见 §7） |
| `app.devTools` | `{appId, uri}` | ⚠️ URI |
| `app.dtd` | `{appId, uri}` | ⚠️ URI |
| `app.progress` | `{appId, id, progressId?, message?, finished}` | ❌ |
| `app.log` | `{appId, log, error?}` | ❌ |

### 5.4 旧协议事件说明

以下事件名在当前 `main` 的 `daemon.dart` / `resident_runner.dart` / `run_hot.dart` / `vmservice.dart` 中**均未找到发送点**：
- `app.out`、`app.flutterError`、`app.async_updated`、`app.debugDispatch`
- `daemon.log`、`daemon.showMessage`、`daemon.showProgress`

结论：这些很可能是**旧协议版本的事件名**或来自 IDE 插件侧的内部约定，当前协议不再使用。即使存在也只携带 `appId`+文本/错误负载，**不含文件系统路径**，对路径翻译无影响。wrapper 设计时作为未知事件透传即可。

## 6. 路径字段清单（最关键，按翻译方向分类）

### 6.1 必须翻译的文件系统路径

| 字段位置 | 字段 | 方向 | 翻译规则 |
|---|---|---|---|
| `daemon.getSupportedPlatforms` 请求 params | `projectRoot` | Windows → WSL | IDE 传 `D:\workspace\demo` → `/mnt/d/workspace/demo` |
| `app.start` 事件 params | `directory` | WSL → Windows | daemon 回显 `/home/berial/demo` → `D:\...` 或 `\\wsl.localhost\Ubuntu-24.04\home\berial\demo` |
| `device.startApp` 请求 params | `mainPath` | Windows → WSL | 仅 proxied/prebuilt 流程使用，如 `lib/main.dart`（相对）或绝对路径 |
| `app.debugPort` 事件 params | `baseUri` | 视协议 | 若为 `file://...` 则需路径翻译；若为 `http://` 则是 web 服务地址 |

### 6.2 URI 类（非纯文件路径，但需关注 WSL2 网络）

| 字段位置 | 字段 | 处理建议 |
|---|---|---|
| `app.debugPort` 事件 | `wsUri` | `ws://127.0.0.1:<port>/<token>`。WSL2 默认 localhost forwarding 通常可直连，**一般不需翻译**；若不行需把 `127.0.0.1` 换成 WSL IP |
| `app.devTools` 事件 | `uri` | `http://127.0.0.1:<port>/...`，同上 |
| `app.dtd` 事件 | `uri` | 同上 |
| `device.startDartDevelopmentService` 响应 | `ddsUri`/`devToolsUri`/`dtdUri` | 同上 |
| `device.VMServiceDiscoveryForAttach.<id>` 事件 | (params 是 uri 字符串) | 同上 |
| `app.exposeUrl` 反向请求/响应 | `url` | web URL，通常不翻译 |

### 6.3 proxy 域的 path（特殊，相对 temp 目录）

`proxy.writeTempFile`/`updateFile`/`calculateFileHashes`/`write` 的 `path` 是**相对于 daemon 临时目录** `systemTemp/flutter_tool_daemon/`（`daemon.dart:1806`）的相对文件名，**不是项目绝对路径**，**不应做 WSL↔Windows 翻译**。`device.uploadApplicationPackage` 的 `applicationBinary` 同理。

### 6.4 明确不是路径，禁止翻译

- `daemon.connected` 的 `version`/`pid`（**没有 `sdk` 字段**）
- 设备 map 的 `emulatorId`、`category`、`platformType`、`platform`、`sdk`、`connectionInterface`
- emulator map 的 `id`、`name`、`category`、`platformType`
- 所有 `appId`（UUID v4，`daemon.dart:655`）、`deviceId`、`applicationPackageId`

## 7. 守护进程生命周期

- **长进程**：`flutter daemon` 持续运行直到关闭。`Daemon.onExit` 是 `Completer<int>`，`runCommand` `await daemon.onExit`（`daemon.dart:86`）
- **关闭方式**：
  1. 发 `daemon.shutdown` 请求 → `Timer.run(daemon.shutdown)`（`daemon.dart:386`），异步清理（dispose 各 domain、关 connection、complete exit code 0）
  2. 关闭 stdin（`onDone` 回调触发 `shutdown()`，`daemon.dart:166-170`）
  3. kill 进程
- **并发请求**：支持。`_handleRequest` 对每条请求独立处理，handler 异步执行，完成后用匹配的 `id` 回响应。**没有全局请求锁**。但 `app.restart` 有 `DebounceOperationQueue`（`daemon.dart:659,898`）做 reload/restart 的去抖串行化（默认 50ms 去抖窗口）
- **stdin 批量**：一次发一条消息（一行），但可连续发多行。无显式 batch 概念，每行独立解析
- **多个并发 daemon**：stdio 模式一个进程一个 daemon；TCP 模式每 socket 一个独立 `Daemon`（`daemon.dart:130-137`）

## 8. 二进制安全性结论

**协议层面支持二进制**，通过 `_binaryLengthKey` 机制（`daemon.dart:34,116-120`）。

### 8.1 实际使用情况

- **正常 IDE 工作流**（device 发现 + `flutter run --machine` 调试）：**不会产生二进制**。所有 app.* / device.* / daemon.* 事件都是纯 JSON。`device.takeScreenshot` 返回 base64 字符串（不是二进制流）
- **二进制仅出现在 `proxy` 域**（proxied/remote devices，远程开发场景）：
  - 请求带二进制：`proxy.writeTempFile`、`proxy.updateFile`、`proxy.write`（`registerHandlerWithBinary`，`daemon.dart:1660-1665`）
  - 事件带二进制：`proxy.data.<id>`（`sendEvent('proxy.data.$id', null, data)`，`daemon.dart:1746`）

### 8.2 对 WSL Wrapper 的建议

- 若 wrapper 只服务正常 IDE 工作流（不涉及 proxied devices）→ 实际不会遇到二进制，但仍建议**按二进制安全实现**以应对未来扩展和 proxy 域
- **强烈不建议用 PowerShell 字符串管道转发** —— PowerShell 的 `[Console]::In/Out`、`$input`、默认编码会破坏 UTF-8 多字节和二进制
- 应使用**原始字节流转发**：
  - .NET 的 `Console.OpenStandardInput()/OpenStandardOutput()` 返回的 `Stream`
  - 或 `Process.StandardInput.BaseStream` / `StandardOutput.BaseStream`
  - 按字节 buffer 透传
  - 用上述状态机解析 `[{...}]\n` + `_binaryLength` 帧边界做路径翻译注入
- 换行符：协议用 **LF (10)**，不是 CRLF。Windows 下注意不要让文本模式把 `\n` 转成 `\r\n` 污染二进制段

### 8.3 wsl.exe stdout 重定向陷阱（Phase 6 实战发现，2026-07-17）

**关键问题**：从 PowerShell 用 `System.Diagnostics.Process` 启动 `wsl.exe flutter daemon` 时，若设置 `RedirectStandardOutput = $true`，**daemon 完全不输出任何数据**——连 `daemon.connected` 事件都没有。WSL 内甚至没有 flutter 进程（wsl.exe 卡在初始化阶段）。

**根因**：wsl.exe 检测 stdout 是否为 TTY。当 stdout 被重定向到 anonymous pipe 时，wsl.exe 进入不同的模式（可能尝试 PTY 协商或阻塞等待），导致子进程无法正常启动。

**验证**：
- `RedirectStandardOutput = $false`（继承 console）→ daemon 立即输出 `daemon.connected` ✅
- `RedirectStandardOutput = $true`（pipe）→ 60 秒无输出，WSL 内无进程 ❌
- bash 内 `printf '...' | flutter daemon`（pipe 但立即有数据）→ 正常 ✅

**结论**：**不能用 `Process.RedirectStandardOutput` 读 wsl.exe 的 daemon stdout**。改用 TCP 模式（§9）。

## 9. Wrapper 的 daemon 翻译实现策略（TCP 模式）

### 9.0 架构变更：TCP 模式（2026-07-17）

因 §8.3 的 wsl.exe stdout 重定向问题，**放弃 stdio 模式，改用 TCP 模式**：

```
Android Studio DaemonApi
  │
  │ stdin/stdout (Windows 路径)
  ▼
wrapper.ps1
  │
  │ TCP socket 127.0.0.1:<port> (WSL 路径，无需翻译 wsl.exe stdout)
  ▼
WSL flutter daemon --listen-on-tcp-port=<port>
```

**工作流**：
1. wrapper.ps1 启动 `wsl.exe flutter daemon --listen-on-tcp-port=<port>`（不重定向 stdout，让它继承 console 或丢弃）
2. wrapper.ps1 作为 TCP client 连接 `127.0.0.1:<port>`（WSL2 localhost forwarding 自动转发）
3. wrapper.ps1 在 Android Studio stdin/stdout ↔ TCP socket 之间做字节流代理 + 帧解析 + 路径翻译
4. wsl.exe 进程退出时 wrapper 也退出

**端口选择**：固定端口 9876（可配置），或动态分配（`--listen-on-tcp-port=0` 后从 stdout 读实际端口——但 stdout 读不了，所以用固定端口）。

**优势**：
- 完全绕开 wsl.exe 的 stdout TTY 检测问题
- TCP socket 是干净的字节流，无编码/TTY 污染
- daemon 协议原生支持 TCP 模式（§1）
- WSL2 localhost forwarding 默认开启，Windows 直接访问 `127.0.0.1:<port>`

**已验证**（2026-07-17）：
- WSL 内 `flutter daemon --listen-on-tcp-port=9876` → `Daemon server listening on 9876`
- Windows PowerShell `TcpClient.Connect('127.0.0.1', 9876)` → 连接成功
- 收到 `daemon.connected` v0.6.1
- 发送 `daemon.version` → 收到响应 `0.6.1`
- 发送 `daemon.shutdown` → daemon 正常退出

### 9.1 整体架构

```
Android Studio DaemonApi                WSL flutter daemon
  │                                          │
  │  stdin (Windows 路径)                    │  stdin (WSL 路径)
  ▼                                          ▲
wrapper.ps1 (字节流代理 + 帧解析 + 路径翻译)
  │
  │  stdout (WSL 路径 → Windows 路径)
  ▼
Android Studio
```

### 9.2 帧解析状态机

```
状态 1: 读 JSON 行
  ├─ 按 LF 切行
  ├─ 解析 [{...}] 得到 JSON 对象
  ├─ 若对象含 "_binaryLength": N
  │    └─ 状态 2: 读 N 字节二进制（透传不翻译）
  └─ 翻译路径字段 → 重写帧 → 转发

状态 2: 读二进制
  └─ 读满 N 字节后回到状态 1
```

### 9.3 路径翻译注入点

**入方向（stdin，Android Studio → daemon）**：
- 解析 `method` 字段
- 若 `method == "daemon.getSupportedPlatforms"`：翻译 `params.projectRoot`（Windows → WSL）
- 若 `method == "device.startApp"`：翻译 `params.mainPath`（Windows → WSL，若为绝对路径）
- 其他方法：透传

**出方向（stdout，daemon → Android Studio）**：
- 解析 `event` 字段
- 若 `event == "app.start"`：翻译 `params.directory`（WSL → Windows）
- 若 `event == "app.debugPort"`：检查 `params.baseUri`，若 `file://` 开头则翻译
- 其他事件：透传

**响应方向**（`id` 匹配）：
- `daemon.getSupportedPlatforms` 响应：检查 result 里有无路径字段（实际无，但保留扩展）
- 其他响应：透传

### 9.4 翻译失败处理

- 若路径翻译失败（如无法识别的路径格式）：**原样透传**，不阻塞通信
- 写一条 warning 日志到 `logs/wrapper.log`
- 让 Android Studio 自行处理（可能显示错误，但不会卡死通信）

### 9.5 性能考虑

- daemon 是长进程，启动一次 wsl.exe 后持续运行
- 每条消息的帧解析 + JSON 解析 + 路径翻译开销很小（< 1ms）
- 瓶颈在 wsl.exe 的 stdin/stdout 管道吞吐，但对 JSON 行协议足够
- 若发现性能问题，考虑用 C# 重写翻译核心

### 9.6 PS 5.1 host Stream 陷阱与文本模式实现（2026-07-20 实战发现）

**核心发现**：原计划用字节流模式（`OpenStandardInput/Output` + `DaemonFrameParser`），但 PS 5.1 host 下 Stream API 不可靠。改为**文本模式**（`StreamReader/Writer` + `[Console]::In/Out` TextReader/TextWriter）。

**陷阱清单**：

| API | 行为 | 解决方案 |
|-----|------|----------|
| `[Console]::OpenStandardOutput().Write()` | 数据**不到达**父进程的重定向 pipe（父进程收到 0 字节） | 改用 `[Console]::Out.WriteLine()` (TextWriter) |
| `[Console]::OpenStandardInput().Read()` | **无限阻塞**，即使有数据 | 改用 `[Console]::In.ReadLine()` (TextReader) |
| `BaseStream.DataAvailable` | **不可靠**，有数据时也返回 false | 用 `ReadLine()`/`ReadLineAsync()` |
| PS 5.1 class 跨 Runspace | class 实例方法在子 Runspace 中调用时**静默失败**（不抛异常） | 用函数式 hashtable 替代 class |
| `param()` 块位置 | `AddScript + AddParameters` 传参时，param 块不在脚本首行会导致参数全为空 | param 块作为独立字符串拼接到脚本最前面 |
| `Runspace.Close()` | 若 Runspace 内有阻塞的 pipeline，`Close()` 会**阻塞等待** | 用 `[Environment]::Exit()` 直接终止进程 |
| `PowerShell.Stop()` | 无法中断 native 阻塞调用（如 `[Console]::In.ReadLine()`） | 同上，用 `[Environment]::Exit()` |
| `exit` 语句 | PS 5.1 的 `exit` 会等所有 Runspace 完成 | 用 `[System.Environment]::Exit(code)` 强制退出 |

**文本模式安全性**：daemon 协议在正常 IDE 工作流中全是 JSON 文本（`[{json}]\n` 帧），二进制帧仅在 proxy 域出现（不需要）。因此文本模式安全。

**wsl.exe 启动配置**：
```powershell
$wslPsi.RedirectStandardInput = $true   # 防止 wsl.exe 继承 wrapper stdin（否则会消耗 daemon 请求）
$wslPsi.RedirectStandardOutput = $false # 继承 console stdout（重定向会触发 TTY 检测问题，见 §8.3）
$wslPsi.RedirectStandardError = $false
$wslProc.Start()
$wslProc.StandardInput.Close()  # 立即关闭（daemon 不读 stdin）
```

**两 Runspace 架构**：
- Runspace 1: `[Console]::In.ReadLine()` → `Translate-Frame('in')` → `tcpWriter.WriteLine()`
- Runspace 2: `tcpReader.ReadLine()` → `Translate-Frame('out')` → `[Console]::Out.WriteLine()`
- 主线程: `$wslProc.WaitForExit()` 循环，检测 `handle2.IsCompleted`（TCP EOF）则 kill wsl.exe

**退出处理**：daemon.shutdown 关闭 TCP 但 wsl.exe 不一定立即退出。主线程检测 TCP EOF 后主动 kill wsl.exe，然后用 `[Environment]::Exit()` 绕过 Runspace 阻塞（in pump 阻塞在 native ReadLine）。

**UTF-8 编码**：
```powershell
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
```
解决 PS 5.1 默认 GBK 编码下解码 UTF-8 BOM 的问题（`锘縃ELLO` 乱码）。

## 10. 关键源码位置

所有路径基于 `flutter/flutter` 仓库 `main` 分支：
- 传输层（`DaemonConnection`/`DaemonStreams`/`DaemonInputStreamConverter`/二进制帧解析）：`packages/flutter_tools/lib/src/daemon.dart`
- 命令入口 + 全部 Domain 逻辑（Daemon/AppDomain/DeviceDomain/EmulatorDomain/DevToolsDomain/ProxyDomain + `protocolVersion` + `_deviceToMap` + `_emulatorToMap` + `MachineOutputLogger`）：`packages/flutter_tools/lib/src/commands/daemon.dart`

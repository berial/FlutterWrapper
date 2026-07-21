# 常见问题 (FAQ)

## 为什么不直接用 Windows Flutter？

- **Linux 工具链**：NDK、cmake 在 WSL 内原生运行，无需跨编译。
- **文件系统性能**：WSL ext4 处理大量小文件（Flutter 项目特征）比 NTFS 快。
- **版本管理**：vfox 和 FVM 在 Linux 上的体验更好。
- **CI 一致性**：开发环境与 Linux CI 运行器一致。

## 项目为什么必须放在 WSL 文件系统上？

Flutter 工具链（Gradle、NDK、cmake）在 WSL 内运行。项目放 Windows NTFS（`C:\`/`D:\`）会导致每次文件访问都跨 WSL/NTFS 边界，严重拖慢 `pub get` 和 Gradle 构建。

## 为什么需要映射 W: 盘？

CMD.EXE（Android Studio 用它启动 `flutter.bat`）**不支持 UNC 路径**作为工作目录。如果用 `\\wsl.localhost\...` 打开项目，CMD 静默回退到 `C:\Windows`，导致 flutter 报 `No pubspec.yaml file found`。

映射盘符（W:）让 WSL 文件系统以普通盘符形式出现，CMD 可以正常使用。

## 为什么修改 package_config.json？

Dart 分析服务器在 **Windows** 本地运行（通过 Junction 指向的 `dart.exe`），需要 Windows 风格路径找包。WSL 内的编译需要 Linux 路径。

FlutterWrapper 在 `pub get` 后将文件翻译为 `file:///w:/...` 格式。Windows Dart 通过 `W:\` 读取，WSL Dart 通过 `/w:` 符号链接解析。两边共享一个文件。

## 支持 VS Code 吗？

VS Code 原生支持 [Remote - WSL](https://code.visualstudio.com/docs/remote/wsl)，直接在 WSL 内打开项目即可，不需要 FlutterWrapper。

FlutterWrapper 专为 Android Studio（IntelliJ 系列 IDE）设计，因为它们没有原生 WSL 远程开发支持。

## 支持哪些 Flutter 版本？

Flutter 3.22+。推荐 3.44+（Dart 3.12.2+ 修复了分析服务器的 UNC 路径 bug）。

## 能同时保留 Windows 上的 Flutter 吗？

可以共存。`bin/cache/dart-sdk` 的 Junction 指向 Windows Flutter 的 Dart SDK 用于代码分析。WSL 内的 Flutter 负责所有构建和运行。

## 用 vfox 还是 FVM？

- **vfox**：通用版本管理器，一个工具管理 Flutter、Java、Node.js 等所有 SDK。适合多语言开发者。
- **FVM**：Flutter 专用，社区生态更好（`.fvmrc` 是 Flutter 项目的行业标准）。适合纯 Flutter 开发者。

两者 FlutterWrapper 都支持。运行 `fw provider` 查看检测结果。

## 怎么切换 Flutter 版本？

```powershell
fw flutter use 3.44.6    # 自动路由到 vfox 或 FVM
```

或直接调用：
```bash
# vfox in WSL
vfox use -g flutter@3.44.6

# FVM in WSL  
fvm global 3.44.6
```

切换后需重启 Android Studio，Dart 插件才能感知新版本。

## 为什么某些问题标记为 "不是 FlutterWrapper 的 bug"？

FlutterWrapper 是兼容层——在 Windows 和 WSL 之间做翻译。部分问题（如旧版 Dart 分析服务器的 UNC 路径崩溃、Linux 下无 Web 设备）源自 Flutter/Dart 自身，影响所有 WSL 用户，不是 FlutterWrapper 独有的。

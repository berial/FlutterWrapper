我建议把这个项目定位为一个**可长期维护的兼容层（Compatibility Layer）**，而不是一个简单的 `flutter.bat` 脚本。目标是： 
 
 > **让 Android Studio 认为它使用的是一个正常的 Windows Flutter SDK，而实际上所有 Flutter/Dart 命令都在 WSL 中执行。** 
 
 放到你的目录就是： 
 
 ```text 
 D:\ 
 └── Android 
     └── FlutterWrapper 
 ``` 
 
 --- 
 
 # Phase 0：调研（1~2 天） 
 
 ## 目标 
 
 彻底弄清 Android Studio 与 Flutter Plugin 的调用方式。 
 
 ### 输出 
 
 ``` 
 D:\Android\FlutterWrapper 
 ├── docs 
 │   ├── architecture.md 
 │   ├── sdk-layout.md 
 │   ├── flutter-plugin.md 
 │   ├── daemon.md 
 │   ├── path-convert.md 
 │   └── risks.md 
 ``` 
 
 需要确认： 
 
 * Android Studio 调用哪些命令 
 * SDK 最小目录结构 
 * daemon 通信方式 
 * cwd 设置方式 
 * stderr/stdout 是否会影响 Plugin 
 
 --- 
 
 # Phase 1：目录结构 
 
 ``` 
 D:\Android\FlutterWrapper 
 │ 
 ├── bin 
 │   ├── flutter.bat 
 │   ├── dart.bat 
 │   ├── flutter.ps1 
 │   ├── dart.ps1 
 │   └── wrapper.ps1 
 │ 
 ├── cache 
 │ 
 ├── packages 
 │ 
 ├── version 
 │ 
 ├── config 
 │   └── wrapper.yaml 
 │ 
 ├── logs 
 │ 
 ├── tools 
 │ 
 └── docs 
 ``` 
 
 目标： 
 
 让 Android Studio 能把这里识别成 Flutter SDK。 
 
 --- 
 
 # Phase 2：配置文件 
 
 例如： 
 
 ```yaml 
 version: 1 
 
 wsl: 
   distro: Ubuntu-24.04 
 
 flutter: 
   executable: ~/.version-fox/cache/flutter/current/bin/flutter 
 
 dart: 
   executable: ~/.version-fox/cache/flutter/current/bin/dart 
 
 workspace: 
   uncPrefix: \\wsl.localhost\Ubuntu-24.04 
 ``` 
 
 以后不用改脚本。 
 
 --- 
 
 # Phase 3：路径转换 
 
 支持： 
 
 ## Windows 
 
 ``` 
 D:\workspace\demo 
 ``` 
 
 ↓ 
 
 ``` 
 /mnt/d/workspace/demo 
 ``` 
 
 --- 
 
 ## UNC 
 
 ``` 
 \\wsl.localhost\Ubuntu-24.04\home\berial\demo 
 ``` 
 
 ↓ 
 
 ``` 
 /home/berial/demo 
 ``` 
 
 --- 
 
 ## 相对路径 
 
 ``` 
 lib/main.dart 
 ``` 
 
 ↓ 
 
 保持不变。 
 
 --- 
 
 ## cwd 
 
 例如： 
 
 ``` 
 Get-Location 
 ``` 
 
 ↓ 
 
 自动转换。 
 
 --- 
 
 # Phase 4：Wrapper 
 
 flutter.bat 
 
 ↓ 
 
 flutter.ps1 
 
 ↓ 
 
 wrapper.ps1 
 
 ↓ 
 
 ``` 
 wsl.exe 
 ``` 
 
 ↓ 
 
 ``` 
 flutter 
 ``` 
 
 职责： 
 
 * 读取配置 
 * 转换 cwd 
 * 转换参数 
 * 保留 stdin 
 * 保留 stdout 
 * 保留 stderr 
 * 返回 exit code 
 
 --- 
 
 # Phase 5：SDK 模拟 
 
 确认 Android Studio 会检查： 
 
 ``` 
 version 
 ``` 
 
 ``` 
 cache/ 
 ``` 
 
 ``` 
 packages/ 
 ``` 
 
 缺什么补什么。 
 
 尽量不要复制真正 Flutter SDK。 
 
 --- 
 
 # Phase 6：命令兼容 
 
 逐个验证： 
 
 ``` 
 flutter --version 
 ``` 
 
 ``` 
 flutter doctor 
 ``` 
 
 ``` 
 flutter pub get 
 ``` 
 
 ``` 
 flutter clean 
 ``` 
 
 ``` 
 flutter run 
 ``` 
 
 ``` 
 flutter daemon 
 ``` 
 
 ``` 
 flutter devices 
 ``` 
 
 ``` 
 flutter build apk 
 ``` 
 
 ``` 
 flutter build web 
 ``` 
 
 ``` 
 flutter test 
 ``` 
 
 --- 
 
 # Phase 7：dart 
 
 Android Studio 也会调用： 
 
 ``` 
 dart 
 ``` 
 
 因此： 
 
 ``` 
 dart.bat 
 ``` 
 
 也要实现。 
 
 --- 
 
 # Phase 8：日志 
 
 ``` 
 D:\Android\FlutterWrapper\logs 
 ``` 
 
 例如： 
 
 ``` 
 wrapper.log 
 ``` 
 
 记录： 
 
 ``` 
 时间 
 
 cwd 
 
 原始命令 
 
 转换后命令 
 
 退出码 
 
 耗时 
 ``` 
 
 方便排查问题。 
 
 --- 
 
 # Phase 9：自动测试 
 
 建立测试矩阵： 
 
 | 功能         | 预期                 | 
 | ---------- | ------------------ | 
 | SDK 检测     | Android Studio 能识别 | 
 | Pub Get    | 成功                 | 
 | Run        | 成功                 | 
 | Hot Reload | 成功                 | 
 | Debug      | 成功                 | 
 | Devices    | 成功                 | 
 | Build      | 成功                 | 
 | Test       | 成功                 | 
 
 每完成一项就打勾。 
 
 --- 
 
 # Phase 10：安装脚本 
 
 例如： 
 
 ``` 
 install.ps1 
 ``` 
 
 自动： 
 
 * 创建目录 
 * 写配置 
 * 检查 WSL 
 * 检查 flutter 
 * 检查 version-fox 
 * 检查 distro 
 
 最后提示： 
 
 ``` 
 Flutter SDK Path 
 
 D:\Android\FlutterWrapper 
 ``` 
 
 即可。 
 
 --- 
 
 # 后续增强（可选） 
 
 等基本功能稳定后，可以再考虑： 
 
 * **自动发现 WSL 发行版**（不用手写 `Ubuntu-24.04`）。 
 * **自动发现 Flutter 路径**（读取 Version Fox 或 PATH，而不是固定 `~/.version-fox/...`）。 
 * **多发行版支持**（Ubuntu、Debian 等）。 
 * **性能优化**（减少每次启动 `wsl.exe` 的开销）。 
 * **单元测试**（重点测试路径转换和参数转换逻辑）。 
 
 --- 
 
 ## 我建议的技术路线 
 
 我建议**不要从 Batch 开始**，而是： 
 
 * `flutter.bat`：仅作为 Android Studio 的入口。 
 * `flutter.ps1`：负责参数处理和日志。 
 * `wrapper.ps1`：负责 WSL 调用和路径转换。 
 * 后期如果性能或兼容性需要，再把核心逻辑迁移到 **C#/.NET 单文件可执行程序**，作为真正的 Wrapper。 
 
 这样开发速度快、便于调试，也方便以后逐步演进。 

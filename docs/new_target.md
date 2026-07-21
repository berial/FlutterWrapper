# FlutterWrapper

## Windows Android Studio + WSL Flutter 开发桥接方案

**版本：v1.0 Draft**

---

# 1. 背景

## 1.1 问题背景

Flutter 官方主要支持：

### Windows 原生开发

```text
Windows
├── Android Studio
├── Flutter SDK
├── Dart SDK
├── Android SDK
└── Project
```

或者：

### Linux 原生开发

```text
Linux
├── Android Studio
├── Flutter SDK
├── Dart SDK
├── Android SDK
└── Project
```

但是实际开发中，希望：

* 使用 Windows Android Studio
* 使用 WSL2 Linux 环境
* 项目存储在 Linux 文件系统
* 使用 Linux Flutter Toolchain
* 使用 Windows Emulator / Android SDK

形成：

```text
Windows IDE
+
Linux Toolchain
+
Linux Project
```

官方没有直接支持。

---

# 2. 目标

FlutterWrapper 的目标：

> 让 Windows 版 Android Studio 认为本机存在一个 Flutter SDK，而实际上所有 Flutter/Dart 操作运行在 WSL Linux 环境。

最终体验：

```text
Android Studio
        |
        |
Flutter SDK:
D:\Android\FlutterWrapper
        |
        |
        ▼
WSL Flutter SDK
/home/berial/.version-fox/flutter
```

---

# 3. 最终架构

```
                         Windows

┌────────────────────────────────────┐
│                                    │
│        Android Studio               │
│                                    │
│  Flutter Plugin                     │
│  Dart Plugin                        │
│                                    │
└────────────────┬───────────────────┘
                 │
                 │ Flutter SDK Path
                 ▼

┌────────────────────────────────────┐
│                                    │
│       D:\Android\FlutterWrapper     │
│                                    │
│  flutter.bat                       │
│  dart.bat                          │
│  wrapper.exe                       │
│  config.yaml                       │
│                                    │
└────────────────┬───────────────────┘
                 │
                 │ wsl bridge
                 ▼


                         WSL

┌────────────────────────────────────┐
│                                    │
│ Ubuntu-24.04                       │
│                                    │
│ Flutter SDK                        │
│ Dart SDK                           │
│ Pub                                │
│ Gradle                             │
│ Java                               │
│                                    │
│ /home/berial/workspace/flutter     │
│                                    │
└────────────────────────────────────┘


                         Windows

┌────────────────────────────────────┐
│                                    │
│ Android SDK                        │
│ Emulator                           │
│ adb.exe                            │
│                                    │
└────────────────────────────────────┘
```

---

# 4. 设计原则

## 4.1 Windows 只负责 IDE

Windows：

负责：

* Android Studio
* Flutter Plugin
* Dart Plugin
* Emulator
* Android SDK

---

## 4.2 WSL 负责 Flutter Toolchain

WSL：

负责：

* Flutter SDK
* Dart SDK
* pub
* Gradle
* Java
* Git
* 项目源码

---

## 4.3 Wrapper 保持透明

Android Studio 不应该知道：

* WSL
* Linux路径
* wsl.exe

它只看到：

```
D:\Android\FlutterWrapper
```

---

# 5. 核心模块设计

---

# 5.1 SDK Proxy

目的：

让 Android Studio 识别 Wrapper 为 Flutter SDK。

目录：

```
D:\Android\FlutterWrapper

├── bin
│   ├── flutter.bat
│   └── dart.bat
│
├── packages
├── cache
└── version
```

Android Studio 检测：

```
Flutter SDK Path
        |
        ▼
FlutterWrapper
```

---

# 5.2 Command Bridge

负责转发：

## Flutter

```
flutter doctor
flutter pub get
flutter run
flutter build
flutter daemon
```

## Dart

```
dart analyze
dart format
dart test
```

流程：

```
Android Studio

flutter.bat

        ↓

wrapper.exe

        ↓

wsl.exe

        ↓

flutter
```

---

# 5.3 WSL Bridge

统一管理：

```
wsl.exe
```

功能：

* 指定发行版
* 设置工作目录
* 环境变量传递
* 参数转换

例如：

Windows:

```
D:\workspace\app
```

转换：

```
/mnt/d/workspace/app
```

WSL:

```
/home/berial/workspace/flutter/app
```

保持。

---

# 5.4 Environment Adapter

管理：

## Flutter

```
FLUTTER_STORAGE_BASE_URL
PUB_HOSTED_URL
```

## Android

```
ANDROID_HOME
ANDROID_SDK_ROOT
```

## Java

```
JAVA_HOME
```

## Pub

```
PUB_CACHE
```

---

# 5.5 Path Adapter

处理：

## Windows

```
D:\project
```

转换：

```
/mnt/d/project
```

---

## WSL UNC

```
\\wsl.localhost\Ubuntu-24.04
```

转换：

```
/home/xxx
```

---

# 6. Android 环境设计

采用：

Windows Android SDK。

原因：

* Emulator 在 Windows
* adb 在 Windows
* Android Studio 原生支持

WSL Flutter 使用：

```
adb.exe
```

通过 PATH 暴露：

```
adb

↓

adb.exe
```

---

# 7. Flutter SDK 管理

推荐：

WSL 使用：

* FVM
* Version Fox
* 手动 Flutter SDK

例如：

```
/home/berial/.version-fox/cache/flutter/v-3.44.6
```

Wrapper 配置：

```yaml
flutter:
  executable:
/home/berial/.version-fox/cache/flutter/v-3.44.6/bin/flutter
```

---

# 8. Android Studio 工作流

## 打开项目

方式：

```
File
 ↓
Open
 ↓
\\wsl.localhost\Ubuntu-24.04
 ↓
project
```

---

## Flutter SDK

设置：

```
Settings

Languages

Flutter

Flutter SDK path:

D:\Android\FlutterWrapper
```

---

## 运行

点击：

```
Run ▶
```

流程：

```
Android Studio

↓

Flutter Plugin

↓

FlutterWrapper

↓

WSL Flutter

↓

Windows adb/emulator

```

---

# 9. 已验证功能

## 已验证

| 功能                          | 状态                |
| --------------------------- | ----------------- |
| Android Studio识别Flutter SDK | ✅                 |
| WSL Flutter项目打开             | ✅                 |
| flutter run                 | ✅                 |
| Debug                       | ✅                 |
| Hot Reload                  | ✅                 |
| Flutter Inspector           | 待测试               |
| Dart Analysis               | ✅（Flutter 3.44.6） |
| package import索引            | ✅                 |

---

# 10. Flutter版本要求

测试结果：

## Flutter 3.41.9

```
Dart Analysis
❌
package import 红
```

## Flutter 3.44.6

```
Dart Analysis
✅
package import 正常
```

建议：

```
Flutter >= 3.44.x
```

---

# 11. 项目目录建议

```
D:\Android
│
├── FlutterWrapper
│
└── AndroidStudio
```

WSL：

```
/home/berial/workspace/flutter

├── project-a
├── project-b
└── project-c
```

---

# 12. 日志系统

目录：

```
FlutterWrapper

logs/

├── flutter.log
├── dart.log
└── bridge.log
```

记录：

* command
* args
* cwd
* environment
* exit code

---

# 13. 测试方案

## 基础测试

```
flutter --version
```

## 环境测试

```
flutter doctor -v
```

## 项目测试

```
flutter pub get
```

## IDE测试

* 自动补全
* 跳转
* Debug
* Hot Reload
* DevTools

---

# 14. 已知限制

## 1. Flutter版本

旧版本可能存在：

* Analysis Server
* WSL UNC Path

兼容问题。

推荐：

Flutter 3.44+

---

## 2. Android Studio升级

Android Studio Flutter Plugin 行为可能变化。

需要测试：

* SDK检测
* daemon协议

---

# 15. 后续增强方向

## v1.1

增加：

* 自动发现 WSL Flutter SDK
* 自动生成配置

---

## v1.2

增加：

* 多 WSL 发行版支持

例如：

```
Ubuntu-22.04
Ubuntu-24.04
Debian
```

---

## v1.3

支持：

* Melos
* FVM
* Shorebird

---

# 16. 项目定位总结

FlutterWrapper 不是：

> 一个 Flutter 命令转发脚本。

而是：

> 一个 Windows IDE 与 Linux Flutter Toolchain 的兼容桥接层。

它解决：

* Windows IDE 与 WSL Flutter 的隔离问题
* Windows 文件系统性能问题
* Linux Flutter 工具链问题
* Android Studio Flutter Plugin 兼容问题

最终实现：

```
最佳 IDE体验
        +
最佳 Linux开发环境
        +
最佳 Flutter工具链
```

这就是 FlutterWrapper 的完整方案定位。

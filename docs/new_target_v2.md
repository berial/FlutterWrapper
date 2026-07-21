定位：

> **基于 FlutterWrapper 当前实现重新整理的架构规范文档。**
>
> 不再只是“Flutter 命令代理方案”，而是完整描述 **Windows Android Studio + WSL Flutter Linux Toolchain 的兼容桥接层**。

---

# FlutterWrapper new_target_v2

## Windows Android Studio + WSL Flutter Development Bridge

版本：v2.0 Draft

---

# 1. 项目定位

## 1.1 定义

FlutterWrapper 是一个：

> Windows IDE 与 WSL Flutter Linux Toolchain 之间的兼容层。

目标：

让开发者能够：

* 使用 Windows Android Studio
* 使用 Windows Android Emulator
* 使用 WSL2 Linux Flutter SDK
* 使用 WSL Linux 项目文件系统

获得接近原生 Flutter 开发体验。

---

# 2. 背景问题

Flutter 官方支持：

## Windows Flutter

```text
Windows
├── Android Studio
├── Flutter SDK
├── Dart SDK
├── Android SDK
└── Project
```

---

## Linux Flutter

```text
Linux
├── Android Studio
├── Flutter SDK
├── Dart SDK
├── Android SDK
└── Project
```

---

但是缺少：

```text
Windows IDE
+
Linux Flutter Toolchain
+
Linux Project
```

组合支持。

---

# 3. 设计目标

FlutterWrapper 解决：

| 问题                            | 解决                       |
| ----------------------------- | ------------------------ |
| Android Studio无法识别WSL Flutter | SDK Proxy                |
| Windows无法调用Linux Flutter      | Command Bridge           |
| Windows/WSL路径冲突               | Path Adapter             |
| Flutter daemon路径错误            | Daemon Translator        |
| Dart Analysis报红               | Dart Compatibility Layer |
| Android SDK跨环境问题              | Android Bridge           |
| Gradle环境不一致                   | Gradle Adapter           |

---

# 4. 总体架构

```text
                         Windows

┌────────────────────────────────────┐
│                                    │
│          Android Studio             │
│                                    │
│ Flutter Plugin                      │
│ Dart Plugin                         │
│ Debugger                            │
│                                    │
└───────────────┬────────────────────┘
                │
                │ Flutter SDK Path
                ▼


┌────────────────────────────────────┐
│                                    │
│       D:\Android\FlutterWrapper     │
│                                    │
│ SDK Proxy                           │
│ Command Bridge                      │
│ Path Adapter                        │
│ Daemon Translator                   │
│ Dart Compatibility                  │
│ Android Adapter                     │
│ Gradle Adapter                      │
│                                    │
└───────────────┬────────────────────┘
                │
                │ WSL Bridge
                ▼


                         WSL2

┌────────────────────────────────────┐
│                                    │
│ Ubuntu-24.04                       │
│                                    │
│ Flutter SDK                        │
│ Dart SDK                           │
│ Pub                                │
│ Gradle                             │
│ Java                               │
│ Git                                │
│                                    │
│ /home/user/workspace/flutter       │
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

# 5. 核心模块设计

---

# 5.1 SDK Proxy

## 目标

让 Android Studio 认为：

```text
Flutter SDK:

D:\Android\FlutterWrapper
```

实际：

```text
WSL Flutter SDK
```

---

## 提供入口

```text
FlutterWrapper

bin/

├── flutter.bat
├── dart.bat
└── pub.bat
```

---

# 5.2 Command Bridge

## 职责

转发：

Flutter:

```bash
flutter run
flutter build
flutter pub get
flutter doctor
```

Dart:

```bash
dart analyze
dart format
dart test
```

流程：

```text
Android Studio

      ↓

FlutterWrapper

      ↓

wsl.exe

      ↓

Linux Flutter
```

---

# 5.3 WSL Bridge

负责：

* distro选择
* 工作目录转换
* 环境变量注入

支持：

```yaml
wsl:
  distro: Ubuntu-24.04
```

---

# 5.4 Environment Adapter

统一管理：

## Flutter

```text
FLUTTER_STORAGE_BASE_URL
PUB_HOSTED_URL
```

---

## Android

```text
ANDROID_HOME
ANDROID_SDK_ROOT
```

---

## Java

```text
JAVA_HOME
```

---

## Pub

```text
PUB_CACHE
```

---

# 5.5 Path Adapter

核心模块。

支持：

## Windows → Linux

例如：

```text
D:\workspace\flutter
```

转换：

```text
/mnt/d/workspace/flutter
```

---

## WSL UNC

输入：

```text
\\wsl.localhost\Ubuntu-24.04\home\user
```

输出：

```text
/home/user
```

---

## 映射盘

支持：

```text
W:
```

映射：

```text
\\wsl.localhost\Ubuntu-24.04
```

---

# 6. Flutter Daemon Translator

## 背景

Android Studio Flutter Plugin 依赖：

```text
flutter daemon
```

Daemon返回：

```json
{
 "event":"device.added"
}
```

其中包含：

* projectRoot
* directory
* device path

Linux路径：

```text
/home/user/project
```

Windows IDE无法识别。

---

## 解决方案

增加：

```text
JSON-RPC Translator
```

流程：

```text
Flutter daemon

       ↓

JSON Frame Parser

       ↓

Path Translation

       ↓

Android Studio
```

---

支持：

* 双向转换
* stdin/stdout保持
* JSON frame保持

---

# 7. Dart Analysis Compatibility Layer

## 背景

JetBrains Dart Plugin 不完全通过 Flutter Wrapper 调用 Dart。

调用：

```text
Android Studio

       ↓

dart.exe

       ↓

Analysis Server
```

---

## 方案

采用双轨：

---

## Flutter执行

使用：

```text
WSL Dart SDK
```

用于：

* flutter run
* build
* pub

---

## IDE分析

使用：

```text
Windows Dart SDK
```

用于：

* code completion
* navigation
* analyzer

---

## Path兼容

处理：

```text
package_config.json
```

中的：

```text
file:///w:/...
```

以及：

```text
/home/...
```

映射。

---

# 8. Android Toolchain Adapter

采用：

> Windows Android SDK + WSL Flutter Build

---

## Windows负责

```text
Android SDK
adb
emulator
build-tools
platform-tools
```

---

## WSL负责

```text
Flutter
Gradle
NDK
CMake
```

---

## local.properties

混合配置：

```properties
sdk.dir=C:\\Android\\sdk

ndk.dir=/home/user/android/ndk

cmake.dir=/home/user/android/cmake
```

---

# 9. Gradle Adapter

负责：

## 镜像

支持：

* Maven mirror
* Gradle Plugin Portal

---

## Gradle缓存共享

支持：

```text
.gradle
```

复用。

---

# 10. SDK管理

支持：

## vfox

当前推荐：

```text
WSL
 |
 vfox
 |
 Flutter
```

---

未来：

支持：

* FVM
* 官方SDK

---

# 11. 配置文件

位置：

```text
FlutterWrapper/config/wrapper.yaml
```

示例：

```yaml
wsl:
  distro: Ubuntu-24.04


flutter:
  sdk: /home/user/.version-fox/flutter/current


android:
  sdk: C:/Android/sdk


mapping:
  drive:
    W: /home/user
```

---

# 12. 安装流程

## Step 1

安装：

* WSL2
* Ubuntu

---

## Step 2

安装：

* Flutter SDK
* Dart SDK

---

## Step 3

安装：

* Android Studio

---

## Step 4

安装：

```text
FlutterWrapper
```

---

## Step 5

配置：

Android Studio:

```text
Flutter SDK:

D:\Android\FlutterWrapper
```

---

# 13. 诊断工具

增加：

```bash
flutter-wrapper doctor
```

输出：

```text
FlutterWrapper Doctor


[✓] Android Studio
[✓] WSL
[✓] Flutter SDK
[✓] Dart SDK
[✓] Path Mapping
[✓] Daemon Translation
[✓] Dart Analysis
[✓] Android Bridge
```

---

# 14. 已验证环境

| 组件             | 版本                       |
| -------------- | ------------------------ |
| Windows        | Windows 11               |
| WSL            | Ubuntu 24.04             |
| Android Studio | Quail 1 2026.1.1         |
| Flutter        | 3.44.6+                  |
| Dart           | Flutter内置                |
| IDE            | JetBrains Flutter Plugin |

---

# 15. 当前完成度

| 模块                  | 状态   |
| ------------------- | ---- |
| SDK Proxy           | ✅    |
| Command Bridge      | ✅    |
| WSL Bridge          | ✅    |
| Environment Adapter | ✅    |
| Path Adapter        | ✅    |
| Daemon Translator   | ✅    |
| Dart Analysis Layer | ✅    |
| Android Adapter     | ✅    |
| Gradle Adapter      | ✅    |
| Installer           | ✅    |
| Doctor              | ✅    |

---

# 16. 后续路线

## v2.1 ✅

重点：

* flutter-wrapper doctor ✅
* 自动诊断 ✅
* 日志拆分 ✅

---

## v2.2 ✅

重点：

* 自动发现 Flutter SDK ✅（install.ps1 -Auto）
* 自动生成配置 ✅（Auto 模式全程无输入）
* FVM 检测 ✅

---

## v2.3 ✅

重点：

* 多 WSL distro ✅（doctor 列出 + config 切换）
* FVM 支持 ✅（install + doctor 检测）
* Melos 支持 ✅（WSL 侧 pub global activate 即工作，无需 wrapper 改动）

---

# 17. 项目最终定位

FlutterWrapper 不只是：

```text
flutter.bat替代品
```

而是：

```text
Windows IDE
        +
Linux Flutter Toolchain
        +
WSL Project
```

之间的：

> **Compatibility Layer**

目标：

让 Android Studio 在 Windows 上无感使用 WSL Flutter 开发环境。

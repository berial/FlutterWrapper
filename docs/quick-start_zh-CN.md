# 快速开始

## 前置要求

- Windows 10 或 11，已启用 WSL2
- 已安装 WSL 发行版（推荐 Ubuntu 24.04）
- WSL 内已安装 Flutter SDK（通过 [vfox](https://vfox.dev) 或 [FVM](https://fvm.app)）
- Android Studio + Flutter 插件

## 1. 安装 FlutterWrapper

```powershell
git clone https://github.com/<user>/FlutterWrapper.git %USERPROFILE%\FlutterWrapper
cd %USERPROFILE%\FlutterWrapper
powershell -NoProfile -ExecutionPolicy Bypass -File install.ps1 -Auto
```

安装器自动检测：
- WSL 发行版（优先 Ubuntu-24.04，否则第一个可用）
- Flutter SDK 路径（`command -v flutter` → vfox → FVM → 手动）
- Dart SDK 路径（从 Flutter 路径推导）
- JDK 路径（vfox → JAVA_HOME → PATH）
- Android SDK 路径
- 自动映射 W: 盘到 WSL 文件系统

## 2. 运行诊断

```powershell
fw doctor
```

应该全部显示 ✓。如有 ✗，执行：

```powershell
fw doctor --fix-safe    # 自动修复安全项
# 或单独修复：
fw repair <模块名>      # 修复特定模块
```

## 3. 配置 Android Studio

1. 打开 Android Studio
2. **File → Settings → Languages & Frameworks → Flutter**
   - Flutter SDK path: `%USERPROFILE%\FlutterWrapper`
3. **File → Settings → Languages & Frameworks → Dart**
   - Dart SDK path: `%USERPROFILE%\FlutterWrapper\bin\cache\dart-sdk`
4. 重启 Android Studio

## 4. 打开 Flutter 项目

**关键**：必须通过映射盘符打开项目，不能用 UNC 路径。

```
✅ 正确：W:\home\<用户名>\projects\my_app
❌ 错误：\\wsl.localhost\Ubuntu-24.04\home\<用户名>\projects\my_app
```

安装器会自动创建 `net use W: \\wsl.localhost\<发行版>`。重启后映射丢失，可手动重建：

```powershell
net use W: \\wsl.localhost\<你的发行版> /persistent:yes
```

## 5. 开始开发

所有 Flutter 操作（pub get、run、hot reload、debug、build）现在都通过 WSL 执行。

```powershell
# 终端中：
fw status
fw flutter current

# 或直接用 flutter.bat：
%USERPROFILE%\FlutterWrapper\bin\flutter.bat devices
%USERPROFILE%\FlutterWrapper\bin\flutter.bat run
```

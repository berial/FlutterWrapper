# 故障排查

## 第一步：运行诊断

```powershell
fw doctor
```

检查 13 大类，每个失败项附带修复建议。

## 常见问题及修复

### Android Studio 中报 "No pubspec.yaml file found"

**原因**：项目通过 UNC 路径（`\\wsl.localhost\...`）打开。

**修复**：
1. 在 AS 中关闭项目
2. 用映射盘符重新打开：`W:\home\<用户名>\<项目>`
3. 验证映射：`net use W:` 应显示 `\\wsl.localhost\<发行版>`

### 所有 import 报红

**原因**：Dart 分析服务器旧版（3.12.2 之前）的 UNC 路径 bug。

**修复**：升级到 Flutter ≥ 3.44.6（Dart ≥ 3.12.2）。然后：
```powershell
fw repair dart-sdk
fw repair package-config
```
重启 Android Studio。

### flutter --version 卡住或无输出

**修复**：
```powershell
fw repair config       # 重新检测并生成配置
fw repair daemon       # 清理残留 daemon
fw doctor              # 验证
```

查看日志：`logs/flutter.log`

### Daemon 模式无响应

**修复**：
```powershell
fw repair daemon       # 杀掉 9876 端口残留进程
```

或手动：
```powershell
wsl -e bash -c "fuser -k 9876/tcp"
```

### Android Studio 报 "Flutter SDK not found"

**修复**：
```powershell
fw repair dart-sdk     # 重建 Junction
fw doctor --fix-safe   # 自动修复安全项
```

### 重启后 W: 盘不可访问

**修复**：
```powershell
net use W: \\wsl.localhost\<你的发行版> /persistent:yes
```

或重跑：`install.ps1 -Auto -SkipSmoke`

### 路径转换错误

```powershell
fw doctor               # 第 5 节检查路径映射
```

查看 `logs/flutter.log` 中的实际转换记录。

### WSL 构建报包错误（`/w:/.../No such file`）

**修复**：
```powershell
fw repair symlinks      # 重建 /w: 和 /W: 符号链接
```

需要 WSL 内 sudo。如果失败，手动执行：
```bash
wsl -e sudo bash tools/setup-wsl-symlink.sh <发行版> W
```

## 生成诊断报告

```powershell
fw doctor --json > doctor-report.json
```

提交 GitHub Issue 时附带此文件。

## 仍然无法解决？

在 GitHub 仓库提交 Issue，附上诊断报告和问题描述。

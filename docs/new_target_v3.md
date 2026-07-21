# FlutterWrapper v3

## Compatibility Orchestration Layer

---

# 1. v3 核心定位调整

## v2

解决：

```
Windows Android Studio
        ↓
FlutterWrapper
        ↓
WSL Flutter
```

的运行问题。

重点：

* 路径
* daemon
* Dart Analysis
* Android Toolchain

---

## v3

解决：

```
开发者
  ↓
FlutterWrapper
  ↓
vfox/FVM
  ↓
Flutter SDK
  ↓
WSL Runtime
```

的管理问题。

重点：

* 统一入口
* 自动检测
* 自动修复
* 环境一致性

---

# 2. v3 架构应该调整为

```
                     fw CLI

                       |
                       |

              FlutterWrapper Core


        ┌──────────────┼──────────────┐

        ↓              ↓              ↓

   Doctor Engine   Repair Engine   Provider Adapter


        ↓              ↓              ↓


     vfox           FVM          Manual SDK


        ↓              ↓              ↓


             Flutter SDK Runtime


                       |

                     WSL


                       |

                Android / Gradle
```

核心变化：

**FlutterWrapper 不管理 SDK，只管理 SDK 使用环境。**

---

# 3. v3 最大价值排序

我重新排序一下。

---

# P0：Doctor + Repair ⭐⭐⭐⭐⭐

这是最高价值。

原因：

你的 v2 最大特点：

不是简单 wrapper，而是：

```
大量兼容层
```

兼容层越复杂：

维护成本越高。

所以：

> 自动诊断能力比增加功能更重要。

---

建议：

## fw doctor

输出：

```
FlutterWrapper Doctor


Environment

[✓] WSL Ubuntu-24.04
[✓] Flutter SDK 3.44.6
[✓] Provider vfox


Bridge

[✓] Path mapping
[✓] Daemon translator
[✓] Dart analysis


Android

[✓] SDK bridge
[✓] adb bridge
[✓] NDK


Repairable

[!] package_config mismatch

Run:

fw repair package-config
```

---

## fw repair

设计：

```bash
fw repair <module>
```

不要：

```bash
fw doctor --fix
```

原因：

自动修复风险更高。

推荐：

```
doctor
  ↓
发现
  ↓
用户确认
  ↓
repair
```

例如：

```bash
fw doctor

fw repair dart-sdk
```

更安全。

可以增加：

```bash
fw doctor --fix-safe
```

只执行安全项：

* junction
* symlink
* config

不执行：

* cache clean
* pub get

---

# 4. Provider Adapter 设计非常正确

这里我建议再收敛。

不要做：

```text
fw flutter install
fw flutter uninstall
```

太像重新造 FVM。

建议：

## fw provider

例如：

```bash
fw provider list
```

输出：

```
Detected providers:

✓ vfox
  Flutter 3.44.6

✓ fvm
  Flutter 3.35.0

✓ manual
```

---

## fw flutter current

内部：

```
detect provider

↓

vfox current
or
fvm list
```

---

## fw flutter use

只做：

```
route
```

不要做逻辑。

---

# 5. `.vfox.toml` / `.fvmrc` 检测非常重要

这里我认为比生成配置更有价值。

原因：

团队项目通常已有：

```
.vfox.toml

或者

.fvmrc
```

FlutterWrapper 应该检查：

例如：

项目：

```
project/
├── .vfox.toml
├── pubspec.yaml
```

doctor:

```
[✓]
Project Flutter version managed by vfox

[✓]
Wrapper compatible
```

如果：

```
.vfox.toml

Flutter 3.44.6
```

但是：

```
wrapper.yaml

Flutter 3.41
```

提示：

```
Version mismatch
```

这个很有价值。

---

# 6. CLI 统一非常值得做

现在：

```
install.ps1
doctor.ps1
wrapper.ps1
```

随着项目增长会越来越散。

建议：

最终入口：

```
fw
```

结构：

```
fw

├── doctor
├── repair
├── provider
├── flutter
├── setup
├── status
└── version
```

---

# 7. 我建议增加一个 v3 功能：Environment Snapshot ⭐⭐⭐⭐⭐

这个之前没有提。

但非常适合你的项目。

原因：

WSL + Windows 混合环境最大的问题：

> 今天能跑，明天不知道哪里变了。

增加：

```bash
fw snapshot create
```

生成：

```
.flutterwrapper/environment.json
```

例如：

```json
{
 "windows":{
   "androidStudio":"2026.1.1",
   "androidSdk":"35"
 },

 "wsl":{
   "distro":"Ubuntu-24.04",
   "flutter":"3.44.6",
   "dart":"3.11"
 },

 "provider":{
   "type":"vfox"
 }
}
```

以后：

```bash
fw doctor --compare
```

可以发现：

```
Flutter changed
Android SDK changed
Provider changed
```

这个比团队模板更有价值。

---

# 8. 我建议增加一个 v3 功能：Migration

因为你的方案复杂。

例如：

用户升级：

```
Flutter 3.44
→
Flutter 3.46
```

可能需要：

* dart-sdk junction 更新
* package_config 更新
* daemon 重启

增加：

```bash
fw migrate
```

执行：

```
detect changes

↓

repair affected modules

↓

doctor
```

---

# 9. 最终 v3 路线建议

## v3.0

核心：

```
fw CLI
doctor
repair
provider detect
```

包含：

* 统一入口
* 7 个 repair
* provider adapter

---

## v3.1

环境治理：

```
fw status
fw snapshot
fw compare
```

---

## v3.2

自动化：

```
fw migrate
fw ci check
```

---

# 10. 最终架构边界

## FlutterWrapper 负责：

✅ Windows/WSL桥接
✅ IDE兼容
✅ 路径转换
✅ daemon协议
✅ Dart Analysis适配
✅ Android混合环境
✅ 环境检测
✅ 自动修复

---

## FlutterWrapper 不负责：

❌ Flutter版本管理
❌ SDK下载
❌ SDK缓存
❌ 项目模板
❌ CI生成

这些交给：

```
vfox
FVM
Melos
CI系统
```

---

# 最终评价

你的这版 v3 规划比原版更合理：

| 方向               | 评价     |
| ---------------- | ------ |
| 自建 SDK Manager   | ❌ 放弃正确 |
| Workspace系统      | ❌ 放弃正确 |
| Provider Adapter | ✅ 保留   |
| fw CLI           | ✅ 必做   |
| doctor --fix     | ✅ 高价值  |
| repair体系         | ✅ 核心   |
| snapshot         | ⭐ 建议增加 |
| migration        | ⭐ 建议增加 |

一句话总结：

> **FlutterWrapper v2 解决“能不能用”，v3 应该解决“怎么长期稳定使用”。**

这个方向更符合当前项目已经形成的技术定位。

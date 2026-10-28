# REV — 车机 OBD 实时仪表盘（v2.15.0）

面向 Android 车机 / 手机的实时赛车仪表盘与声浪模拟器：十套皮肤、21 套真实引擎采样声浪、
ELM327 OBD（USB/蓝牙/WiFi）、游戏 UDP 遥测、账号体系与车队看板、DTC 中文故障码、
马力曲线 / 电池健康 / 圈速 / 前台保活。

- 包名 `com.rev.cluster`，versionCode **41** / versionName **2.15.0**
- 最低 SDK 24（Android 7.1 可跑），compile/target SDK 36

> **开源版默认不内置任何服务器地址**（不连作者服务器）。请在设置里填写你自己部署的
> 服务器地址，或用 `--dart-define` 注入；详见 [`OPENSOURCE_DEPLOY.md`](./OPENSOURCE_DEPLOY.md)。

---

## 功能特性

**仪表盘 / 数据**
- 十套皮肤，全横屏适配（1280×720 / 1920×720 等）
- ELM327 OBD：USB-OTG（CH340/CP210x/PL230x/FTDI/CDC）、蓝牙、WiFi；自动 PID 探测
- GPS 快乐表（无 OBD 时用定位算速度）
- 实时仪表：转速 / 速度 / 油门 / 水温 / 涡轮压力 / 油耗 / 电瓶电压等
- 马力曲线、电池健康、DTC 故障码（308 条中文码 + 清除）
- 实时 PID 导出 CSV、自定义 Trigger→Action

**声浪（21 套真实采样）**
- hi（44.1k 立体声）/ lo（22.05k 单声道）双档，设置：高 / 低 / 自动
- band 内随转速**连续变调**（变速升调），跨段 crossfade
- hi 缺失自动回退 lo 并记录日志，任何选档都不会静默无声
- 涡轮/机增车型补 blowoff / whine 声浪层

**游戏 UDP 遥测 / 输入**
- 支持 5 款游戏的 UDP 数据（见下表）
- 蓝牙手柄换挡（按键可自定义）
- 赛道自动识别圈速

| 游戏 | UDP 端口 |
|---|---|
| Forza Horizon / Motorsport | **5300** |
| F1 / DiRT | **20777** |
| Assetto Corsa | **9996** |
| BeamNG.drive | **4564** |
| ETS2 / ATS | **20818** |

**车机化**
- 开机自启 + 前台服务保活（可开关，首次启动权限引导）
- 音频焦点：导航 ducking、来电暂停、挂断恢复、与音乐共存
- 强制横屏、电影感开屏

**云端 / 车队看板**
- 账号体系（scrypt 加盐哈希 + token 会话），数据按账号隔离
- 车队看板（SSE 实时推送）、轨迹回放
- 应用内更新：检查 → 下载 → 安装
- 网络安全：默认关明文、仅豁免本地 OBD 网段；服务器地址不硬编码

**十套皮肤**

| ID | 名称 | ID | 名称 |
|---|---|---|---|
| metro | Metro | cluster | CLUSTER 赛车橙 |
| nerv | NERV | cyanhex | CYAN_HEX 青眼 |
| touge | Touge（水墨山路） | supercar | SUPERCAR 超跑 |
| nervr | NERV-R 赛道 | ambergt | AMBER_GT 金瞳 |
| apex | APEX 赛博 | amberNerv | 琥珀NERV 诊断 |

---

## 所需软件

| 软件 | 版本 | 用途 |
|---|---|---|
| Flutter（stable） | 3.47.x（Dart 3.13） | 构建 Android/iOS |
| Android SDK | platforms 33–36，build-tools 35 | Android 构建 |
| JDK | 17（Android Studio 内置即可） | Gradle |
| Node.js | 18+（推荐 20 LTS） | 后端 / 车队看板 |
| Xcode（仅 macOS） | 15+ | 构建 iOS |
| acme.sh（可选） | 最新 | Let's Encrypt 证书 |

---

## 快速开始

```bash
flutter pub get
flutter run                       # 连设备调试
flutter build apk --release       # 基础 release 包
```

## 标准化发布构建

```bash
# 自用打包：注入你自己的服务器地址（开源构建不 export 即为空）
export REV_DEFAULT_BASE="https://your.domain"
export REV_DEFAULT_ENDPOINT="https://your.domain/api/v1/report"

bash scripts/build_release.sh     # 构建手机/车机/arm64/lite 包
python3 scripts/release_check.py  # 发布自检（不通过非零退出）
```

产物输出到 `dist/`：

| 文件 | 说明 |
|---|---|
| `rev-latest.apk` | 手机包（armv7+arm64，hi+lo） |
| `rev-car.apk` | 车机包（armv7+arm64，仅 lo，.so 压缩，约 26MB） |
| `rev-arm64.apk` | arm64 单架构包（hi+lo） |
| `rev-lite.apk` | 精简包（lo，arm64，.so 压缩） |
| `rev-ios.ipa` | 未签名 iOS 包（GitHub Actions 构建，用全能签/Sideloadly 重签） |

> 发布机需在 `android/key.properties` 配置签名密钥（参考脚本注释）；
> release 构建带 `--obfuscate --split-debug-info`，符号单独存档，混淆后需回归。

## iOS 构建（GitHub Actions，未签名）

仓库已含 `.github/workflows/build-ios-ipa.yml`：推送到 `main` 自动在 macOS 云端构建
**未签名 IPA**，在 Actions 运行页下载 artifact（`REV-ios-ipa`），用
**全能签 / Sideloadly** 自行重签后安装。也可在 Actions 页面手动 Run workflow。

本地手动构建（需 macOS）：

```bash
flutter build ipa --release --no-codesign
# 把 build/ios/archive/Runner.xcarchive/Products/Applications/Runner.app
# 放入 Payload/ 后 zip 成 IPA（workflow 内有完整命令）
```

## 后端 / 车队看板

见 [`OPENSOURCE_DEPLOY.md`](./OPENSOURCE_DEPLOY.md)：启动 `server/server.js`、
创建首个管理员、配置 443 HTTPS、把 App 指向你的服务器。

---

## 目录结构

```
lib/
  main.dart                      # 入口：崩溃兜底 + 横屏 + 音频焦点
  core/
    config/environment.dart      # 环境开关
    skin/                        # 皮肤描述符 + 注册表（十套）
    obd/ game/ track/ perf/ …    # OBD / 游戏 UDP / 圈速 / 性能
  services/
    cloud_service.dart           # 云上报 + 应用内更新
    engine_sound_service.dart    # 声浪合成/采样（连续变调）
    audio_focus_bridge.dart      # 音频焦点
    boot_autostart.dart          # 开机自启
  features/                      # dashboard / settings / auth / track …
android/app/src/main/
  AndroidManifest.xml            # 权限 + BootReceiver + networkSecurityConfig
  kotlin/com/rev/cluster/        # MainActivity / BootReceiver / 前台服务 / 音频焦点
server/
  server.js                      # 零依赖 Node 后端
  dashboard.html                 # 车队看板
scripts/
  build_release.sh               # 标准化发布构建
  release_check.py               # 发布自检
.github/workflows/build-ios-ipa.yml  # iOS 云构建
```

## 许可

个人开源项目，使用请保留出处。引擎采样来自公开声音库，版权归原作者。

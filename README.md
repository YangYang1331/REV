# REV — 车机 OBD 实时仪表盘（v2.15.0）

十套皮肤 · 21 套真实引擎采样声浪 · 账号体系与车队看板 · DTC 中文故障码 · 马力曲线 / 电池健康 / 圈速 / 前台保活。
包名 `com.rev.cluster`，versionCode 41 / versionName 2.15.0。

> 开源版默认不内置任何服务器地址（不连作者服务器）。请在设置里填写你自己部署的服务器地址，
> 或用 `--dart-define=DEFAULT_BASE=... --dart-define=DEFAULT_ENDPOINT=...` 注入；详见 `OPENSOURCE_DEPLOY.md`。

## 快速构建

```bash
cd obd_dashboard
flutter pub get
flutter build apk --release
```

## 标准化发布构建（脚本）

```bash
source ../build_env.sh        # 每个新 shell 先 source（低内存串行配置）
bash scripts/build_release.sh # 手机包(hi+lo) / 车机包(lo-only) / arm64 单架构包
bash scripts/release_check.py # 校验版本/ABI 同构建/签名/zipalign，不通过非零退出
```

产物默认输出到 `rev_src/dist/`：
- `rev-latest.apk` — 手机包（armv7 + arm64，hi+lo 双档采样）
- `rev-car.apk` — 车机包（armv7 + arm64，仅 lo 采样，压缩 .so，≤35MB）
- `rev-arm64.apk` — arm64 单架构包（hi+lo，车机/老设备省流量）
- `rev-lite.apk` — 精简包（仅 arm64 + 仅 lo + 压缩 .so，最小体积，约 19MB）
- `rev-ios.ipa` — iOS 未签名 IPA（由 GitHub Actions 云端构建，需用全能签/Sideloadly 自行重签）

> 发布机需在 `android/key.properties` 放正式签名密钥（证书 SHA-256 以 `3f16feb1` 开头）；
> 无密钥时脚本会提前报错。release 构建带 `--obfuscate --split-debug-info`，
> 符号输出到 `build/symbols_*/` 单独存档。

### iOS 未签名 IPA（云端构建）

无需 Mac：推送代码到 GitHub 后，Actions 工作流 `.github/workflows/build-ios-ipa.yml`
自动在 macOS runner 上执行 `flutter build ipa --no-codesign`，产出未签名 IPA。
下载后用「全能签 / Sideloadly / AltStore」等工具用自己的 Apple ID 重签安装。
IPA 内各 framework 的 `_CodeSignature` 只是 Xcode 自动生成的 CodeResources 资源清单，
不是证书签名，可直接重签。

## 所需软件 / 构建环境

| 软件 | 版本（本项目实测） | 用途 |
|---|---|---|
| Flutter SDK | 3.x（stable） | 跨平台框架 |
| Dart | 随 Flutter 附带 | 业务语言 |
| Android SDK | API 36（compile/target），min API 24 | Android 构建 |
| Android Build-Tools | 35.0.0 | aapt/apksigner/zipalign |
| JDK | 17 | Gradle / Android 构建 |
| Gradle | 8.14.3（wrapper 自带） | 构建系统 |
| Kotlin | 2.2.20 | Android 原生层 |
| Xcode | 最新（仅 macOS，构建 iOS 时需要） | iOS 构建 |
| Node.js | 18+ | 自建云服务器（server.js，零依赖） |
| CocoaPods | 最新（仅 macOS） | iOS 依赖管理 |

> 云服务器是零依赖的 Node.js 单文件（`dist/server.js`，仅用内置模块），
> 部署方式见 `OPENSOURCE_DEPLOY.md`。

## v2.15.0 主要变更

- **看板回退 v2.10 样式**：radial 背景、左色条卡片、大速度字；新增源码包、精简包、iOS 包下载入口。
- **背景图高清化**：修复背景被 `cacheWidth:1366` 强制缩小解码、在 1920 车机上放大导致的模糊；
  nerv（明日香）/ touge（水墨山路）两套背景重做到 2700+ 宽并加 `filterQuality.medium`；
  已排查全部皮肤，仅这两套有背景图，其余 8 套为纯色。
- **开源发行版**：默认不内置任何服务器地址（`String.fromEnvironment` 默认空），
  开源版不连作者服务器、不自动上报；设置页在地址为空时红字提示填写自己部署的地址；
  工程内无明文密码，新增单测验证默认空端点不自动上报。
- **iOS 未签名 IPA**：GitHub Actions 云端构建成功（约 5m35s），可自行重签。
- 服务器直连 IP（HTTP）；网络安全配置放行服务器 IP 与本地 OBD 网段。

## v2.14.0 主要变更

- 声浪：band 内连续变调（随转速平滑升调）；修复关开关仍有声 / 多声部串音；真实采样库替换。
- 应用内更新：检查更新 → 下载 → 安装。
- 游戏：游戏 UDP 遥测、蓝牙手柄换挡、赛道圈速计时。
- 车机化：开机自启 + 前台保活（默认开，国产 ROM 可在设置里引导授权）；
  音频焦点（导航 ducking / 来电暂停 / 挂断恢复，与音乐共存）；强制横屏适配。
- 工程安全：云端服务器地址不硬编码（默认空，用户在设置里填自己部署的地址，
  或用 `--dart-define=DEFAULT_BASE/DEFAULT_ENDPOINT` 注入自用地址）；
  networkSecurityConfig 默认关明文、仅豁免本地 192.168 OBD 网段；APK v3/v4 签名 + 混淆；
  `extractNativeLibs=false`、.so STORED + 4K 页对齐。

## 目录结构

```
lib/
  main.dart                       # 入口：崩溃兜底 + 横屏 + 音频焦点桥
  core/config/environment.dart    # 环境开关
  core/skin/…                     # 皮肤注册表 + 十套皮肤
  services/
    cloud_service.dart            # 云上报 + 应用内更新（默认 HTTPS 域名）
    engine_sound_service.dart     # 声浪合成/采样（setDucking 供焦点桥复用）
    audio_focus_bridge.dart       # 音频焦点事件 → setDucking
    boot_autostart.dart           # 开机自启开关通道
  features/settings/…             # 设置 / 服务器地址 / 引擎包
android/app/src/main/
  AndroidManifest.xml             # 权限 + BootReceiver + networkSecurityConfig
  kotlin/com/rev/cluster/
    MainActivity.kt              # 前台服务/设备/音频焦点 平台通道
    BootReceiver.kt              # 开机自启
    RevForegroundService.kt       # 前台保活
    AudioFocusManager.kt          # AUDIOFOCUS 监听
```

## 注意

- 最低 SDK 24（马6 车机 Android 7.1 可跑），compile/target SDK 36。
- 引擎采样 hi（44.1k 立体声）/ lo（22.05k 单声道）双档；手机包内置 hi+lo，车机包仅 lo。

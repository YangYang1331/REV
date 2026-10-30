# REV — 车机 OBD 实时仪表盘（v2.15.4）

十套皮肤 · 26 套真实引擎采样声浪 · 账号体系与车队看板 · DTC 中文故障码 · 马力曲线 / 电池健康 / 圈速 / 前台保活。
包名 `com.rev.cluster`，versionCode 45 / versionName 2.15.4。

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
- `rev-car.apk` — 车机包（armv7 + arm64，仅 lo 采样，临时切 hi 后恢复）
- `rev-arm64.apk` — arm64 单架构包（车机/老设备省流量）

> 发布机需在 `android/key.properties` 放正式签名密钥（证书 SHA-256 以 `3f16feb1` 开头）；
> 无密钥时脚本会提前报错。release 构建带 `--obfuscate --split-debug-info`，
> 符号输出到 `build/symbols/` 单独存档。

## v2.15.4 主要变更

- 声浪只由转速驱动：音高 = 排气脉冲频率（rpm/60 × 缸数/2），去掉车速关联；
  节气门负荷只改变脉冲强度与高频含量，挡位只用于低速高挡「闷音」判断。
- 全部采样母带统一：各 band 响度对齐到 −13 dBFS，32 Hz 高通去除次声，
  软限幅保留脉冲峰值；11 个近乎无声的 band 用同包素材变调补齐。
- 修掉 2JZ（toyota_supra）整包：五个 band 全是底噪，已从清单移除。
- 看板数据链路：演示模式默认上报；token 失效自动登出；设置页新增上报状态
  与「测试上报」。
- 车队看板重做视觉（暗色霓虹 / 玻璃卡片 / 动效），保留全部接口。

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

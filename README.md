# REV — 车机 OBD 实时仪表盘（私有自用版 v2.15.0）

> 本仓库是 **REV 的私有自用版**，与公开开源版 [YangYang1331/REV](https://github.com/YangYang1331/REV) 代码同源，
> 额外包含**正式签名密钥、自用云构建工作流**，用于随时调取签名、云端出包。
> 公开仓库是干净的开源版（不含签名、不含私有地址）。

包名 `com.rev.cluster`，versionCode **41** / versionName **2.15.0**。

十套皮肤 · 21 套真实引擎采样声浪（hi/lo 双档）· 账号体系与车队看板 ·
DTC 中文故障码 · 马力曲线 / 电池健康 / 圈速 / 前台保活 · 游戏 UDP 接入 · 未签名 iOS IPA。

## 签名（关键）

正式签名密钥位于 `signing/`，证书 SHA-256 前缀 `3f16feb`，用于覆盖安装与应用内更新。
- 若 `signing/rev-debug.keystore` 缺失，按 [signing/README.md](signing/README.md)
  在构建过历史包的云电脑上运行 `bash signing/upload_signing_key.sh` 一键取回；
- 取回后 Android 云构建工作流会自动使用该签名，无需配置 Secret。

## 快速构建

```bash
flutter pub get
# 用正式签名（密钥已在 signing/ 时）
cp signing/key.properties android/key.properties
flutter build apk --release
```

## 标准化发布构建

```bash
bash scripts/build_release.sh   # 手机包(hi+lo)/车机包(lo)/arm64/lite
python3 scripts/release_check.py # 发布自检：版本/ABI 同构建/签名/zipalign
```

产物输出到 `dist/`：

| 文件 | 说明 |
|---|---|
| `rev-latest.apk` | 手机包（armv7+arm64，hi+lo） |
| `rev-car.apk` | 车机包（armv7+arm64，仅 lo，.so 压缩） |
| `rev-arm64.apk` | arm64 单架构包（hi+lo） |
| `rev-lite.apk` | 精简包（lo，arm64，.so 压缩） |
| `rev-ios.ipa` | 未签名 iOS 包（用全能签/Sideloadly 重签） |

## 云构建（GitHub Actions）

- `.github/workflows/build-android.yml` — Ubuntu 云端构建正式签名 APK（自动用 signing/ 密钥）；
- `.github/workflows/build-ios-ipa.yml` — macOS 云端构建未签名 IPA。

## 自建后端 / 车队看板

零依赖 Node.js 单文件在 `server/server.js`，部署见 `OPENSOURCE_DEPLOY.md`。
首个管理员通过环境变量 `ADMIN_USER` / `ADMIN_PASSWORD` 创建，无硬编码密码。

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
signing/                          # 正式签名密钥（私有）
server/                           # 零依赖 Node.js 后端 + 看板
android/app/src/main/
  AndroidManifest.xml             # 权限 + BootReceiver + networkSecurityConfig
  kotlin/com/rev/cluster/
    MainActivity.kt              # 前台服务/设备/音频焦点 平台通道
    BootReceiver.kt              # 开机自启
    RevForegroundService.kt       # 前台保活
    AudioFocusManager.kt          # AUDIOFOCUS 监听
```

## 其他文档

- [RELEASE.md](RELEASE.md) — 发版一页纸
- [README-IOS.md](README-IOS.md) — iOS 构建说明
- [操作手册-另一台云电脑.md](操作手册-另一台云电脑.md) — 环境操作手册
- [OPENSOURCE_DEPLOY.md](OPENSOURCE_DEPLOY.md) — 后端部署与安全自查

## 注意

- 最低 SDK 24（车机 Android 7.1 可跑），compile/target SDK 36。
- 引擎采样 hi（44.1k 立体声）/ lo（22.05k 单声道）双档；手机包内置 hi+lo，车机包仅 lo。

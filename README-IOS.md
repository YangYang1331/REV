# REV iOS 版构建指南（无需自己有 Mac）

你的 GitHub 账号：**YangYang1331**
包名：`com.rev.cluster`　显示名：REV　版本：2.14.0+40

iOS 工程已配好（`ios/` 目录），蓝牙/定位权限、横屏、后台声浪都已在 Info.plist 声明。
本机构不出 .ipa（iOS 必须 macOS/Xcode），走 GitHub 免费 macOS 云跑器构建。

## 第一步：建仓库并推送（在电脑上执行一次）

```bash
# 进入本工程根目录（含 ios/、lib/、android/ 的这层）
git init
git add -A
git commit -m "REV 2.14.0 + iOS 工程"

# 把下面命令里的 YOUR_TOKEN 换成你在 GitHub 生成的 Personal Access Token
# （github.com → Settings → Developer settings → Personal access tokens → 勾选 repo 权限）
git branch -M main
git remote add origin https://YangYang1331:YOUR_TOKEN@github.com/YangYang1331/rev-cluster.git
git push -u origin main
```

> 仓库可设为 Public（公开），macOS 跑器对公开仓库免费；Private 仓库每月有免费额度，通常够用。

## 第二步：等云构建自动跑完

推送后，到仓库页面：
**Actions → REV iOS IPA (macOS 云构建) → 等待绿勾**（首次约 10–20 分钟，要装 Flutter + CocoaPods）。

如果没自动跑，进 Actions 页手动点 **Run workflow**。

## 第三步：下载 IPA

构建完成页 → 下方 **Artifacts**：
- `REV-ios-ipa` → 解压得到 `Runner.ipa`（这就是你要的安装包，未签名）。

## 第四步：用全能签签名装到 iPhone

1. iPhone 上按你截图那页流程：装配置文件 → 安装全能签 → 导入你的证书；
2. 用全能签导入 `Runner.ipa`，选证书签名 → 安装。

## 已知 iOS 限制（与 Android 版差异）

- **USB 有线 OBD（OTG 转接头）在 iPhone 上不可用**——iOS 没有 USB 主机串口；
  蓝牙 ELM327（BLE）完全正常。
- 开机自启 / 前台保活是 Android 专属，iOS 无对应能力（属系统限制，非缺陷）。
- 免费/企业证书签名有有效期，掉签后需用全能签重签。

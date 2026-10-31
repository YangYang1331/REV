# REV 应用签名密钥（私有，请勿公开）

本目录保存 REV 应用的**正式发布签名密钥**，用于保证所有版本能用同一签名覆盖安装、
以及应用内更新能正常升级。

## 签名信息

- 类型：Android debug-style keystore（历史发布一直沿用，等同于正式签名）
- 别名（alias）：`androiddebugkey`
- 密钥库密码：`android`
- 密钥密码：`android`
- 证书 SHA-256（指纹前缀）：`3f16feb181c9f0fee3fac4727d4d003031bbd6d1f53c405d78d7a7c4ece8e917`
- 对应文件：`rev-debug.keystore`

> 服务器上现存所有 v2.15.0(41) 包均使用此签名（SHA-256 前缀 `3f16feb`）。
> 更换密钥会导致无法覆盖安装，必须卸载重装，因此务必长期保留此密钥。

## 文件

- `rev-debug.keystore` — 正式签名密钥（**当前缺失，需从构建机取回**，见下）
- `key.properties` — Gradle 读取的签名配置（构建时由脚本生成/复制到 android/）
- `upload_signing_key.sh` — 一键把密钥从构建机取回并提交到本仓库的脚本

## 如何取回密钥（在"构建过历史包的那台云电脑"上运行）

历史签名密钥当前只存在于构建过 v2.13/v2.14/v2.15 包的那台云电脑，路径通常为：

- `~/.config/.android/debug.keystore`，或
- `~/.android/debug.keystore`

在那台云电脑上：

```bash
# 1) 克隆本私有仓库（需要 GitHub 登录）
git clone https://github.com/YangYang1331/rev-cluster.git
cd rev-cluster

# 2) 运行一键取回脚本（自动定位指纹为 3f16feb 的密钥并提交推送）
bash signing/upload_signing_key.sh
```

脚本会自动：在常见路径中找到 SHA-256 以 `3f16feb` 开头的 keystore →
复制为 `signing/rev-debug.keystore` → 生成 `key.properties` → 提交并推送到本仓库。

## 取回后如何在新机器上用此签名构建

```bash
git clone https://github.com/YangYang1331/rev-cluster.git
cd rev-cluster
cp signing/key.properties android/key.properties
# signing/rev-debug.keystore 已在仓库内；build_release.sh 会读取 android/key.properties
bash scripts/build_release.sh
```

## 安全提示

- 本目录**只存在于私有仓库 rev-cluster**，绝不同步到公开仓库 REV；
- 私有仓库的访问权限请只保留本人账号；
- 若怀疑密钥泄露，需要更换签名，则所有老用户必须卸载重装，请谨慎。

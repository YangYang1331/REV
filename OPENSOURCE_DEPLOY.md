# REV 开源版部署指南

本文件指导你把 REV 车机仪表盘跑起来，并把车队看板数据上报到**你自己的服务器**。

> REV 的云端服务器地址**不硬编码**：默认构建里 `defaultBase` / `defaultEndpoint`
> 都是空字符串，App 启动**不会**连接任何作者服务器、不会自动上报。
> 你要么在 App 设置里填自己部署的地址，要么用 `--dart-define` 注入。

---

## 1. 准备后端（server/server.js）

后端在仓库 `server/` 目录，零依赖 Node.js（仅内置 `http/https/fs/path/url/crypto`）。它提供：

| 方法 | 路径 | 说明 |
|---|---|---|
| POST | `/api/v1/report` | 接收车辆实时帧（需登录 token） |
| POST | `/api/auth/register` | 注册账号 |
| POST | `/api/auth/login` | 登录，返回 token |
| POST | `/api/auth/logout` | 注销会话 |
| GET  | `/api/v1/devices` | 当前账号下的设备列表 |
| GET  | `/api/v1/stream` | SSE 实时推送（按账号过滤） |
| GET  | `/api/v1/latest` | 应用内更新检查（版本号/下载地址） |
| GET  | `/download/...` | APK / IPA / 源码包下载 |
| GET  | `/` | 车队看板页面 |

### 1.1 环境

- Node.js 18 LTS 或更高（推荐 20 LTS）。
- 一个可被车机/手机访问的地址：公网域名 + HTTPS，或内网 IP:端口。

### 1.2 目录结构（自包含）

```
server/
  server.js
  dashboard.html
  data/                    # 首次运行自动创建：users.json / sessions.json
  download/                # 放 APK/IPA/源码包（见该目录 README）
  certs/                   # 放 fullchain.pem / key.pem（启用 443 时）
```

### 1.3 启动

```bash
cd server

# 非 root：仅监听 8080（可用 PORT 改）
node server.js

# root：同时监听 80 + 8080 + 443（443 需证书，缺失则自动跳过）
sudo node server.js
```

### 1.4 创建首个管理员（无硬编码密码）

server.js **不内置任何默认账号/密码**。首次启动时通过环境变量创建管理员：

```bash
ADMIN_USER=admin ADMIN_PASSWORD=你的强密码 node server.js
```

不设置则不创建管理员，用户可走 `/api/auth/register` 自行注册。

健康检查：`curl http://你的地址:端口/api/v1/latest` 应返回 JSON。

---

## 2. 配置 443 HTTPS（推荐）

车机/手机走 HTTPS 最稳妥。用 Let's Encrypt 免费证书。

> 经验：放在**大陆云服务器**且域名未备案时，80 端口的明文 HTTP 会被云厂商拦截；
> 但 **443 加密流量不被拦截**。因此可直接用 `acme.sh` 的 **TLS-ALPN-01**（走 443）验证。

```bash
# 安装 acme.sh
git clone --depth 1 https://github.com/acmesh-official/acme.sh.git
cd acme.sh && ./acme.sh --install -m you@example.com

# 签发（确保 443 空闲）
~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
~/.acme.sh/acme.sh --issue --alpn -d your.domain -d www.your.domain

# 安装到后端证书目录，续期后自动重启
mkdir -p server/certs
~/.acme.sh/acme.sh --install-cert -d your.domain --ecc \
  --key-file server/certs/key.pem \
  --fullchain-file server/certs/fullchain.pem \
  --reloadcmd "systemctl restart rev-cloud"
```

acme.sh 安装时自动加 cron，证书到期前自动续期。

---

## 3. 配置 App 连到你自己的服务器（二选一）

### 方式 A：运行时在设置里填（推荐，不改代码）

1. 打开 App → 设置 → **云服务器地址**（编辑图标）。
2. 填完整上报地址，例如：

   ```
   https://your.domain/api/v1/report
   ```

   （内网也行：`http://192.168.1.10:8080/api/v1/report`）

3. 保存后登录/注册账号，数据即上报到你的后端。
   - 地址留空 = 不上报、不检查更新。

### 方式 B：构建时注入默认地址（自用打包）

构建时传入 `DEFAULT_BASE` / `DEFAULT_ENDPOINT`：

```bash
flutter build apk --release \
  --dart-define=DEFAULT_BASE=https://your.domain \
  --dart-define=DEFAULT_ENDPOINT=https://your.domain/api/v1/report
```

这样 App 启动就默认连你的服务器；用户在设置里仍可改成别的地址。

---

## 4. 用脚本构建（含注入）

```bash
# 自用打包：先 export 地址，再跑脚本（开源构建不 export 即为空）
export REV_DEFAULT_BASE="https://your.domain"
export REV_DEFAULT_ENDPOINT="https://your.domain/api/v1/report"
bash scripts/build_release.sh
python3 scripts/release_check.py
```

开源源码包内**不含**任何作者域名/IP/密码。

---

## 5. 安全自查清单（开源发行前）

- [ ] 源码/配置里 grep 不到任何作者域名/IP/密码：

  ```bash
  grep -rE "mayangyang|139\.224\.30\.235|Myy@|1314520" lib/ android/ scripts/ server/
  ```

  （应无输出；文档中提及这些串仅作反面示例。）
- [ ] 后端数据目录已备份、已前置 HTTPS。
- [ ] 你自己掌握后端账号体系，不依赖任何第三方服务。
- [ ] 签名密钥（`android/key.properties`、keystore）未提交到仓库。

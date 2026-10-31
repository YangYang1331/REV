# REV 开源版部署指南

本文件指导你把 REV 车机仪表盘跑起来，并把车队看板数据上报到**你自己的服务器**。

> REV 的云端服务器地址**不硬编码**：默认构建里 `defaultBase` / `defaultEndpoint`
> 都是空字符串，App 启动**不会**连接任何作者服务器、不会自动上报。
> 你要么在 App 设置里填自己部署的地址，要么用 `--dart-define` 注入。

---

## 1. 准备后端（server.js）

后端就是仓库里的 `server.js`（Node.js）。它提供：

- `POST /api/v1/report` —— 接收车辆实时帧
- `POST /api/auth/register|login|logout` —— 账号
- `GET  /api/v1/latest` —— 应用内更新检查（可选）

### 1.1 环境

- Node.js 18 LTS 或更高（推荐 20 LTS）。
- 一个可被车机/手机访问的地址：公网域名 + HTTPS，或内网 IP:端口。

### 1.2 数据目录

`server.js` 默认把账号/看板数据写到进程工作目录下的 JSON 文件（首次运行自动创建）。
请把数据目录放在持久磁盘上，并建议前置反向代理（Nginx/Caddy）+ HTTPS（Let's Encrypt）：

```bash
git clone <your-fork-of-this-repo>
cd obd_dashboard
node server.js            # 监听端口见 server.js 顶部配置
```

健康检查：`curl http://你的地址:端口/api/v1/latest` 应返回 JSON。
> **反向代理与真实 IP**：服务端默认只信任来自本机回环地址的 `X-Forwarded-For`，
> 公网直连时完全忽略客户端自带的转发头（防止伪造 IP 绕过登录/注册限流）。
> 如果 Nginx/Caddy 与 Node 不在同一台机器或不在回环地址上，请把代理出口 IP
> 加入环境变量 `TRUSTED_PROXIES`（逗号分隔，例如 `TRUSTED_PROXIES=10.0.0.2`）。
> 只有明确走 Cloudflare 时才设置 `TRUST_CF_CONNECTING_IP=1`。
> 反向代理请用 `proxy_set_header X-Forwarded-For $remote_addr;` **覆盖**客户端头，
> 不要用 `$proxy_add_x_forwarded_for` 追加，否则最外层伪造值仍可能被带入。


---

## 2. 配置 App 连到你自己的服务器（二选一）

### 方式 A：运行时在设置里填（推荐，不改代码）

1. 打开 App → 设置 → **云服务器地址**（编辑图标）。
2. 填完整上报地址，例如：

   ```
   https://你的域名/api/v1/report
   ```

   （内网也行：`http://192.168.1.10:8080/api/v1/report`）

3. 保存后登录/注册账号，数据即上报到你的后端。
   - 地址留空 = 不上报、不检查更新（设置页红字提示"请填写你自己部署的服务器地址"）。

### 方式 B：构建时注入默认地址（自用打包）

构建时传入 `DEFAULT_BASE` / `DEFAULT_ENDPOINT`：

```bash
flutter build apk --release \
  --dart-define=DEFAULT_BASE=https://你的域名 \
  --dart-define=DEFAULT_ENDPOINT=https://你的域名/api/v1/report
```

这样 App 启动就默认连你的服务器；用户在设置里仍可改成别的地址。

---

## 3. 构建

```bash
cd obd_dashboard
flutter build apk --release
# 自用打包再加上上面的 --dart-define 注入
```

开源源码包内**不含**任何作者域名/IP——默认值就是空字符串。

---

## 4. 安全自查清单（开源发行前）

- [ ] 源码/配置里 grep 不到任何明文域名/IP/密码：
  ```bash
  grep -rEi "mayangyang|139\.224\.30\.235|Deploy@|旧默认口令" .
  ```
  （应无输出；`OPENSOURCE_DEPLOY.md` 本身提及这些串仅作反面示例。）
- [ ] 后端数据目录已备份、已前置 HTTPS。
- [ ] 你自己掌握后端账号体系，不依赖任何第三方服务。

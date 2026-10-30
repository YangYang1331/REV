# REV API v2.16.0 文档

## 版本信息
- **versionName**: `2.16.0`
- **versionCode**: `51`
- **发布日期**: 2026-10-30

## 新增功能

### A. 历史趋势 API

#### `GET /api/v1/history`

获取设备的历史趋势数据（分钟级聚合）。

**权限要求**：
- 需要登录（Bearer token）
- 设备 owner、被共享用户、admin 可访问
- viewer 角色可访问已授权设备

**请求参数**：
| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `deviceId` | string | 是 | 设备 ID |
| `hours` | number | 否 | 查询时间范围（小时），默认 24，范围 1-168（7 天） |

**响应示例**：
```json
{
  "ok": true,
  "deviceId": "TEST-001",
  "hours": 24,
  "stepMin": 3,
  "points": [
    {
      "t": 1793354460000,
      "ct": 81.0,
      "ot": 91.0,
      "volt": 14.00,
      "spd": 70.0
    }
  ]
}
```

**字段说明**：
- `stepMin`: 桶合并步长（分钟），确保返回点数 ≤ 500
- `points`: 趋势点数组
  - `t`: 时间戳（毫秒）
  - `ct`: 水温（°C），null 表示无数据
  - `ot`: 油温（°C），null 表示无数据
  - `volt`: 电压（V），null 表示无数据
  - `spd`: 车速（km/h），null 表示无数据

**数据存储**：
- 文件：`data/history.json`
- 每设备最多保留 7 天（10080 个分钟桶）
- 每 5 分钟自动落盘，SIGTERM 时立即保存
- 环形缓冲：超出 10080 桶时丢弃最旧数据

---

### B. 车队共享 API

#### `POST /api/v1/share`

将设备共享给其他用户（只读权限）。

**权限要求**：
- 需要登录（Bearer token）
- 仅设备 owner 或 admin 可操作
- viewer 角色禁止操作

**请求体**：
```json
{
  "deviceId": "TEST-001",
  "username": "u_b",
  "perm": "view"
}
```

**响应示例**：
```json
{
  "ok": true
}
```

---

#### `GET /api/v1/shares`

获取设备的共享列表。

**权限要求**：
- 需要登录（Bearer token）
- 仅设备 owner 或 admin 可查看

**请求参数**：
| 参数 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `deviceId` | string | 是 | 设备 ID |

**响应示例**：
```json
{
  "ok": true,
  "shares": [
    {
      "username": "u_b",
      "perm": "view"
    },
    {
      "username": "viewer1",
      "perm": "view"
    }
  ]
}
```

---

#### `DELETE /api/v1/share`

撤销设备共享。

**权限要求**：
- 需要登录（Bearer token）
- 仅设备 owner 或 admin 可操作
- viewer 角色禁止操作

**请求体**：
```json
{
  "deviceId": "TEST-001",
  "username": "u_b"
}
```

**响应示例**：
```json
{
  "ok": true
}
```

---

### C. 角色权限系统

#### 用户角色

| 角色 | 说明 | 权限 |
|------|------|------|
| `admin` | 管理员 | 所有操作权限，可查看所有设备 |
| `user` | 普通用户 | 可上报、查看自己的设备、管理共享 |
| `viewer` | 只读用户 | 仅可查看已授权设备，不能上报/共享 |

**角色设置**（`POST /api/auth/role`，仅 admin）：

```json
{ "username": "viewer1", "role": "viewer" }
```

- 允许值：`admin` / `user` / `viewer`；注册时默认为 `user`
- 修改会立即更新该账号已有的登录会话，无需重新登录
- 拒绝降级最后一个 `admin`（防止把系统锁死）
- 返回：`{ "ok": true, "username": "viewer1", "role": "viewer" }`

#### 设备权限字段

设备列表 API 返回的每个设备包含 `perm` 字段：

| perm 值 | 说明 |
|---------|------|
| `owner` | 当前用户是设备所有者 |
| `share` | 当前用户被共享访问该设备 |
| `admin` | 当前用户是管理员（查看所有设备） |

**示例响应**：
```json
[
  {
    "deviceId": "TEST-001",
    "perm": "owner",
    "owner": "u_a",
    "speed": 70,
    "coolant": 81,
    ...
  },
  {
    "deviceId": "TEST-002",
    "perm": "share",
    "owner": "u_b",
    "speed": 60,
    ...
  }
]
```

---

## 修改的 API

### `GET /api/v1/devices`

**新增字段**：
- `perm`: 当前用户对设备的权限（`owner` / `share` / `admin`）

**行为变更**：
- viewer 角色可访问已授权的设备列表
- 被共享的设备会出现在列表中（`perm: "share"`）

---

### `GET /api/v1/track/:deviceId`

**权限变更**：
- 被共享用户可访问设备轨迹（之前仅 owner/admin）

---

### `POST /api/v1/report` 和 `POST /api/v1/report/batch`

**权限变更**：
- viewer 角色返回 `403`（`viewer 账号无权上报数据`）

---

## 数据文件说明

### `data/history.json`

存储设备历史趋势数据。

**结构**：
```json
{
  "TEST-001": [
    {
      "t": 1793354460000,
      "ct_s": 81,
      "ct_n": 1,
      "ot_s": 91,
      "ot_n": 1,
      "volt_s": 14,
      "volt_n": 1,
      "spd_s": 70,
      "spd_n": 1
    }
  ]
}
```

**字段说明**：
- `t`: 分钟起始时间戳（毫秒）
- `ct_s` / `ct_n`: 水温和 / 样本数
- `ot_s` / `ot_n`: 油温和 / 样本数
- `volt_s` / `volt_n`: 电压和 / 样本数
- `spd_s` / `spd_n`: 车速和 / 样本数

**平均值计算**：
```javascript
ct = ct_n > 0 ? round(ct_s / ct_n, 1) : null
```

**文件大小控制**：
- 每设备最多 10080 条记录（7 天）
- 超出时自动丢弃最旧记录
- 设备被回收时同步清理历史数据

---

### `data/devices.json`

**新增字段**：
```json
{
  "deviceId": "TEST-001",
  "owner": "u_a",
  "shares": {
    "u_b": "view",
    "viewer1": "view"
  },
  "latest": { ... },
  "track": [ ... ],
  "spark": [ ... ]
}
```

**`shares` 字段**：
- 键：被共享用户的 username
- 值：权限类型（目前仅支持 `"view"`）

---

## 看板 UI 更新

### 新增功能

1. **分享按钮**（设备卡片右上角）
   - 仅 owner/admin 可见
   - viewer 角色隐藏
   - 点击弹出分享管理弹窗

2. **趋势按钮**（设备卡片右上角）
   - 所有用户可见
   - 点击弹出 24 小时趋势图
   - Canvas 绘制三条折线：水温（青色）、油温（红色）、电压（绿色）

3. **只读共享标记**
   - 被共享设备显示"只读共享"徽章
   - 隐藏分享/删除等写操作按钮

4. **角色显示**
   - 顶栏显示当前用户角色（ADMIN / USER / VIEWER）
   - viewer 角色使用青色样式区分

---

## 兼容性说明

### 向后兼容
- 所有现有 API 保持兼容
- `data/users.json` 中缺少 `role` 字段的老用户自动按 `user` 处理
- `data/devices.json` 中缺少 `shares` 字段的老设备自动初始化为 `{}`

### 会话兼容性
- 老会话（无 `role` 字段）自动补全为 `user`
- 修改用户角色后需重新登录生效

---

## 已知限制

1. **历史数据精度**
   - 分钟级聚合，同一分钟内的多个样本取平均值
   - 温度取平均值，电压取平均值，车速取平均值
   - 空值（null）不参与平均计算

2. **历史数据保留**
   - 最多保留 7 天（10080 分钟）
   - 设备回收时同步清理历史
   - 进程重启时从 `data/history.json` 恢复

3. **共享权限**
   - 目前仅支持 `view`（只读）权限
   - 被共享用户不能修改设备、不能再次共享给第三方

4. **viewer 角色管理**
   - 无 API 接口修改用户角色
   - 需手动编辑 `data/users.json` 并重启服务

5. **趋势图时间范围**
   - 看板固定查询 24 小时
   - API 支持 1-168 小时（7 天）

---

## 测试验证

### 自测命令
```bash
# 启动测试服务器
cd /tmp/srv2160
PORT=8097 ADMIN_PASSWORD=testpw123 node server.js &

# 注册用户
curl -X POST http://localhost:8097/api/auth/register \
  -H "Content-Type: application/json" \
  -d '{"username":"test_user","password":"password123"}'

# 上报数据
TOKEN=$(curl -s -X POST http://localhost:8097/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"username":"test_user","password":"password123"}' | jq -r .token)

curl -X POST http://localhost:8097/api/v1/report \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"deviceId":"TEST-001","ts":1234567890000,"coolant":85,"oilTemp":95,"voltage":14.2,"speed":70}'

# 查询历史
curl "http://localhost:8097/api/v1/history?deviceId=TEST-001&hours=24" \
  -H "Authorization: Bearer $TOKEN"

# 共享设备
curl -X POST http://localhost:8097/api/v1/share \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"deviceId":"TEST-001","username":"other_user","perm":"view"}'
```

### 验证清单
- [x] `node --check server.js` 通过
- [x] 历史趋势 API 返回正确点数
- [x] 共享权限控制正确（403 / 200）
- [x] viewer 角色限制生效（不能上报/共享）
- [x] 设备列表返回 `perm` 字段
- [x] 看板分享/趋势按钮显示正确
- [x] 数据文件正确持久化

---

## 文件清单

| 文件 | 行数 | 说明 |
|------|------|------|
| `server.js` | 919 | 服务端主程序（+167 行） |
| `dashboard.html` | 842 | 看板页面（+232 行） |
| `API-2.16.0.md` | 本文档 | API 说明 |

**主要改动**：
- `server.js`: +167 行（历史 API +60，共享 API +80，权限系统 +27）
- `dashboard.html`: +232 行（分享弹窗 +50，趋势图 +100，UI 调整 +82）

---

**构建版本**: v2.16.0 · BUILD 51  
**更新时间**: 2026-10-30

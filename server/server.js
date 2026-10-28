/*
 * REV 云端服务 v2.15.0 —— 零依赖 Node.js（v18+，仅内置 http/https/fs/path/url/crypto）
 *
 * 能力：
 *  - 账号密码体系（scrypt 加盐哈希，token 会话，users.json / sessions.json 落盘）
 *  - 数据隔离：普通用户只看自己上报的设备，管理员看全部
 *  - SSE 按客户端会话过滤推送（不再一份广播给所有人）
 *  - report / devices / stream / track 全部接入鉴权
 *  - ingest / 轨迹 / latest / download / 看板 全部逻辑
 *  - 443 HTTPS：读取同目录 certs/fullchain.pem、certs/key.pem（Let's Encrypt）
 *
 * 开源安全：本文件不内置任何默认账号/密码。首个管理员通过环境变量创建：
 *   ADMIN_USER=admin ADMIN_PASSWORD=your-strong-pass node server.js
 * 不设置则不创建管理员，可走 /api/auth/register 自行注册。
 *
 * 运行：
 *   node server.js                       # 非 root：仅 8080（PORT 可改）
 *   sudo node server.js                 # root：80 + 8080 + 443（需证书）
 */
const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const https = require('https');

const PORT = process.env.PORT || 8080;
const TRACK_LIMIT = 2000;
const ONLINE_MS = 10000;
const DATA_DIR = path.join(__dirname, 'data');
const USERS_FILE = path.join(DATA_DIR, 'users.json');
const SESSIONS_FILE = path.join(DATA_DIR, 'sessions.json');

const devices = new Map();         // deviceId -> { owner, latest, track:[] }
const sseClients = new Set();      // { res, username, role }

/* ---------------- 持久化（容错，原子写） ---------------- */
function ensureDataDir() {
  try { fs.mkdirSync(DATA_DIR, { recursive: true }); } catch (e) {}
}
function loadJson(fp, fallback) {
  try {
    if (fs.existsSync(fp)) return JSON.parse(fs.readFileSync(fp, 'utf8'));
  } catch (e) { console.error('[load]', fp, e.message); }
  return fallback;
}
function writeJsonAtomic(fp, obj) {
  try {
    ensureDataDir();
    const tmp = fp + '.tmp';
    fs.writeFileSync(tmp, JSON.stringify(obj, null, 2));
    fs.renameSync(tmp, fp);
  } catch (e) { console.error('[persist]', fp, e.message); }
}

/* ---------------- 账号体系 ---------------- */
// users: [{username, salt, scryptHash, role, createdAt, boundDevices:[]}]
let userList = loadJson(USERS_FILE, { users: [] }).users || [];
// sessions: { token: {username, role, createdAt} }
let sessions = loadJson(SESSIONS_FILE, {});

function persistUsers() { writeJsonAtomic(USERS_FILE, { users: userList }); }
function persistSessions() { writeJsonAtomic(SESSIONS_FILE, sessions); }

function findUser(username) {
  const u = String(username || '').trim().toLowerCase();
  return userList.find(x => x.username.toLowerCase() === u);
}
function hashPassword(password, salt) {
  return crypto.scryptSync(String(password), salt, 64).toString('hex');
}
function verifyPassword(password, salt, hash) {
  try {
    const h = Buffer.from(hashPassword(password, salt), 'hex');
    const ref = Buffer.from(hash, 'hex');
    return h.length === ref.length && crypto.timingSafeEqual(h, ref);
  } catch (e) { return false; }
}
function createToken() { return crypto.randomBytes(32).toString('hex'); }

// 首次启动：若设置环境变量 ADMIN_USER/ADMIN_PASSWORD 则创建首个管理员；
// 否则不创建任何内置账号（无硬编码密码），用户可通过 /api/auth/register 自行注册。
(function bootstrapAdmin() {
  const adminUser = process.env.ADMIN_USER;
  const adminPass = process.env.ADMIN_PASSWORD;
  if (adminUser && adminPass && !findUser(adminUser)) {
    const salt = crypto.randomBytes(16).toString('hex');
    userList.push({
      username: adminUser,
      salt,
      scryptHash: hashPassword(adminPass, salt),
      role: 'admin',
      createdAt: Date.now(),
      boundDevices: []
    });
    persistUsers();
    console.log(`[auth] 已按环境变量初始化管理员账号 ${adminUser}`);
  }
})();

// 从 Authorization: Bearer <t> 或 ?token= 解析会话
function getSession(req, url) {
  let token = null;
  const auth = req.headers['authorization'] || '';
  const m = String(auth).match(/^Bearer\s+(.+)$/i);
  if (m) token = m[1].trim();
  if (!token) token = url.searchParams.get('token');
  if (!token) return null;
  return sessions[token] || null;
}

/* ---------------- 数据 ingest ---------------- */
function readBody(req) {
  return new Promise((resolve, reject) => {
    let buf = '';
    req.on('data', c => { buf += c; if (buf.length > 1e6) req.destroy(); });
    req.on('end', () => resolve(buf));
    req.on('error', reject);
  });
}
function round(v, n = 1) {
  if (v == null || Number.isNaN(v)) return null;
  const k = Math.pow(10, n);
  return Math.round(v * k) / k;
}
function ingest(p) {
  const id = p.deviceId || 'unknown';
  if (!devices.has(id)) devices.set(id, { track: [] });
  const dev = devices.get(id);
  const lat = p.lat, lng = p.lng;
  dev.latest = {
    deviceId: id, ts: p.ts || Date.now(),
    source: p.source || 'obd',
    connected: p.connected !== false,
    owner: dev.owner || null,
    gear: p.gear == null ? null : p.gear,
    speed: round(p.speed), rpm: round(p.rpm),
    coolant: round(p.coolant), oilTemp: round(p.oilTemp),
    intakeTemp: round(p.intakeTemp), ambient: round(p.ambient),
    voltage: round(p.voltage), boost: round(p.boost),
    load: round(p.load), throttle: round(p.throttle),
    fuelLevel: round(p.fuelLevel),
    maf: round(p.maf, 2), fuelLph: round(p.fuelLph, 2), fuelRate: round(p.fuelRate, 2),
    tripKm: round(p.tripKm, 2), tripFuel: round(p.tripFuel, 3), tripSec: round(p.tripSec, 0),
    lat: lat != null ? round(lat, 5) : null,
    lng: lng != null ? round(lng, 5) : null,
    heading: round(p.heading)
  };
  if (lat != null && lng != null) {
    dev.track.push({ lat: round(lat, 5), lng: round(lng, 5), ts: p.ts || Date.now() });
    if (dev.track.length > TRACK_LIMIT) dev.track.shift();
  }
  return dev.latest;
}
function withStatus(dev) {
  const d = dev.latest;
  if (!d) return d;
  const age = Date.now() - (d.ts || 0);
  return { ...d, connected: age <= ONLINE_MS };
}
// 按会话过滤可见设备
function snapshotFor(sess) {
  return [...devices.values()]
    .filter(d => sess.role === 'admin' || d.owner === sess.username)
    .map(withStatus);
}
// 按客户端过滤推送一帧
function pushFrame(latest) {
  const line = `event: frame\ndata: ${JSON.stringify(latest)}\n\n`;
  for (const c of sseClients) {
    if (c.role === 'admin' || c.username === latest.owner) {
      try { c.res.write(line); } catch (e) {}
    }
  }
}

/* ---------------- 版本清单 ---------------- */
const LATEST = {
  versionCode: 41, versionName: '2.15.0',
  notes: 'v2.15.0：①看板回退 v2.10 硬朗样式（radial 背景/左色条卡片/大速度字），新增源码包与小体积精简包下载；②背景图高清化——修复背景被强制解码到 1366 宽导致的模糊，touge/nerv 两套背景重做到 2700+ 宽、细节锐化（构图/角色/配色不变）；③开源发行版——默认不内置任何服务器地址，开源版不连用户服务器，需在设置填写自己部署的地址，配开源部署文档；④服务器直连 IP（HTTP），网络安全配置放行服务器 IP 与本地 OBD 网段。其余保留 v2.14 全部能力：声浪 band 内连续变调、关开关/串音修复、采样音质高/低/自动三档、21 套真实采样、应用内更新、游戏 UDP/手柄/赛道、开机自启/音频焦点/横屏、DTC 308 条中文码与清除、账号车队看板按账号隔离、十套皮肤、电影感开屏、GPS 快乐表、自动重连与离线补报。',
};

/* ---------------- 主 handler ---------------- */
const handler = async (req, res) => {
  const url = new URL(req.url, 'http://x');
  const send = (code, body, type = 'application/json; charset=utf-8') => {
    res.writeHead(code, { 'Content-Type': type, 'Access-Control-Allow-Origin': '*' });
    res.end(typeof body === 'string' ? body : JSON.stringify(body));
  };

  // CORS 预检
  if (req.method === 'OPTIONS') {
    res.writeHead(204, {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization',
      'Access-Control-Max-Age': '86400'
    });
    return res.end();
  }

  /* ---- 鉴权接口（无需 token） ---- */
  if (req.method === 'POST' && url.pathname === '/api/auth/register') {
    try {
      const body = JSON.parse(await readBody(req) || '{}');
      const username = String(body.username || '').trim();
      const password = String(body.password || '');
      if (!/^[A-Za-z0-9_]{3,20}$/.test(username))
        return send(400, { ok: false, error: '用户名需为 3-20 位字母、数字或下划线' });
      if (password.length < 6)
        return send(400, { ok: false, error: '密码长度至少 6 位' });
      if (findUser(username))
        return send(409, { ok: false, error: '用户名已被占用' });
      const salt = crypto.randomBytes(16).toString('hex');
      userList.push({
        username, salt, scryptHash: hashPassword(password, salt),
        role: 'user', createdAt: Date.now(), boundDevices: []
      });
      persistUsers();
      const token = createToken();
      sessions[token] = { username, role: 'user', createdAt: Date.now() };
      persistSessions();
      console.log(`[auth] register ${username} @${new Date().toISOString()}`);
      return send(200, { ok: true, token, username, role: 'user' });
    } catch (e) { return send(400, { ok: false, error: '请求格式错误' }); }
  }

  if (req.method === 'POST' && url.pathname === '/api/auth/login') {
    try {
      const body = JSON.parse(await readBody(req) || '{}');
      const username = String(body.username || '').trim();
      const password = String(body.password || '');
      const u = findUser(username);
      if (!u || !verifyPassword(password, u.salt, u.scryptHash))
        return send(401, { ok: false, error: '用户名或密码错误' });
      const token = createToken();
      sessions[token] = { username: u.username, role: u.role, createdAt: Date.now() };
      persistSessions();
      console.log(`[auth] login ${u.username}(${u.role}) @${new Date().toISOString()}`);
      return send(200, { ok: true, token, username: u.username, role: u.role });
    } catch (e) { return send(400, { ok: false, error: '请求格式错误' }); }
  }

  if (req.method === 'POST' && url.pathname === '/api/auth/logout') {
    const auth = req.headers['authorization'] || '';
    const m = String(auth).match(/^Bearer\s+(.+)$/i);
    if (m && sessions[m[1].trim()]) { delete sessions[m[1].trim()]; persistSessions(); }
    return send(200, { ok: true });
  }

  /* ---- SSE 实时流（按客户端会话过滤） ---- */
  if (req.method === 'GET' && url.pathname === '/api/v1/stream') {
    const sess = getSession(req, url);
    if (!sess) return send(401, { ok: false, error: '未登录' });
    res.writeHead(200, {
      'Content-Type': 'text/event-stream; charset=utf-8',
      'Cache-Control': 'no-cache, no-transform',
      'Connection': 'keep-alive',
      'Access-Control-Allow-Origin': '*'
    });
    res.write('retry: 2000\n\n');
    res.write(`event: snapshot\ndata: ${JSON.stringify(snapshotFor(sess))}\n\n`);
    const client = { res, username: sess.username, role: sess.role };
    sseClients.add(client);
    const hb = setInterval(() => { try { res.write(': ping\n\n'); } catch (e) {} }, 25000);
    req.on('close', () => { clearInterval(hb); sseClients.delete(client); });
    return;
  }

  /* ---- 数据上报（必须登录） ---- */
  if (req.method === 'POST' && url.pathname === '/api/v1/report') {
    const sess = getSession(req, url);
    if (!sess) return send(401, { ok: false, error: '未登录，请先在 App 登录账号' });
    try {
      const p = JSON.parse(await readBody(req));
      const deviceId = p.deviceId || 'unknown';
      // 绑定设备到用户
      const u = findUser(sess.username);
      if (u && !u.boundDevices.includes(deviceId)) {
        u.boundDevices.push(deviceId);
        persistUsers();
      }
      if (!devices.has(deviceId)) devices.set(deviceId, { track: [] });
      devices.get(deviceId).owner = sess.username;
      const latest = ingest(p);
      pushFrame(latest);
      console.log(`[report] ${sess.username}/${deviceId} src=${p.source || 'obd'} speed=${p.speed} rpm=${p.rpm} @${new Date().toISOString()}`);
      return send(200, { ok: true });
    } catch (e) { return send(400, { ok: false, error: String(e) }); }
  }

  /* ---- 设备列表（按会话过滤） ---- */
  if (url.pathname === '/api/v1/devices') {
    const sess = getSession(req, url);
    if (!sess) return send(401, { ok: false, error: '未登录' });
    return send(200, snapshotFor(sess));
  }

  /* ---- 单设备轨迹（归属校验） ---- */
  const m = url.pathname.match(/^\/api\/v1\/track\/(.+)$/);
  if (m) {
    const sess = getSession(req, url);
    if (!sess) return send(401, { ok: false, error: '未登录' });
    const id = decodeURIComponent(m[1]);
    const d = devices.get(id);
    if (!d) return send(200, []);
    if (sess.role !== 'admin' && d.owner !== sess.username)
      return send(403, { ok: false, error: '无权查看该设备' });
    return send(200, d.track);
  }

  /* ---- 公开：版本 / 下载 ---- */
  if (url.pathname === '/api/v1/latest') {
    // 走 Cloudflare 橙云 + Origin Rule 时，回源 Host 是源站 IP，需以转发头还原对外地址。
    const first = (v) => (v ? String(v).split(',')[0].trim() : null);
    const proto = first(req.headers['x-forwarded-proto']) || (req.socket.encrypted ? 'https' : 'http');
    const host = first(req.headers['x-forwarded-host']) || req.headers.host;
    const base = `${proto}://${host}`;
    return send(200, {
      ...LATEST,
      apkUrl: base + '/download/rev-latest.apk',
      carUrl: base + '/download/rev-car.apk',
      sourceUrl: base + '/download/REV-Flutter-source.zip',
    });
  }
  if (url.pathname === '/download/rev-latest.apk' || url.pathname === '/download/app-debug.apk') {
    const fp = path.join(__dirname, 'download', 'rev-latest.apk');
    if (!fs.existsSync(fp)) return send(404, { ok: false, error: 'apk missing' });
    res.writeHead(200, {
      'Content-Type': 'application/vnd.android.package-archive',
      'Content-Length': fs.statSync(fp).size,
      'Content-Disposition': 'attachment; filename="REV-latest.apk"',
      'Access-Control-Allow-Origin': '*'
    });
    return fs.createReadStream(fp).pipe(res);
  }
  if (url.pathname === '/download/REV-Flutter-source.zip') {
    const fp = path.join(__dirname, 'download', 'REV-Flutter-source.zip');
    if (!fs.existsSync(fp)) return send(404, { ok: false, error: 'source missing' });
    res.writeHead(200, {
      'Content-Type': 'application/zip',
      'Content-Length': fs.statSync(fp).size,
      'Content-Disposition': 'attachment; filename="REV-Flutter-source.zip"',
      'Access-Control-Allow-Origin': '*'
    });
    return fs.createReadStream(fp).pipe(res);
  }

  /* ---- 分 ABI 小安装包（车机/老设备省流量；通用包在 rev-latest.apk）---- */
  const ABI_PKGS = {
    '/download/rev-arm64.apk': 'rev-arm64.apk',
    '/download/rev-armv7.apk': 'rev-armv7.apk',
    '/download/rev-x86_64.apk': 'rev-x86_64.apk',
  };
  if (ABI_PKGS[url.pathname]) {
    const fp = path.join(__dirname, 'download', ABI_PKGS[url.pathname]);
    if (!fs.existsSync(fp)) return send(404, { ok: false, error: 'apk missing' });
    res.writeHead(200, {
      'Content-Type': 'application/vnd.android.package-archive',
      'Content-Length': fs.statSync(fp).size,
      'Content-Disposition': `attachment; filename="${ABI_PKGS[url.pathname]}"`,
      'Access-Control-Allow-Origin': '*'
    });
    return fs.createReadStream(fp).pipe(res);
  }

  /* ---- 车机包（v2.14：仅 lo 采样，armv7+arm64，统一 extractNativeLibs=false）---- */
  if (url.pathname === '/download/rev-car.apk') {
    const fp = path.join(__dirname, 'download', 'rev-car.apk');
    if (!fs.existsSync(fp)) return send(404, { ok: false, error: 'car apk missing' });
    res.writeHead(200, {
      'Content-Type': 'application/vnd.android.package-archive',
      'Content-Length': fs.statSync(fp).size,
      'Content-Disposition': 'attachment; filename="rev-car.apk"',
      'Access-Control-Allow-Origin': '*'
    });
    return fs.createReadStream(fp).pipe(res);
  }

  /* ---- 精简包（v2.15：仅 lo、arm64 单 ABI、压缩 .so，目标最小）---- */
  if (url.pathname === '/download/rev-lite.apk') {
    const fp = path.join(__dirname, 'download', 'rev-lite.apk');
    if (!fs.existsSync(fp)) return send(404, { ok: false, error: 'lite apk missing' });
    res.writeHead(200, {
      'Content-Type': 'application/vnd.android.package-archive',
      'Content-Length': fs.statSync(fp).size,
      'Content-Disposition': 'attachment; filename="rev-lite.apk"',
      'Access-Control-Allow-Origin': '*'
    });
    return fs.createReadStream(fp).pipe(res);
  }

  /* ---- iOS 未签名 IPA（需用全能签/Sideloadly 等工具自行重签后安装）---- */
  if (url.pathname === '/download/rev-ios.ipa') {
    const fp = path.join(__dirname, 'download', 'rev-ios.ipa');
    if (!fs.existsSync(fp)) return send(404, { ok: false, error: 'ios ipa missing' });
    res.writeHead(200, {
      'Content-Type': 'application/octet-stream',
      'Content-Length': fs.statSync(fp).size,
      'Content-Disposition': 'attachment; filename="rev-ios.ipa"',
      'Access-Control-Allow-Origin': '*'
    });
    return fs.createReadStream(fp).pipe(res);
  }

  /* ---- 看板 ---- */
  if (url.pathname === '/' || url.pathname === '/index.html') {
    return send(200, fs.readFileSync(path.join(__dirname, 'dashboard.html'), 'utf8'),
      'text/html; charset=utf-8');
  }
  send(404, { ok: false, error: 'not found' });
};

/* ---------------- 启动 ---------------- */
const server = http.createServer(handler);
const server80 = http.createServer(handler);

server.listen(PORT, '0.0.0.0', () => {
  console.log(`REV server v2.14.0 listening on 0.0.0.0:${PORT} (auth + filtered SSE)`);
});

// 80：非 root 环境 EACCES 时仅告警跳过，不崩溃；线上 root 正常监听
server80.on('error', (e) => {
  console.warn(`[warn] 80 端口监听未启用（本地非 root 正常，线上 root 可监听）: ${e.code || e.message}`);
});
server80.listen(80, '0.0.0.0', () => {
  console.log('REV server also listening on 0.0.0.0:80');
});

// 443 HTTPS：Let's Encrypt 证书（TLS-ALPN-01 签发，acme.sh 自动续期后重启本服务）。
// 证书缺失或端口被占时仅告警，不影响 80/8080。
const CERT_DIR = path.join(__dirname, 'certs');
const CERT_FILE = path.join(CERT_DIR, 'fullchain.pem');
const KEY_FILE = path.join(CERT_DIR, 'key.pem');
if (fs.existsSync(CERT_FILE) && fs.existsSync(KEY_FILE)) {
  const server443 = https.createServer({
    cert: fs.readFileSync(CERT_FILE),
    key: fs.readFileSync(KEY_FILE),
  }, handler);
  server443.on('error', (e) => {
    console.warn(`[warn] 443 HTTPS 未启用: ${e.code || e.message}`);
  });
  server443.listen(443, '0.0.0.0', () => {
    console.log('REV server HTTPS listening on 0.0.0.0:443');
  });
} else {
  console.warn('[warn] 未找到 TLS 证书（certs/fullchain.pem、certs/key.pem），443 HTTPS 未启用');
}

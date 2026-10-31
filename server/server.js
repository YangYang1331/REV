/*
 * REV 云端服务 v2.17.5（历史趋势 + 车队共享 + viewer 角色）
 * 零依赖 Node.js（v18+，仅内置 http/fs/path/crypto/https）
 *
 * v2.16.0 新增：
 *  - 分钟级聚合环形缓冲（每设备最多 7 天 10080 桶），data/history.json 落盘
 *  - GET /api/v1/history?deviceId=&hours= 历史趋势 API（最多 500 点）
 *  - POST/DELETE /api/v1/share + GET /api/v1/shares 车队共享（只读 view）
 *  - viewer 角色：只读，不能上报/分享；设备列表返回 perm: owner|share|admin
 *  - SSE pushFrame 按 owner / shares / admin 过滤
 *
 * 运行： PORT=8099 node server.js
 */
const http = require('http');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const https = require('https');
const { createClientIp } = require('./proxy_ip');

const PORT = Number(process.env.PORT || 8080);
const TRACK_LIMIT = Math.max(100, Number(process.env.TRACK_LIMIT || 2000));
const ONLINE_MS = 10000;
const SESSION_TTL_MS = Math.max(1, Number(process.env.SESSION_TTL_DAYS || 30)) * 86400000;
const DEVICE_IDLE_MS = Math.max(1, Number(process.env.DEVICE_IDLE_HOURS || 48)) * 3600000;
const MAX_DEVICES = Math.max(100, Number(process.env.MAX_DEVICES || 5000));
const MAX_SSE_CLIENTS = Math.max(10, Number(process.env.MAX_SSE_CLIENTS || 500));
const MAX_BODY = 1e6;
const RATE_WINDOW_MS = 10 * 60 * 1000;
const LOGIN_IP_LIMIT = 30;
const LOGIN_USER_LIMIT = 10;
const REGISTER_IP_LIMIT = 10;
const HISTORY_MAX_BUCKETS = 10080; // 7 days * 24h * 60min
// 历史默认口令只从环境变量读取，避免把真实口令写进源码/仓库。
const LEGACY_ADMIN_PASS = process.env.LEGACY_ADMIN_PASSWORD || '';

const DATA_DIR = path.join(__dirname, 'data');
const USERS_FILE = path.join(DATA_DIR, 'users.json');
const SESSIONS_FILE = path.join(DATA_DIR, 'sessions.json');
const DEVICES_FILE = path.join(DATA_DIR, 'devices.json');
const HISTORY_FILE = path.join(DATA_DIR, 'history.json');

const devices = new Map();         // deviceId -> { owner, latest, track:[], spark:[], shares:{username:'view'} }
const streamTickets = new Map();   // ticket -> { username, role, exp }
const sseClients = new Set();      // { res, username, role }
const history = new Map();         // deviceId -> [{t, ct_s, ct_n, ot_s, ot_n, volt_s, volt_n, spd_s, spd_n}]
let historyDirty = false;

/* ---------------- 持久化（容错，原子写） ---------------- */
function ensureDataDir() {
  try {
    fs.mkdirSync(DATA_DIR, { recursive: true, mode: 0o700 });
    fs.chmodSync(DATA_DIR, 0o700);
  } catch (e) {}
}
// 数据目录/文件只给服务账号读写：里面是账号口令哈希与 30 天会话 token。
function secureDataFiles() {
  ensureDataDir();
  for (const fp of [USERS_FILE, SESSIONS_FILE, DEVICES_FILE, HISTORY_FILE]) {
    try { if (fs.existsSync(fp)) fs.chmodSync(fp, 0o600); } catch (e) {}
  }
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
    fs.writeFileSync(tmp, JSON.stringify(obj, null, 2), { mode: 0o600 });
    fs.renameSync(tmp, fp);
    try { fs.chmodSync(fp, 0o600); } catch (e) {}
  } catch (e) { console.error('[persist]', fp, e.message); }
}

/* ---------------- 账号体系 ---------------- */
let userList = loadJson(USERS_FILE, { users: [] }).users || [];
let sessions = loadJson(SESSIONS_FILE, {});
// Normalize old sessions without role
for (const s of Object.values(sessions)) { if (s && !s.role) s.role = 'user'; }
// 启动即收紧权限：旧版本可能把 data/*.json 留成 644。
secureDataFiles();

function persistUsers() { writeJsonAtomic(USERS_FILE, { users: userList }); }
function persistSessions() { writeJsonAtomic(SESSIONS_FILE, sessions); }

let devicesDirty = false;
function persistDevices() {
  try {
    const list = [];
    for (const [id, d] of devices) {
      list.push({
        deviceId: id,
        owner: d.owner || null,
        latest: d.latest || null,
        track: Array.isArray(d.track) ? d.track.slice(-120) : [],
        spark: Array.isArray(d.spark) ? d.spark.slice(-72) : [],
        shares: d.shares || {},
      });
    }
    writeJsonAtomic(DEVICES_FILE, { devices: list });
  } catch (e) { console.error('[persist] devices', e.message); }
}
(function restoreDevices() {
  const saved = loadJson(DEVICES_FILE, { devices: [] }).devices || [];
  for (const d of saved) {
    if (!d || !d.deviceId) continue;
    devices.set(d.deviceId, {
      owner: d.owner || null,
      latest: d.latest || null,
      track: Array.isArray(d.track) ? d.track.slice(-120) : [],
      spark: Array.isArray(d.spark) ? d.spark.slice(-72) : [],
      shares: (d.shares && typeof d.shares === 'object') ? d.shares : {},
    });
  }
  if (devices.size) console.log(`[restore] 已恢复 ${devices.size} 台设备快照`);
})();

/* ---------------- 历史数据持久化 ---------------- */
function persistHistory() {
  try {
    const obj = {};
    for (const [id, buckets] of history) obj[id] = buckets;
    writeJsonAtomic(HISTORY_FILE, obj);
    historyDirty = false;
  } catch (e) { console.error('[persist] history', e.message); }
}
(function restoreHistory() {
  const saved = loadJson(HISTORY_FILE, {});
  if (saved && typeof saved === 'object' && !Array.isArray(saved)) {
    for (const [id, buckets] of Object.entries(saved)) {
      if (Array.isArray(buckets) && buckets.length) history.set(id, buckets);
    }
  }
  if (history.size) console.log(`[restore] 已恢复 ${history.size} 台设备历史数据`);
})();

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

(function bootstrapAdmin() {
  if (userList.length === 0) {
    const pwd = process.env.ADMIN_PASSWORD || crypto.randomBytes(12).toString('base64url');
    const salt = crypto.randomBytes(16).toString('hex');
    userList.push({
      username: 'admin', salt, scryptHash: hashPassword(pwd, salt),
      role: 'admin', createdAt: Date.now(), boundDevices: []
    });
    persistUsers();
    if (process.env.ADMIN_PASSWORD) {
      console.log('[auth] 已初始化管理员账号 admin（口令来自 ADMIN_PASSWORD）');
    } else {
      console.log(`[auth] 已初始化管理员账号 admin，随机口令：${pwd}（仅显示一次，登录后请立即修改）`);
    }
  } else if (LEGACY_ADMIN_PASS && findUser('admin') && verifyPassword(LEGACY_ADMIN_PASS, findUser('admin').salt, findUser('admin').scryptHash)) {
    if (process.env.ADMIN_ALLOW_DEFAULT === '1') {
      console.warn('[auth][警告] 管理员仍在使用历史默认口令，ADMIN_ALLOW_DEFAULT=1 已豁免自动重置。');
    } else {
      const nu = findUser('admin');
      const pwd = process.env.ADMIN_PASSWORD || crypto.randomBytes(12).toString('base64url');
      nu.salt = crypto.randomBytes(16).toString('hex');
      nu.scryptHash = hashPassword(pwd, nu.salt);
      persistUsers();
      console.warn('[auth][安全] 检测到历史默认口令，已重置为随机强口令：' + pwd + '（仅显示一次）');
    }
  }
})();

function pruneSessions() {
  const now = Date.now();
  let removed = 0;
  for (const [t, s] of Object.entries(sessions)) {
    if (!s || typeof s !== 'object' || now - (s.createdAt || 0) > SESSION_TTL_MS) {
      delete sessions[t]; removed++;
    }
  }
  if (removed) {
    persistSessions();
    console.log(`[auth] 清理过期会话 ${removed} 条，剩余 ${Object.keys(sessions).length} 条`);
  }
  return removed;
}
function getToken(req) {
  const auth = req.headers['authorization'] || '';
  const m = String(auth).match(/^Bearer\s+(.+)$/i);
  return m ? m[1].trim() : null;
}
function getSession(req) {
  const token = getToken(req);
  if (!token) return null;
  const s = sessions[token];
  if (!s) return null;
  if (!s.role) s.role = 'user';
  return s;
}

/* ---------------- 限流 ---------------- */
const rateBuckets = new Map();
// 只有本机/显式配置的反向代理才信任转发头；公网直连忽略 XFF/CF，防伪造绕过限流。
const clientIp = createClientIp({
  trustedProxies: process.env.TRUSTED_PROXIES || '127.0.0.1,::1',
  trustCf: process.env.TRUST_CF_CONNECTING_IP === '1',
});
function hitLimit(key, limit, windowMs = RATE_WINDOW_MS) {
  const now = Date.now();
  let b = rateBuckets.get(key);
  if (!b || now - b.start > windowMs) { b = { start: now, n: 0 }; rateBuckets.set(key, b); }
  b.n += 1;
  if (rateBuckets.size > 20000) {
    for (const [k, v] of rateBuckets) if (now - v.start > windowMs) rateBuckets.delete(k);
  }
  return b.n > limit;
}
setInterval(() => {
  const now = Date.now();
  for (const [k, v] of rateBuckets) if (now - v.start > RATE_WINDOW_MS) rateBuckets.delete(k);
}, 5 * 60 * 1000).unref();

/* ---------------- 数据 ingest ---------------- */
function readBody(req, limit = MAX_BODY) {
  return new Promise((resolve, reject) => {
    let buf = '';
    let done = false;
    req.on('data', c => {
      if (done) return;
      buf += c;
      if (buf.length > limit) {
        done = true;
        const err = new Error('请求体过大');
        err.status = 413;
        reject(err);
        req.resume();
      }
    });
    req.on('end', () => { if (!done) { done = true; resolve(buf); } });
    req.on('error', (e) => { if (!done) { done = true; reject(e); } });
  });
}
function round(v, n = 1) {
  if (v == null || v === '') return null;
  const x = Number(v);
  if (!Number.isFinite(x)) return null;
  const k = Math.pow(10, n);
  return Math.round(x * k) / k;
}
function sanitizeDeviceId(v) {
  let s = String(v == null ? '' : v).replace(/[\u0000-\u001f\u007f<>]/g, '').trim();
  if (!s) s = 'unknown';
  return s.length > 64 ? s.slice(0, 64) : s;
}

/* ---------------- 历史趋势：分钟级聚合 ---------------- */
function updateHistory(deviceId, ts, p) {
  const minuteStart = Math.floor(ts / 60000) * 60000;
  let buckets = history.get(deviceId);
  if (!buckets) { buckets = []; history.set(deviceId, buckets); }

  const ct = round(p.coolant);
  const ot = round(p.oilTemp);
  const volt = round(p.voltage, 2);
  const spd = round(p.speed);

  const last = buckets.length > 0 ? buckets[buckets.length - 1] : null;
  if (last && last.t === minuteStart) {
    if (ct != null) { last.ct_s += ct; last.ct_n++; }
    if (ot != null) { last.ot_s += ot; last.ot_n++; }
    if (volt != null) { last.volt_s += volt; last.volt_n++; }
    if (spd != null) { last.spd_s += spd; last.spd_n++; }
  } else {
    buckets.push({
      t: minuteStart,
      ct_s: ct != null ? ct : 0, ct_n: ct != null ? 1 : 0,
      ot_s: ot != null ? ot : 0, ot_n: ot != null ? 1 : 0,
      volt_s: volt != null ? volt : 0, volt_n: volt != null ? 1 : 0,
      spd_s: spd != null ? spd : 0, spd_n: spd != null ? 1 : 0,
    });
    if (buckets.length > HISTORY_MAX_BUCKETS) buckets.shift();
  }
  historyDirty = true;
}

function ingest(p) {
  const id = sanitizeDeviceId(p.deviceId);
  if (!devices.has(id)) devices.set(id, { track: [], spark: [], shares: {} });
  const dev = devices.get(id);
  const ts = Number(p.ts) || Date.now();
  // 单调保护
  if (dev.latest && Number(dev.latest.ts) > ts) return null;
  const lat = round(p.lat, 5), lng = round(p.lng, 5);
  dev.latest = {
    deviceId: id, ts: ts,
    source: String(p.source || 'obd').slice(0, 16),
    connected: p.connected !== false,
    owner: dev.owner || null,
    gear: round(p.gear, 0),
    speed: round(p.speed), rpm: round(p.rpm, 0),
    coolant: round(p.coolant), oilTemp: round(p.oilTemp),
    intakeTemp: round(p.intakeTemp), ambient: round(p.ambient),
    voltage: round(p.voltage, 2), boost: round(p.boost, 2),
    load: round(p.load), throttle: round(p.throttle),
    fuelLevel: round(p.fuelLevel),
    maf: round(p.maf, 2), fuelLph: round(p.fuelLph, 2), fuelRate: round(p.fuelRate, 2),
    tripKm: round(p.tripKm, 2), tripFuel: round(p.tripFuel, 3), tripSec: round(p.tripSec, 0),
    lat: (lat != null && lat >= -90 && lat <= 90) ? lat : null,
    lng: (lng != null && lng >= -180 && lng <= 180) ? lng : null,
    heading: round(p.heading)
  };
  if (dev.latest.lat != null && dev.latest.lng != null) {
    dev.track.push({ lat: dev.latest.lat, lng: dev.latest.lng, ts: dev.latest.ts });
    if (dev.track.length > TRACK_LIMIT) dev.track.shift();
  }
  if (!Array.isArray(dev.spark)) dev.spark = [];
  dev.spark.push({ t: dev.latest.ts, s: dev.latest.speed, r: dev.latest.rpm, th: dev.latest.throttle });
  if (dev.spark.length > 72) dev.spark.shift();
  // 更新历史聚合（在单调保护之后，只有新帧才进 history）
  updateHistory(id, ts, p);
  return dev.latest;
}
function withStatus(dev) {
  const d = dev.latest;
  if (!d) return d;
  const age = Date.now() - (d.ts || 0);
  return { ...d, connected: age <= ONLINE_MS, spark: Array.isArray(dev.spark) ? dev.spark : [] };
}

/* ---------------- 权限辅助 ---------------- */
function canAccessDevice(sess, dev) {
  if (!sess) return false;
  if (sess.role === 'admin') return true;
  if (dev.owner === sess.username) return true;
  if (dev.shares && dev.shares[sess.username]) return true;
  return false;
}
function getDevicePerm(sess, dev) {
  if (!sess) return null;
  if (sess.role === 'admin') return 'admin';
  if (dev.owner === sess.username) return 'owner';
  if (dev.shares && dev.shares[sess.username]) return 'share';
  return null;
}

function snapshotFor(sess) {
  return [...devices.entries()]
    .filter(([id, d]) => canAccessDevice(sess, d))
    .map(([id, d]) => {
      const s = withStatus(d);
      if (!s) return null;
      s.perm = getDevicePerm(sess, d);
      return s;
    })
    .filter(Boolean);
}

function pushFrame(latest) {
  const dev = devices.get(latest.deviceId);
  for (const c of sseClients) {
    const canSee = c.role === 'admin' || c.username === latest.owner ||
                   (dev && dev.shares && dev.shares[c.username]);
    if (canSee) {
      const perm = c.role === 'admin' ? 'admin' :
                   (c.username === latest.owner ? 'owner' : 'share');
      const frameData = { ...latest, perm };
      const line = `event: frame\ndata: ${JSON.stringify(frameData)}\n\n`;
      if (c.res.writableLength > 512 * 1024) continue;
      try { c.res.write(line); } catch (e) { sseClients.delete(c); }
    }
  }
}

function sweepDevices() {
  const now = Date.now();
  let removed = 0;
  for (const [id, d] of devices) {
    const ts = d.latest ? d.latest.ts : 0;
    if (now - ts > DEVICE_IDLE_MS) { devices.delete(id); history.delete(id); removed++; }
  }
  if (devices.size > MAX_DEVICES) {
    const sorted = [...devices.entries()].sort((a, b) => ((a[1].latest && a[1].latest.ts) || 0) - ((b[1].latest && b[1].latest.ts) || 0));
    for (const [id] of sorted.slice(0, devices.size - MAX_DEVICES)) { devices.delete(id); history.delete(id); removed++; }
  }
  if (removed) {
    console.log(`[sweep] 清理设备 ${removed} 台，剩余 ${devices.size}`);
    devicesDirty = true;
    historyDirty = true;
  }
}

/* ---------------- 版本清单 ---------------- */
const LATEST = {
  versionCode: 61, versionName: '2.17.7',
  apkSha256: '5e9338d16a03ed2f4b57592f30467d7fc11d533c2b1507cfc9864e9da870479a',
  notes: 'v2.17.7：采样声浪重构——每个包改为单段核心录音 + 连续变调（怠速→红线 0.68~1.85 倍），修复旧版四段重复录音叠播导致的发闷/合唱感与「不随转速变」；240 个循环全部重新母带（接缝体检，超阈值才做 80ms 等功率淡化；ebur128 统一 -16 LUFS/真峰值 -1.5 dB；逐包低通收风噪），包间响度一致；下线「视频采样·驾驶舱巡航」「视频采样·高速巡航」两套不合格采样；调教面板只对「合成引擎·可调」显示，试听改为 2 秒转速扫频。v2.17.6：合成基频改为物理点火频率 + 9 套引擎档案 + 调音面板。v2.17.5：开屏电影感与原创氛围音。v2.17.4：默认 HTTPS + 更新包 SHA-256 + 关闭备份。v2.17.3：开屏标题高光只扫字形。v2.17.2：开屏 3D 镜头/冲击波/HUD。v2.17.1：服务端同步与检查更新修复。v2.17.0：诊断解读/油耗账本/多车车库/行程工具。',
};

/* ---------------- 静态下载表 ---------------- */
const DOWNLOADS = new Map([
  ['/download/rev-latest.apk', { file: 'rev-latest.apk', type: 'application/vnd.android.package-archive', name: 'REV-latest.apk' }],
  ['/download/app-debug.apk', { file: 'rev-latest.apk', type: 'application/vnd.android.package-archive', name: 'REV-latest.apk' }],
  ['/download/rev-car.apk', { file: 'rev-car.apk', type: 'application/vnd.android.package-archive', name: 'rev-car.apk' }],
  ['/download/rev-lite.apk', { file: 'rev-lite.apk', type: 'application/vnd.android.package-archive', name: 'rev-lite.apk' }],
  ['/download/rev-arm64.apk', { file: 'rev-arm64.apk', type: 'application/vnd.android.package-archive', name: 'REV-arm64.apk' }],
  ['/download/rev-armv7.apk', { file: 'rev-armv7.apk', type: 'application/vnd.android.package-archive', name: 'REV-armv7.apk' }],
  ['/download/rev-x86_64.apk', { file: 'rev-x86_64.apk', type: 'application/vnd.android.package-archive', name: 'REV-x86_64.apk' }],
  ['/download/rev-ios.ipa', { file: 'rev-ios.ipa', type: 'application/octet-stream', name: 'rev-ios.ipa' }],
  ['/download/REV-Flutter-source.zip', { file: 'REV-Flutter-source.zip', type: 'application/zip', name: 'REV-Flutter-source.zip' }],
]);

/* ---------------- 主 handler ---------------- */
const SEC_HEADERS = {
  'X-Content-Type-Options': 'nosniff',
  'Referrer-Policy': 'no-referrer',
  'X-Frame-Options': 'SAMEORIGIN',
};
const CSP_DASHBOARD = [
  "default-src 'self'",
  "script-src 'self' 'unsafe-inline'",
  "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com",
  "font-src 'self' https://fonts.gstatic.com data:",
  "img-src 'self' data:",
  "connect-src 'self'",
  "frame-ancestors 'self'",
  "base-uri 'none'",
  "form-action 'self'",
].join('; ');

function serveDownload(req, res, spec, send) {
  const fp = path.join(__dirname, 'download', spec.file);
  let st;
  try { st = fs.statSync(fp); } catch (e) { return send(404, { ok: false, error: 'file missing' }); }
  const etag = `"${st.size.toString(16)}-${Math.floor(st.mtimeMs).toString(16)}"`;
  const headers = {
    ...SEC_HEADERS,
    'Content-Type': spec.type,
    'Accept-Ranges': 'bytes',
    'Content-Disposition': `attachment; filename="${spec.name}"`,
    // 文件名固定（rev-latest.apk），不能给长缓存：否则发新版本后浏览器
    // 仍会把上一次的旧包直接还给安装器（用户看到"2.16.1 -> 2.16.1"）。
    // 改用 ETag + Last-Modified 让浏览器回源校验，未变时仍拿 304。
    'Cache-Control': 'no-cache',
    'ETag': etag,
    'Last-Modified': new Date(st.mtimeMs).toUTCString(),
    'Access-Control-Allow-Origin': '*',
  };
  const inm = req.headers['if-none-match'];
  if (inm && inm.split(',').map((v) => v.trim()).includes(etag)) {
    res.writeHead(304, { ...SEC_HEADERS, 'ETag': etag, 'Cache-Control': 'no-cache' });
    return res.end();
  }
  const range = req.headers['range'];
  const m = range && /^bytes=(\d*)-(\d*)$/.exec(String(range).trim());
  if (m && (m[1] || m[2])) {
    let start = m[1] ? parseInt(m[1], 10) : null;
    let end = m[2] ? parseInt(m[2], 10) : null;
    if (start === null) { start = Math.max(0, st.size - (end || 0)); end = st.size - 1; }
    if (end === null || end >= st.size) end = st.size - 1;
    if (!Number.isFinite(start) || !Number.isFinite(end) || start > end || start >= st.size) {
      res.writeHead(416, { ...SEC_HEADERS, 'Content-Range': `bytes */${st.size}` });
      return res.end();
    }
    res.writeHead(206, { ...headers, 'Content-Range': `bytes ${start}-${end}/${st.size}`, 'Content-Length': end - start + 1 });
    if (req.method === 'HEAD') return res.end();
    return fs.createReadStream(fp, { start, end }).pipe(res);
  }
  res.writeHead(200, { ...headers, 'Content-Length': st.size });
  if (req.method === 'HEAD') return res.end();
  fs.createReadStream(fp).pipe(res);
}

const handler = async (req, res) => {
  const url = new URL(req.url, 'http://x');
  if (/^\/c\//.test(url.pathname)) {
    url.pathname = url.pathname.slice(2);
  }
  const send = (code, body, type = 'application/json; charset=utf-8', extra = {}) => {
    res.writeHead(code, {
      ...SEC_HEADERS,
      'Content-Type': type,
      'Cache-Control': 'no-store',
      'Access-Control-Allow-Origin': '*',
      ...extra,
    });
    res.end(typeof body === 'string' ? body : JSON.stringify(body));
  };

  // HTTPS 强制
  {
    const proto = ((req.headers['x-forwarded-proto'] || '').split(',')[0].trim()) || (req.socket.encrypted ? 'https' : 'http');
    const host = String(req.headers['x-forwarded-host'] || req.headers.host || '').split(',')[0].trim();
    const hostname = host.replace(/:\d+$/, '').toLowerCase();
    const isIp = /^\d{1,3}(\.\d{1,3}){3}$/.test(hostname) || hostname.includes(':');
    const isLocal = hostname === 'localhost' || hostname.endsWith('.local');
    const isPrivate = /^(10\.|127\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.)/.test(hostname);
    if (proto === 'http' && host && (req.method === 'GET' || req.method === 'HEAD') && !isIp && !isLocal && !isPrivate) {
      res.writeHead(301, { ...SEC_HEADERS, Location: `https://${host}${req.url}`, 'Cache-Control': 'no-store' });
      return res.end();
    }
  }

  // CORS 预检（含 DELETE）
  if (req.method === 'OPTIONS') {
    res.writeHead(204, {
      ...SEC_HEADERS,
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET,POST,DELETE,OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type, Authorization',
      'Access-Control-Max-Age': '86400'
    });
    return res.end();
  }

  /* ---- 鉴权接口（无需 token） ---- */
  if (req.method === 'POST' && url.pathname === '/api/auth/register') {
    const ip = clientIp(req);
    if (hitLimit('reg-ip:' + ip, REGISTER_IP_LIMIT)) {
      return send(429, { ok: false, error: '注册过于频繁，请稍后再试' }, undefined, { 'Retry-After': '600' });
    }
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
    } catch (e) {
      return send(e.status || 400, { ok: false, error: e.status === 413 ? '请求体过大' : '请求格式错误' });
    }
  }

  if (req.method === 'POST' && url.pathname === '/api/auth/login') {
    const ip = clientIp(req);
    try {
      const body = JSON.parse(await readBody(req) || '{}');
      const username = String(body.username || '').trim();
      const password = String(body.password || '');
      const uname = username.toLowerCase();
      if (hitLimit('login-ip:' + ip, LOGIN_IP_LIMIT) || hitLimit('login-user:' + ip + ':' + uname, LOGIN_USER_LIMIT)) {
        return send(429, { ok: false, error: '尝试过于频繁，请 10 分钟后再试' }, undefined, { 'Retry-After': '600' });
      }
      const u = findUser(username);
      if (!u || !verifyPassword(password, u.salt, u.scryptHash))
        return send(401, { ok: false, error: '用户名或密码错误' });
      rateBuckets.delete('login-user:' + ip + ':' + uname);
      const token = createToken();
      sessions[token] = { username: u.username, role: u.role || 'user', createdAt: Date.now() };
      persistSessions();
      console.log(`[auth] login ${u.username}(${u.role || 'user'}) @${new Date().toISOString()}`);
      return send(200, { ok: true, token, username: u.username, role: u.role || 'user' });
    } catch (e) {
      return send(e.status || 400, { ok: false, error: e.status === 413 ? '请求体过大' : '请求格式错误' });
    }
  }

  if (req.method === 'POST' && url.pathname === '/api/auth/logout') {
    const token = getToken(req);
    if (token && sessions[token]) { delete sessions[token]; persistSessions(); }
    return send(200, { ok: true });
  }

  // 修改密码（所有角色包括 viewer 均可）
  if (req.method === 'POST' && url.pathname === '/api/auth/password') {
    const token = getToken(req);
    const sess = token ? sessions[token] : null;
    if (!sess) return send(401, { ok: false, error: '未登录' });
    if (hitLimit('pwd:' + clientIp(req), 10)) return send(429, { ok: false, error: '操作过于频繁，请稍后再试' });
    try {
      const body = JSON.parse(await readBody(req) || '{}');
      const oldP = String(body.oldPassword || '');
      const newP = String(body.newPassword || '');
      const u = findUser(sess.username);
      if (!u) return send(404, { ok: false, error: '账号不存在' });
      if (!verifyPassword(oldP, u.salt, u.scryptHash))
        return send(403, { ok: false, error: '原密码不正确' });
      if (newP.length < 8) return send(400, { ok: false, error: '新密码至少 8 位' });
      if (newP === oldP) return send(400, { ok: false, error: '新密码不能与原密码相同' });
      u.salt = crypto.randomBytes(16).toString('hex');
      u.scryptHash = hashPassword(newP, u.salt);
      persistUsers();
      for (const [t, s] of Object.entries(sessions)) {
        if (s.username === u.username && t !== token) delete sessions[t];
      }
      persistSessions();
      console.log(`[auth] password changed for ${u.username} @${new Date().toISOString()}`);
      return send(200, { ok: true });
    } catch (e) {
      return send(e.status || 400, { ok: false, error: e.status === 413 ? '请求体过大' : '请求格式错误' });
    }
  }

  // 角色管理（仅 admin）：把账号设为只读 viewer / 恢复 user / 指定 admin。
  // 老用户 role 缺省按 user；降级唯一管理员会被拒绝。
  if (req.method === 'POST' && url.pathname === '/api/auth/role') {
    const sess = getSession(req);
    if (!sess) return send(401, { ok: false, error: '未登录' });
    if (sess.role !== 'admin') return send(403, { ok: false, error: '仅管理员可修改角色' });
    try {
      const body = JSON.parse(await readBody(req) || '{}');
      const uname = String(body.username || '').trim().toLowerCase();
      const role = String(body.role || '').trim().toLowerCase();
      if (!['admin', 'user', 'viewer'].includes(role))
        return send(400, { ok: false, error: 'role 只能是 admin / user / viewer' });
      const u = findUser(uname);
      if (!u) return send(404, { ok: false, error: '账号不存在' });
      const admins = userList.filter(x => (x.role || 'user') === 'admin');
      if ((u.role || 'user') === 'admin' && role !== 'admin' && admins.length <= 1)
        return send(400, { ok: false, error: '不能降级唯一的管理员' });
      u.role = role;
      persistUsers();
      for (const s of Object.values(sessions)) if (s.username === u.username) s.role = role;
      persistSessions();
      console.log(`[auth] role ${u.username} -> ${role} by ${sess.username}`);
      return send(200, { ok: true, username: u.username, role });
    } catch (e) {
      return send(e.status || 400, { ok: false, error: e.status === 413 ? '请求体过大' : '请求格式错误' });
    }
  }

  /* ---- SSE 一次性票据 ---- */
  if (req.method === 'POST' && url.pathname === '/api/v1/stream-ticket') {
    const sess = getSession(req);
    if (!sess) return send(401, { ok: false, error: '未登录' });
    if (hitLimit('ticket:' + clientIp(req), 60)) return send(429, { ok: false, error: '请求过于频繁' });
    const now = Date.now();
    for (const [t, v] of streamTickets) if (v.exp <= now) streamTickets.delete(t);
    if (streamTickets.size > 5000) streamTickets.clear();
    const ticket = crypto.randomBytes(24).toString('hex');
    streamTickets.set(ticket, { username: sess.username, role: sess.role, exp: now + 60000 });
    return send(200, { ok: true, ticket, expiresIn: 60 });
  }

  /* ---- SSE 实时流 ---- */
  if (req.method === 'GET' && url.pathname === '/api/v1/stream') {
    const ticket = url.searchParams.get('ticket') || '';
    const t = streamTickets.get(ticket);
    streamTickets.delete(ticket);
    const sess = (t && t.exp > Date.now()) ? { username: t.username, role: t.role } : null;
    if (!sess) return send(401, { ok: false, error: '票据无效或已过期' });
    if (sseClients.size >= MAX_SSE_CLIENTS) return send(503, { ok: false, error: '连接数已满，请稍后再试' });
    res.writeHead(200, {
      ...SEC_HEADERS,
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

  /* ---- 数据上报（必须登录；viewer 禁止） ---- */
  if (req.method === 'POST' && url.pathname === '/api/v1/report') {
    const sess = getSession(req);
    if (!sess) return send(401, { ok: false, error: '未登录，请先在 App 登录账号' });
    if (sess.role === 'viewer') return send(403, { ok: false, error: 'viewer 账号无权上报数据' });
    try {
      const p = JSON.parse(await readBody(req));
      const deviceId = sanitizeDeviceId(p.deviceId);
      if (sess.role !== 'admin' && devices.has(deviceId) && devices.get(deviceId).owner &&
          devices.get(deviceId).owner !== sess.username) {
        return send(403, { ok: false, error: '该设备已绑定其他账号' });
      }
      const u = findUser(sess.username);
      if (u && !u.boundDevices.includes(deviceId)) {
        u.boundDevices.push(deviceId);
        if (u.boundDevices.length > 50) u.boundDevices = u.boundDevices.slice(-50);
        persistUsers();
      }
      if (!devices.has(deviceId)) devices.set(deviceId, { track: [], spark: [], shares: {} });
      devices.get(deviceId).owner = sess.username;
      const latest = ingest(p);
      devicesDirty = true;
      if (latest) {
        pushFrame(latest);
        console.log(`[report] ${sess.username}/${deviceId} src=${latest.source} speed=${latest.speed} rpm=${latest.rpm} @${new Date().toISOString()}`);
      }
      return send(200, { ok: true });
    } catch (e) {
      return send(e.status || 400, { ok: false, error: e.status === 413 ? '请求体过大' : String(e) });
    }
  }

  /* ---- 离线补传（批量；viewer 禁止） ---- */
  if (req.method === 'POST' && url.pathname === '/api/v1/report/batch') {
    const sess = getSession(req);
    if (!sess) return send(401, { ok: false, error: '未登录，请先在 App 登录账号' });
    if (sess.role === 'viewer') return send(403, { ok: false, error: 'viewer 账号无权上报数据' });
    try {
      const body = JSON.parse(await readBody(req));
      const raw = Array.isArray(body && body.frames) ? body.frames : [];
      if (!raw.length) return send(400, { ok: false, error: 'frames 为空' });
      if (raw.length > 500) return send(413, { ok: false, error: '单次最多 500 帧' });
      const frames = raw
        .filter(f => f && typeof f === 'object')
        .map(f => ({ ...f, deviceId: sanitizeDeviceId(f.deviceId), ts: Number(f.ts) || 0 }))
        .sort((a, b) => a.ts - b.ts);
      if (!frames.length) return send(400, { ok: false, error: 'frames 为空' });
      const ids = [...new Set(frames.map(f => f.deviceId))];
      const u = findUser(sess.username);
      for (const deviceId of ids) {
        if (sess.role !== 'admin' && devices.has(deviceId) && devices.get(deviceId).owner &&
          devices.get(deviceId).owner !== sess.username) {
          return send(403, { ok: false, error: '该设备已绑定其他账号' });
        }
      }
      for (const deviceId of ids) {
        if (!devices.has(deviceId)) devices.set(deviceId, { track: [], spark: [], shares: {} });
        devices.get(deviceId).owner = sess.username;
        if (u && !u.boundDevices.includes(deviceId)) {
          u.boundDevices.push(deviceId);
          if (u.boundDevices.length > 50) u.boundDevices = u.boundDevices.slice(-50);
        }
      }
      if (u) persistUsers();
      let accepted = 0;
      let latest = null;
      for (const f of frames) {
        const r = ingest(f);
        if (r) { accepted++; latest = r; }
      }
      devicesDirty = true;
      if (latest) pushFrame(latest);
      console.log(`[batch] ${sess.username} frames=${frames.length} accepted=${accepted} ids=${ids.join(',')}`);
      return send(200, { ok: true, accepted });
    } catch (e) {
      return send(e.status || 400, { ok: false, error: e.status === 413 ? '请求体过大' : String(e) });
    }
  }

  /* ---- 健康检查 ---- */
  if (req.method === 'GET' && url.pathname === '/api/v1/health') {
    return send(200, {
      ok: true,
      version: LATEST.versionName,
      versionCode: LATEST.versionCode,
      uptimeSec: Math.round(process.uptime()),
      devices: devices.size,
      users: userList.length,
      sseClients: sseClients.size,
      memMB: Math.round(process.memoryUsage().rss / 1048576),
      time: new Date().toISOString(),
    });
  }

  /* ---- 设备列表（按会话过滤，含共享；viewer 可见） ---- */
  if (url.pathname === '/api/v1/devices') {
    const sess = getSession(req);
    if (!sess) return send(401, { ok: false, error: '未登录' });
    return send(200, snapshotFor(sess));
  }

  /* ---- 单设备轨迹（owner / shares / admin 放行） ---- */
  const mTrack = url.pathname.match(/^\/api\/v1\/track\/(.+)$/);
  if (mTrack) {
    const sess = getSession(req);
    if (!sess) return send(401, { ok: false, error: '未登录' });
    const id = decodeURIComponent(mTrack[1]);
    const d = devices.get(id);
    if (!d) return send(200, []);
    if (!canAccessDevice(sess, d))
      return send(403, { ok: false, error: '无权查看该设备' });
    return send(200, d.track);
  }

  /* ---- 共享管理：POST 添加 / DELETE 撤销 / GET 列表 ---- */
  if (req.method === 'POST' && url.pathname === '/api/v1/share') {
    const sess = getSession(req);
    if (!sess) return send(401, { ok: false, error: '未登录' });
    if (sess.role === 'viewer') return send(403, { ok: false, error: 'viewer 无权操作' });
    try {
      const body = JSON.parse(await readBody(req) || '{}');
      const deviceId = sanitizeDeviceId(body.deviceId);
      const username = String(body.username || '').trim().toLowerCase();
      if (!deviceId || !username) return send(400, { ok: false, error: '缺少 deviceId 或 username' });
      const dev = devices.get(deviceId);
      if (!dev) return send(404, { ok: false, error: '设备不存在' });
      if (sess.role !== 'admin' && dev.owner !== sess.username)
        return send(403, { ok: false, error: '无权操作该设备' });
      if (!findUser(username)) return send(404, { ok: false, error: '目标用户不存在' });
      if (username === dev.owner) return send(400, { ok: false, error: '不能分享给设备所有者' });
      if (!dev.shares) dev.shares = {};
      dev.shares[username] = 'view';
      devicesDirty = true;
      console.log(`[share] ${sess.username} shared ${deviceId} with ${username}`);
      return send(200, { ok: true });
    } catch (e) {
      return send(e.status || 400, { ok: false, error: e.status === 413 ? '请求体过大' : '请求格式错误' });
    }
  }

  if (req.method === 'GET' && url.pathname === '/api/v1/shares') {
    const sess = getSession(req);
    if (!sess) return send(401, { ok: false, error: '未登录' });
    const deviceId = url.searchParams.get('deviceId');
    if (!deviceId) return send(400, { ok: false, error: '缺少 deviceId' });
    const dev = devices.get(sanitizeDeviceId(deviceId));
    if (!dev) return send(404, { ok: false, error: '设备不存在' });
    if (sess.role !== 'admin' && dev.owner !== sess.username)
      return send(403, { ok: false, error: '无权查看该设备共享列表' });
    const shares = dev.shares ? Object.entries(dev.shares).map(([u, p]) => ({ username: u, perm: p })) : [];
    return send(200, { ok: true, shares });
  }

  if (req.method === 'DELETE' && url.pathname === '/api/v1/share') {
    const sess = getSession(req);
    if (!sess) return send(401, { ok: false, error: '未登录' });
    if (sess.role === 'viewer') return send(403, { ok: false, error: 'viewer 无权操作' });
    let body = {};
    try {
      const raw = await readBody(req);
      if (raw && raw.trim()) body = JSON.parse(raw);
    } catch (e) {}
    const deviceId = sanitizeDeviceId(body.deviceId || url.searchParams.get('deviceId') || '');
    const username = String(body.username || url.searchParams.get('username') || '').trim().toLowerCase();
    if (!deviceId || !username) return send(400, { ok: false, error: '缺少 deviceId 或 username' });
    const dev = devices.get(deviceId);
    if (!dev) return send(404, { ok: false, error: '设备不存在' });
    if (sess.role !== 'admin' && dev.owner !== sess.username)
      return send(403, { ok: false, error: '无权操作该设备' });
    if (dev.shares) { delete dev.shares[username]; devicesDirty = true; }
    console.log(`[share] ${sess.username} removed share for ${username} on ${deviceId}`);
    return send(200, { ok: true });
  }

  /* ---- 历史趋势 API ---- */
  if (req.method === 'GET' && url.pathname === '/api/v1/history') {
    const sess = getSession(req);
    if (!sess) return send(401, { ok: false, error: '未登录' });
    const deviceId = url.searchParams.get('deviceId');
    if (!deviceId) return send(400, { ok: false, error: '缺少 deviceId' });
    const id = sanitizeDeviceId(deviceId);
    const dev = devices.get(id);
    if (!dev) return send(404, { ok: false, error: '设备不存在' });
    if (!canAccessDevice(sess, dev))
      return send(403, { ok: false, error: '无权查看该设备历史' });

    let hours = Number(url.searchParams.get('hours')) || 24;
    hours = Math.max(1, Math.min(168, Math.floor(hours)));
    const minutes = hours * 60;
    const stepMin = Math.max(1, Math.ceil(minutes / 500));

    const buckets = history.get(id) || [];
    const cutoff = Date.now() - hours * 3600000;
    const relevant = buckets.filter(b => b.t >= cutoff);

    const points = [];
    for (let i = 0; i < relevant.length; i += stepMin) {
      const group = relevant.slice(i, i + stepMin);
      const ct_n = group.reduce((s, b) => s + (b.ct_n || 0), 0);
      const ot_n = group.reduce((s, b) => s + (b.ot_n || 0), 0);
      const volt_n = group.reduce((s, b) => s + (b.volt_n || 0), 0);
      const spd_n = group.reduce((s, b) => s + (b.spd_n || 0), 0);
      points.push({
        t: group[0].t,
        ct: ct_n > 0 ? round(group.reduce((s, b) => s + (b.ct_s || 0), 0) / ct_n, 1) : null,
        ot: ot_n > 0 ? round(group.reduce((s, b) => s + (b.ot_s || 0), 0) / ot_n, 1) : null,
        volt: volt_n > 0 ? round(group.reduce((s, b) => s + (b.volt_s || 0), 0) / volt_n, 2) : null,
        spd: spd_n > 0 ? round(group.reduce((s, b) => s + (b.spd_s || 0), 0) / spd_n, 1) : null,
      });
    }
    return send(200, { ok: true, deviceId: id, hours, stepMin, points });
  }

  /* ---- 公开：版本 / 下载 ---- */
  if (url.pathname === '/api/v1/latest') {
    const first = (v) => (v ? String(v).split(',')[0].trim() : null);
    const proto = first(req.headers['x-forwarded-proto']) || (req.socket.encrypted ? 'https' : 'http');
    const host = first(req.headers['x-forwarded-host']) || req.headers.host;
    const base = `${proto}://${host}`;
    return send(200, {
      ...LATEST,
      // 带版本号：发新版即换 URL，客户端/系统浏览器不会命中旧包缓存
      apkUrl: `${base}/download/rev-latest.apk?v=${LATEST.versionCode}`,
      carUrl: `${base}/download/rev-car.apk?v=${LATEST.versionCode}`,
      sourceUrl: `${base}/download/REV-Flutter-source.zip?v=${LATEST.versionCode}`,
    });
  }
  if (url.pathname === '/api/v1/artifacts') {
    const seen = new Set();
    const files = [];
    for (const spec of DOWNLOADS.values()) {
      if (seen.has(spec.file)) continue;
      seen.add(spec.file);
      try {
        files.push({ file: spec.file, bytes: fs.statSync(path.join(__dirname, 'download', spec.file)).size });
      } catch (e) {
        files.push({ file: spec.file, bytes: null });
      }
    }
    return send(200, { ok: true, files }, 'application/json; charset=utf-8', { 'Cache-Control': 'no-cache' });
  }
  if (url.pathname.startsWith('/download/')) {
    const spec = DOWNLOADS.get(url.pathname);
    if (!spec) return send(404, { ok: false, error: 'not found' });
    return serveDownload(req, res, spec, send);
  }

  /* ---- 看板 ---- */
  if (url.pathname === '/' || url.pathname === '/index.html') {
    const html = fs.readFileSync(path.join(__dirname, 'dashboard.html'), 'utf8')
      .replace(/\/download\/([A-Za-z0-9._-]+)(?!\?v=)/g,
        `/download/$1?v=${LATEST.versionCode}`)
      .replace(/__REV_VER__/g, LATEST.versionName)
      .replace(/__REV_CODE__/g, String(LATEST.versionCode));
    return send(200, html,
      'text/html; charset=utf-8',
      { 'Content-Security-Policy': CSP_DASHBOARD, 'Cache-Control': 'no-store, must-revalidate' });
  }
  send(404, { ok: false, error: 'not found' });
};

/* ---------------- 启动 ---------------- */
const server = http.createServer(handler);
const server80 = http.createServer(handler);

server.listen(PORT, '0.0.0.0', () => {
  console.log(`REV server v2.17.5 listening on 0.0.0.0:${PORT} (auth + SSE + history + shares)`);
});

server80.on('error', (e) => {
  console.warn(`[warn] 80 端口监听未启用: ${e.code || e.message}`);
});
server80.listen(80, '0.0.0.0', () => {
  console.log('REV server also listening on 0.0.0.0:80');
});

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
  console.warn('[warn] 未找到 TLS 证书，443 HTTPS 未启用');
}

/* ---------------- 定时任务 / 优雅退出 ---------------- */
pruneSessions();
setInterval(pruneSessions, 3600000).unref();
setInterval(sweepDevices, 10 * 60 * 1000).unref();
setInterval(() => { if (devicesDirty) { devicesDirty = false; persistDevices(); } }, 10 * 1000).unref();
setInterval(() => { if (historyDirty) { historyDirty = false; persistHistory(); } }, 5 * 60 * 1000).unref();

for (const sig of ['SIGTERM', 'SIGINT']) {
  process.on(sig, () => {
    console.log(`[shutdown] ${sig} received, persisting sessions/devices/history`);
    try { persistSessions(); } catch (e) {}
    try { persistDevices(); } catch (e) {}
    try { persistHistory(); } catch (e) {}
    process.exit(0);
  });
}

'use strict';

/**
 * 解析请求真实 IP：
 *  - 默认只信任来自本机回环（或 TRUSTED_PROXIES 显式配置）的反向代理；
 *  - 直接暴露在公网的 Node 监听端口一律忽略客户端自带的 X-Forwarded-For /
 *    cf-connecting-ip，避免伪造头绕过登录/注册限流；
 *  - 信任代理时取 XFF 的【最后一跳】（由本机反代追加，客户端无法伪造）；
 *  - cf-connecting-ip 默认不信任，只有显式 TRUST_CF_CONNECTING_IP=1 才启用。
 */
function normalizeAddr(addr) {
  let s = String(addr || '').trim();
  if (s.startsWith('[') && s.includes(']')) s = s.slice(1, s.indexOf(']'));
  if (s.startsWith('::ffff:')) s = s.slice(7);
  return s;
}

function createClientIp(options = {}) {
  const raw = options.trustedProxies;
  const trusted = raw instanceof Set
    ? raw
    : new Set(String(raw == null ? '127.0.0.1,::1' : raw)
        .split(',')
        .map((s) => normalizeAddr(s))
        .filter(Boolean));
  const trustCf = options.trustCf === true;

  return function clientIp(req) {
    const remote = normalizeAddr(req && req.socket && req.socket.remoteAddress);
    const headers = (req && req.headers) || {};
    if (remote && trusted.has(remote)) {
      if (trustCf && headers['cf-connecting-ip']) {
        return normalizeAddr(String(headers['cf-connecting-ip']).split(',')[0]);
      }
      const xf = headers['x-forwarded-for'];
      if (xf) {
        const parts = String(xf).split(',').map((s) => s.trim()).filter(Boolean);
        if (parts.length) return normalizeAddr(parts[parts.length - 1]);
      }
      const real = headers['x-real-ip'];
      if (real) return normalizeAddr(String(real).split(',')[0]);
    }
    return remote || 'unknown';
  };
}

module.exports = { createClientIp, normalizeAddr };

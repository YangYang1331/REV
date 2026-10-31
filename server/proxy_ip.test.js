'use strict';

const test = require('node:test');
const assert = require('node:assert');
const { createClientIp } = require('./proxy_ip');

function req(remote, headers = {}) {
  return { socket: { remoteAddress: remote }, headers };
}

test('公网直连：忽略伪造的 XFF / CF 头', () => {
  const ip = createClientIp();
  const r = req('203.0.113.9', {
    'x-forwarded-for': '1.2.3.4',
    'cf-connecting-ip': '9.9.9.9',
    'x-real-ip': '8.8.8.8',
  });
  assert.strictEqual(ip(r), '203.0.113.9');
});

test('本机反代：取 XFF 最后一跳（最近代理追加）', () => {
  const ip = createClientIp();
  assert.strictEqual(
    ip(req('127.0.0.1', { 'x-forwarded-for': '6.6.6.6, 198.51.100.7' })),
    '198.51.100.7',
  );
  assert.strictEqual(
    ip(req('::ffff:127.0.0.1', { 'x-forwarded-for': '198.51.100.8' })),
    '198.51.100.8',
  );
});

test('本机反代：默认忽略 cf-connecting-ip，显式开启后才使用', () => {
  const off = createClientIp();
  assert.strictEqual(
    off(req('127.0.0.1', { 'cf-connecting-ip': '9.9.9.9' })),
    '127.0.0.1',
  );
  const on = createClientIp({ trustCf: true });
  assert.strictEqual(
    on(req('127.0.0.1', { 'cf-connecting-ip': '9.9.9.9' })),
    '9.9.9.9',
  );
});

test('显式信任的代理地址才生效', () => {
  const ip = createClientIp({ trustedProxies: '10.0.0.2' });
  assert.strictEqual(
    ip(req('10.0.0.2', { 'x-forwarded-for': '198.51.100.9' })),
    '198.51.100.9',
  );
  assert.strictEqual(
    ip(req('10.0.0.3', { 'x-forwarded-for': '198.51.100.9' })),
    '10.0.0.3',
  );
});

test('无 remoteAddress 时回退 unknown', () => {
  assert.strictEqual(createClientIp()(req('', {})), 'unknown');
});

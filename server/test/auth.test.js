'use strict';

const test = require('node:test');
const assert = require('node:assert');

const { authorizeHost, isLoopback, safeEqual, newToken } = require('../lib/auth');

test('loopback addresses are recognised in both families', () => {
  assert.ok(isLoopback('127.0.0.1'));
  assert.ok(isLoopback('::1'));
  assert.ok(isLoopback('::ffff:127.0.0.1'));
  assert.ok(!isLoopback('192.168.1.40'));
  assert.ok(!isLoopback(''));
  assert.ok(!isLoopback(undefined));
});

test('safeEqual matches identical secrets and nothing else', () => {
  assert.ok(safeEqual('abc123', 'abc123'));
  assert.ok(!safeEqual('abc123', 'abc124'));
  assert.ok(!safeEqual('abc123', 'abc1234'));
  // An empty presented token must never satisfy an empty expectation.
  assert.ok(!safeEqual('', ''));
  assert.ok(!safeEqual(undefined, undefined));
});

test('newToken returns distinct, long hex strings', () => {
  const a = newToken();
  const b = newToken();
  assert.notStrictEqual(a, b);
  assert.match(a, /^[0-9a-f]{48}$/);
});

test('with a token configured, only the matching token gets the host role', () => {
  const base = { remoteAddress: '192.168.1.40', expectedToken: 'secret', hostConnected: false };

  assert.deepStrictEqual(authorizeHost({ ...base, presentedToken: 'secret' }), { ok: true });
  assert.strictEqual(authorizeHost({ ...base, presentedToken: 'wrong' }).ok, false);
  assert.strictEqual(authorizeHost({ ...base, presentedToken: '' }).ok, false);
  assert.strictEqual(authorizeHost({ ...base, presentedToken: undefined }).ok, false);
});

test('a correct token is accepted from anywhere, not just loopback', () => {
  const verdict = authorizeHost({
    presentedToken: 'secret',
    remoteAddress: '10.0.0.99',
    expectedToken: 'secret',
    hostConnected: false,
  });
  assert.ok(verdict.ok);
});

test('without a token configured, the host must be local', () => {
  const base = { presentedToken: null, expectedToken: '', hostConnected: false };

  assert.ok(authorizeHost({ ...base, remoteAddress: '127.0.0.1' }).ok);
  assert.ok(authorizeHost({ ...base, remoteAddress: '::1' }).ok);

  const remote = authorizeHost({ ...base, remoteAddress: '192.168.1.40' });
  assert.strictEqual(remote.ok, false);
  assert.match(remote.reason, /AUTOBATTLE_HOST_TOKEN/);
});

test('a second host is refused even with the right credentials', () => {
  const withToken = authorizeHost({
    presentedToken: 'secret',
    remoteAddress: '127.0.0.1',
    expectedToken: 'secret',
    hostConnected: true,
  });
  assert.strictEqual(withToken.ok, false);
  assert.match(withToken.reason, /already connected/);

  // The loopback path must not offer a way around it either.
  const local = authorizeHost({
    presentedToken: null,
    remoteAddress: '127.0.0.1',
    expectedToken: '',
    hostConnected: true,
  });
  assert.strictEqual(local.ok, false);
});

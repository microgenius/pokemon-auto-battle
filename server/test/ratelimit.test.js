'use strict';

const test = require('node:test');
const assert = require('node:assert');

const { RateLimiter } = require('../lib/ratelimit');

test('the burst is spent one message at a time, then refused', () => {
  const limiter = new RateLimiter(3, 10);
  const t = 1_000_000;

  assert.ok(limiter.allow(t));
  assert.ok(limiter.allow(t));
  assert.ok(limiter.allow(t));
  assert.strictEqual(limiter.allow(t), false);
});

test('tokens refill at the configured rate', () => {
  const limiter = new RateLimiter(3, 10); // 10/s => one token every 100ms
  const t = 1_000_000;

  for (let i = 0; i < 3; i += 1) limiter.allow(t);
  assert.strictEqual(limiter.allow(t), false);

  assert.strictEqual(limiter.allow(t + 50), false, 'half a token is not enough');
  assert.ok(limiter.allow(t + 100), 'one token has accrued');
  assert.strictEqual(limiter.allow(t + 100), false);
});

test('refill never exceeds the burst capacity', () => {
  const limiter = new RateLimiter(3, 10);
  const t = 1_000_000;

  limiter.allow(t);
  // A long idle period must not bank unlimited credit.
  const later = t + 60_000;
  assert.ok(limiter.allow(later));
  assert.ok(limiter.allow(later));
  assert.ok(limiter.allow(later));
  assert.strictEqual(limiter.allow(later), false);
});

test('a clock that goes backwards does not grant free tokens', () => {
  const limiter = new RateLimiter(2, 10);
  const t = 1_000_000;

  assert.ok(limiter.allow(t));
  assert.ok(limiter.allow(t));
  assert.strictEqual(limiter.allow(t - 5_000), false);
});

test('a sustained sender is held to the configured rate', () => {
  const limiter = new RateLimiter(20, 10);
  let now = 1_000_000;

  for (let i = 0; i < 20; i += 1) assert.ok(limiter.allow(now));
  assert.strictEqual(limiter.allow(now), false);

  // One second later, exactly ten more get through.
  now += 1000;
  let allowed = 0;
  for (let i = 0; i < 50; i += 1) {
    if (limiter.allow(now)) allowed += 1;
  }
  assert.strictEqual(allowed, 10);
});

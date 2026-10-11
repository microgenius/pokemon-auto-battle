'use strict';

/**
 * Per-connection token bucket.
 *
 * A spectator socket had no ceiling on how fast it could send: a loop firing
 * PLACE_BETS pinned the event loop and every accepted slip triggered a
 * broadcast to everyone else, so one client could stall the whole room.
 *
 * `now` is injected rather than read from Date.now() inside, so the refill
 * behaviour can be tested without sleeping.
 */
class RateLimiter {
  /**
   * @param {number} capacity        Burst size — messages allowed back to back.
   * @param {number} refillPerSecond Sustained rate once the burst is spent.
   */
  constructor(capacity = 20, refillPerSecond = 10) {
    this.capacity = capacity;
    this.refillPerSecond = refillPerSecond;
    this.tokens = capacity;
    this.lastRefill = null;
  }

  /** Consumes one token. Returns false when the caller is over budget. */
  allow(now = Date.now()) {
    if (this.lastRefill === null) this.lastRefill = now;

    const elapsedSeconds = Math.max(0, (now - this.lastRefill) / 1000);
    this.tokens = Math.min(this.capacity, this.tokens + elapsedSeconds * this.refillPerSecond);
    this.lastRefill = now;

    if (this.tokens < 1) return false;
    this.tokens -= 1;
    return true;
  }
}

module.exports = { RateLimiter };

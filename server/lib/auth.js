'use strict';

const crypto = require('crypto');

/**
 * Who is allowed to be the host, and who owns a username.
 *
 * Pure decisions over plain data — no sockets — so the rules can be tested
 * directly. The stores that persist identities live in ./identities.
 */

/** Addresses that count as "this machine" for the loopback fallback. */
const LOOPBACK_ADDRESSES = new Set(['127.0.0.1', '::1', '::ffff:127.0.0.1']);

function isLoopback(address) {
  return LOOPBACK_ADDRESSES.has(String(address || ''));
}

/**
 * Compares two secrets without leaking their contents through timing. Length
 * mismatch short-circuits, which is fine: the length of a token is not secret.
 */
function safeEqual(a, b) {
  const left = Buffer.from(String(a == null ? '' : a), 'utf8');
  const right = Buffer.from(String(b == null ? '' : b), 'utf8');
  if (left.length !== right.length || left.length === 0) return false;
  return crypto.timingSafeEqual(left, right);
}

function newToken() {
  return crypto.randomBytes(24).toString('hex');
}

/**
 * Decides whether a connection asking for `?role=host` may have it.
 *
 * With AUTOBATTLE_HOST_TOKEN set, the token has to match. Without one the host may
 * only connect from this machine — that keeps `npm start` plus F5 in the editor
 * working with no configuration, while refusing a takeover from anywhere else
 * on the network. Previously any connection carrying `role=host` in the URL
 * became the host and could fabricate MATCH_RESULTS.
 *
 * A second host is always refused rather than silently replacing the first.
 */
function authorizeHost({ presentedToken, remoteAddress, expectedToken, hostConnected }) {
  if (hostConnected) {
    return { ok: false, reason: 'a host is already connected' };
  }

  if (expectedToken) {
    return safeEqual(presentedToken, expectedToken)
      ? { ok: true }
      : { ok: false, reason: 'invalid host token' };
  }

  return isLoopback(remoteAddress)
    ? { ok: true }
    : { ok: false, reason: 'AUTOBATTLE_HOST_TOKEN is not set, so only a local host is accepted' };
}

module.exports = { authorizeHost, isLoopback, safeEqual, newToken, LOOPBACK_ADDRESSES };

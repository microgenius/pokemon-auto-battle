'use strict';

const { BET_TYPES } = require('./config');

/**
 * Input validation for anything a spectator sends.
 *
 * Pure functions so the rules can be tested without a socket. Everything that
 * arrives over a WebSocket is attacker-controlled, including from a browser we
 * shipped ourselves.
 */

const MAX_USERNAME_LENGTH = 12;

/** Trims, caps the length, and rejects anything left over that is not printable. */
function sanitizeUsername(raw) {
  const value = String(raw == null ? '' : raw)
    .trim()
    .slice(0, MAX_USERNAME_LENGTH);
  // Control characters would render as invisible or line-breaking glyphs and
  // make two different names look identical in the UI.
  return /[\u0000-\u001F\u007F]/.test(value) ? '' : value;
}

/**
 * Filters a slip down to bets that are actually placeable.
 *
 * `choice` is a roster-slot alias ("candidate1"), checked against the aliases the
 * host broadcast. Without that, a spectator could bet on an arbitrary string,
 * which polluted `gameState.bets` with keys that no fighter would ever match and
 * fed unvetted text back into the results screen.
 */
function sanitizeBets(incoming, roster) {
  if (!Array.isArray(incoming)) return [];

  const allowed = new Set();
  for (const option of Array.isArray(roster) ? roster : []) {
    if (option && option.alias) allowed.add(String(option.alias));
  }

  const seenTypes = new Set();
  const valid = [];

  for (const bet of incoming) {
    if (!bet || typeof bet !== 'object') continue;

    const type = String(bet.type || '');
    if (!BET_TYPES.includes(type)) continue;
    // One bet per market; a slip with two winner bets would be debited twice
    // but only settled once.
    if (seenTypes.has(type)) continue;

    const wager = Number.parseInt(bet.wager, 10);
    if (!Number.isFinite(wager) || wager <= 0) continue;

    const choice = String(bet.choice || '');
    if (!allowed.has(choice)) continue;

    seenTypes.add(type);
    valid.push({ type, choice, wager });
  }

  return valid;
}

module.exports = { sanitizeUsername, sanitizeBets, MAX_USERNAME_LENGTH };

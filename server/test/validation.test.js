'use strict';

const test = require('node:test');
const assert = require('node:assert');

const { sanitizeUsername, sanitizeBets } = require('../lib/validation');

/** Bets reference the slot alias; the name is only ever displayed. */
const aliasOf = (name) => `c_${String(name).toLowerCase()}`;
const ROSTER = ['Bulbasaur', 'Charmander', 'Squirtle'].map((name) => ({ alias: aliasOf(name), name }));

test('usernames are trimmed and capped', () => {
  assert.strictEqual(sanitizeUsername('  sezer  '), 'sezer');
  assert.strictEqual(sanitizeUsername('a'.repeat(30)), 'a'.repeat(12));
  assert.strictEqual(sanitizeUsername(''), '');
  assert.strictEqual(sanitizeUsername(null), '');
  assert.strictEqual(sanitizeUsername(undefined), '');
});

test('usernames carrying control characters are rejected outright', () => {
  assert.strictEqual(sanitizeUsername('ali\u0000bot'), '');
  assert.strictEqual(sanitizeUsername('two\nlines'), '');
  assert.strictEqual(sanitizeUsername('tab\there'), '');
});

test('a bet on a fighter outside the roster is dropped', () => {
  const bets = sanitizeBets(
    [{ type: 'winner', choice: '<img src=x onerror=alert(1)>', wager: 50 }],
    ROSTER
  );
  assert.deepStrictEqual(bets, []);
});

test('a bet naming a fighter instead of its alias is dropped', () => {
  // Display names are not identities. Accepting one would reopen the whole
  // class of mismatch the alias exists to close.
  assert.deepStrictEqual(sanitizeBets([{ type: 'winner', choice: 'Bulbasaur', wager: 50 }], ROSTER), []);
  assert.deepStrictEqual(sanitizeBets([{ type: 'winner', choice: 'bULBaSAUR', wager: 50 }], ROSTER), []);
});

test('an alias is taken exactly as given', () => {
  const bets = sanitizeBets([{ type: 'winner', choice: aliasOf('Bulbasaur'), wager: 50 }], ROSTER);
  assert.deepStrictEqual(bets, [{ type: 'winner', choice: aliasOf('Bulbasaur'), wager: 50 }]);
});

test('unknown markets and non-positive wagers are dropped', () => {
  const bets = sanitizeBets(
    [
      { type: 'not_a_market', choice: aliasOf('Bulbasaur'), wager: 50 },
      { type: 'winner', choice: aliasOf('Bulbasaur'), wager: 0 },
      { type: 'first_hit', choice: aliasOf('Squirtle'), wager: -10 },
      { type: 'kill_king', choice: aliasOf('Squirtle'), wager: 'abc' },
      { type: 'dodge_king', choice: aliasOf('Squirtle'), wager: 25 },
    ],
    ROSTER
  );
  assert.deepStrictEqual(bets, [{ type: 'dodge_king', choice: aliasOf('Squirtle'), wager: 25 }]);
});

test('only the first bet per market survives', () => {
  const bets = sanitizeBets(
    [
      { type: 'winner', choice: aliasOf('Bulbasaur'), wager: 10 },
      { type: 'winner', choice: aliasOf('Squirtle'), wager: 999 },
    ],
    ROSTER
  );
  assert.deepStrictEqual(bets, [{ type: 'winner', choice: aliasOf('Bulbasaur'), wager: 10 }]);
});

test('junk input never throws', () => {
  assert.deepStrictEqual(sanitizeBets(undefined, ROSTER), []);
  assert.deepStrictEqual(sanitizeBets('not an array', ROSTER), []);
  assert.deepStrictEqual(sanitizeBets([null, 42, 'x'], ROSTER), []);
  assert.deepStrictEqual(sanitizeBets([{ type: 'winner', choice: aliasOf('Bulbasaur'), wager: 5 }], []), []);
  assert.deepStrictEqual(sanitizeBets([{ type: 'winner', choice: aliasOf('Bulbasaur'), wager: 5 }], null), []);
});

test('fractional wagers are floored by parseInt, not rounded up', () => {
  const bets = sanitizeBets([{ type: 'winner', choice: aliasOf('Bulbasaur'), wager: 10.9 }], ROSTER);
  assert.deepStrictEqual(bets, [{ type: 'winner', choice: aliasOf('Bulbasaur'), wager: 10 }]);
});

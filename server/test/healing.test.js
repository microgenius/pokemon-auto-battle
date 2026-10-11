'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const { authorizeHeal, healCost, stakeOn, healStateFor } = require('../lib/healing');
const { HEAL_TIERS, HEAL_COOLDOWN_MS, HEAL_MATCH_CAP, HEAL_MIN_COST } = require('../lib/config');

const ROSTER = [{ alias: 'candidate1', name: 'Bulbasaur' }, { alias: 'candidate2', name: 'Charmander' }];
const SMALL = HEAL_TIERS.find((t) => t.id === 'small');
const LARGE = HEAL_TIERS.find((t) => t.id === 'large');

function req(overrides = {}) {
  return {
    tierId: 'small',
    alias: 'candidate1',
    roster: ROSTER,
    status: 'BATTLING',
    balance: 1000,
    targetMaxHp: 300,
    targetAlive: true,
    now: 1_000_000,
    ...overrides,
  };
}

// ---------------------------------------------------------------- pricing

test('the price is a multiple of the money staked on that fighter', () => {
  // The headline case: back a fighter with 150 CP, a full heal on it costs ~150.
  assert.equal(healCost('large', 150), 150);
  assert.equal(healCost('small', 150), 60);
});

test('a fighter nobody has backed still costs the floor', () => {
  assert.equal(healCost('large', 0), HEAL_MIN_COST);
  assert.equal(healCost('small', 0), HEAL_MIN_COST);
  assert.equal(healCost('large', 10), HEAL_MIN_COST);
});

test('the price rises with the room, not with one bettor', () => {
  assert.ok(healCost('large', 400) > healCost('large', 150));
  assert.equal(healCost('large', 400), 400);
});

test('an unknown tier has no price', () => {
  assert.equal(healCost('enormous', 0), null);
});

test('stakeOn totals every bettor and every market on that fighter', () => {
  const userBets = {
    sezer: { wager: 60, bets: [
      { type: 'winner', choice: 'candidate1', wager: 30 },
      { type: 'kill_king', choice: 'candidate1', wager: 20 },
      { type: 'dodge_king', choice: 'candidate2', wager: 10 },
    ] },
    deniz: { wager: 100, bets: [{ type: 'winner', choice: 'candidate1', wager: 100 }] },
  };
  assert.equal(stakeOn(userBets, 'candidate1'), 150);
  assert.equal(stakeOn(userBets, 'candidate2'), 10);
  assert.equal(stakeOn(userBets, 'candidate9'), 0);
  assert.equal(stakeOn({}, 'candidate1'), 0);
  assert.equal(stakeOn(null, 'candidate1'), 0);
});

// ---------------------------------------------------------------- authorisation

test('a plain heal is allowed and sized against max HP', () => {
  const verdict = authorizeHeal(req({ stake: 150 }));
  assert.ok(verdict.ok);
  assert.equal(verdict.cost, 60);
  assert.equal(verdict.amount, Math.round(300 * SMALL.fraction));
});

test('a dead fighter cannot be healed', () => {
  assert.equal(authorizeHeal(req({ targetAlive: false })).ok, false);
});

test('healing is refused outside a live match', () => {
  for (const status of ['WAITING', 'LOBBY', 'END']) {
    assert.equal(authorizeHeal(req({ status })).ok, false);
  }
});

test('an unknown fighter or tier is refused', () => {
  assert.equal(authorizeHeal(req({ alias: 'candidate9' })).ok, false);
  assert.equal(authorizeHeal(req({ tierId: 'colossal' })).ok, false);
});

test('the cooldown is room-wide, blocks, and then lets go', () => {
  const now = 1_000_000;
  // Whoever healed last, everyone waits — the timestamp is not per user.
  const blocked = authorizeHeal(req({ lastHealAt: now - 1000, now }));
  assert.equal(blocked.ok, false);
  assert.match(blocked.reason, /bekleme/);
  assert.ok(blocked.cooldownLeftMs > 0);

  assert.ok(authorizeHeal(req({ lastHealAt: now - HEAL_COOLDOWN_MS, now })).ok);
});

test('a wallet that cannot cover the price is refused', () => {
  assert.ok(authorizeHeal(req({ balance: HEAL_MIN_COST, stake: 0 })).ok);
  assert.equal(authorizeHeal(req({ balance: HEAL_MIN_COST, stake: 500 })).ok, false);
});

test('one fighter cannot be healed past the per-match cap', () => {
  assert.equal(authorizeHeal(req({ healedThisMatch: HEAL_MATCH_CAP })).ok, false);
});

test('the last heal before the cap is trimmed to what it can deliver', () => {
  // Only 5% of the cap left, but a large heal was asked for.
  const verdict = authorizeHeal(req({ tierId: 'large', healedThisMatch: HEAL_MATCH_CAP - 0.05 }));
  assert.ok(verdict.ok);
  // The fraction is float arithmetic on the cap, so compare the HP it buys —
  // that is the integer the wallet and the fighter actually see.
  assert.equal(verdict.amount, 15);
  assert.ok(verdict.fraction < LARGE.fraction);
  assert.ok(verdict.amount < Math.round(300 * LARGE.fraction));
});

test('a fighter with no reported max HP heals for nothing rather than throwing', () => {
  const verdict = authorizeHeal(req({ targetMaxHp: 0 }));
  assert.ok(verdict.ok);
  assert.equal(verdict.amount, 0);
});


// ---------------------------------------------------------------- UI state

test('healStateFor prices and gates every fighter for the page', () => {
  const state = healStateFor({
    roster: ROSTER,
    userBets: { sezer: { bets: [{ type: 'winner', choice: 'candidate1', wager: 150 }] } },
    status: 'BATTLING',
    balance: 1000,
    lastHealAt: 0,
    healedThisMatch: {},
    liveStats: {
      candidate1: { max_hp: 300, hp: 120 },
      candidate2: { max_hp: 300, hp: 0 },   // dead
    },
    now: 1_000_000,
  });

  assert.equal(state.fighters.candidate1.large.cost, 150);
  assert.ok(state.fighters.candidate1.large.ok);

  // A dead fighter is priced but refused, so the page can grey the row out.
  assert.equal(state.fighters.candidate2.large.ok, false);
  assert.match(state.fighters.candidate2.large.reason, /hayatta/);
});

test('healStateFor reports the cooldown the whole room is serving', () => {
  const now = 1_000_000;
  const state = healStateFor({
    roster: ROSTER, userBets: {}, status: 'BATTLING', balance: 1000,
    lastHealAt: now - 5000, healedThisMatch: {},
    liveStats: { candidate1: { max_hp: 300, hp: 100 } }, now,
  });

  assert.equal(state.cooldownLeftMs, HEAL_COOLDOWN_MS - 5000);
  assert.equal(state.fighters.candidate1.small.ok, false);
});

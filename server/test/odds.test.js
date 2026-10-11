'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const {
  calculateOdds,
  priceFor,
  normalise,
  MARKETS,
  MIN_ODDS,
  MAX_ODDS,
} = require('../lib/odds');
const { ODDS_PAYBACK } = require('../lib/config');

/** Minimal roster entry; overrides win. */
/**
 * Aliases are opaque in production ("candidate1"). Here they are derived from
 * the name so a test can name the fighter it means: A.bulbasaur.
 */
const aliasOf = (name) => `c_${String(name).toLowerCase()}`;
const A = new Proxy({}, { get: (_target, key) => `c_${String(key)}` });

function mon(name, overrides = {}) {
  return {
    // Odds key on the alias, not the name — that is the whole point.
    alias: aliasOf(name),
    name,
    base_hp: 50,
    base_atk: 50,
    base_def: 50,
    base_sp_atk: 50,
    base_sp_def: 50,
    base_spd: 50,
    evolution_level: -1,
    stage: 1,
    max_stages: 3,
    ...overrides,
  };
}

const ROSTER = [
  mon('Bulbasaur', { base_hp: 45, base_atk: 49, base_def: 49, base_sp_atk: 65, base_sp_def: 65, base_spd: 45, evolution_level: 16 }),
  mon('Charmander', { base_hp: 39, base_atk: 52, base_def: 43, base_sp_atk: 60, base_sp_def: 50, base_spd: 65, evolution_level: 16 }),
  mon('Abra', { base_hp: 25, base_atk: 20, base_def: 15, base_sp_atk: 105, base_sp_def: 55, base_spd: 90, evolution_level: 16 }),
];

const EXCLUSIVE_MARKETS = Object.keys(MARKETS);
const ALL_MARKETS = [...EXCLUSIVE_MARKETS, 'incomplete_evolution'];

test('prices every market for every roster entry', () => {
  const odds = calculateOdds(ROSTER);

  for (const entry of ROSTER) {
    for (const market of ALL_MARKETS) {
      const key = `${market}_${entry.alias}`;
      assert.ok(odds[key] !== undefined, `missing ${key}`);
      assert.ok(odds[key] >= MIN_ODDS, `${key} should never price below the floor`);
      assert.ok(odds[key] <= MAX_ODDS, `${key} should never price above the cap`);
    }
  }
});

// The bug this whole model replaces: the favourite used to sit at 1.05x on a
// board where its real chance was one in three, handing back 35 CP per 100.
test('a fair board pays back the configured fraction, not a fraction of it', () => {
  const odds = calculateOdds(ROSTER);
  const evens = normalise([1, 1, 1], MARKETS.winner.sharpness);

  // Three identical fighters each have a one-in-three chance.
  const flat = calculateOdds([mon('A'), mon('B'), mon('C')]);
  assert.equal(evens[0], 1 / 3);
  assert.ok(
    Math.abs(flat[`winner_${A.a}`] - ODDS_PAYBACK * 3) < 0.02,
    `an even three-way should price near ${(ODDS_PAYBACK * 3).toFixed(2)}x, got ${flat[`winner_${A.a}`]}x`
  );

  // And nothing on a real board is anywhere near the old 1.05x floor.
  for (const entry of ROSTER) {
    assert.ok(odds[`winner_${entry.alias}`] > 2, 'winner odds should be real prices');
  }
});

test('implied probabilities across an exclusive market sum to one', () => {
  const odds = calculateOdds(ROSTER);

  for (const market of EXCLUSIVE_MARKETS) {
    const implied = ROSTER.reduce(
      (sum, e) => sum + ODDS_PAYBACK / odds[`${market}_${e.alias}`],
      0
    );
    assert.ok(
      Math.abs(implied - 1) < 0.02,
      `${market} implied probabilities sum to ${implied.toFixed(3)}, expected ~1`
    );
  }
});

test('expected value per market equals the payback setting', () => {
  const flat = calculateOdds([mon('A'), mon('B'), mon('C'), mon('D')]);
  // Four identical fighters: p = 0.25, so a 100 CP stake returns 100 * payback.
  const ev = 0.25 * flat[`winner_${A.a}`];
  assert.ok(Math.abs(ev - ODDS_PAYBACK) < 0.01, `EV was ${ev}, expected ${ODDS_PAYBACK}`);
});

test('the favourite is the shortest price, the long shot the longest', () => {
  const odds = calculateOdds(ROSTER);

  // Base stat totals: Bulbasaur 318, Abra 310, Charmander 309.
  assert.ok(odds[`winner_${A.bulbasaur}`] < odds[`winner_${A.charmander}`]);
  // Speeds: Abra 90 > Charmander 65 > Bulbasaur 45, so dodge prices rank inversely.
  assert.ok(odds[`dodge_king_${A.abra}`] < odds[`dodge_king_${A.charmander}`]);
  assert.ok(odds[`dodge_king_${A.charmander}`] < odds[`dodge_king_${A.bulbasaur}`]);
});

test('no two markets price identically', () => {
  const odds = calculateOdds(ROSTER);
  const vector = (market) => ROSTER.map((e) => odds[`${market}_${e.alias}`]).join(',');

  for (let i = 0; i < ALL_MARKETS.length; i += 1) {
    for (let j = i + 1; j < ALL_MARKETS.length; j += 1) {
      assert.notEqual(
        vector(ALL_MARKETS[i]),
        vector(ALL_MARKETS[j]),
        `${ALL_MARKETS[i]} and ${ALL_MARKETS[j]} are the same model — one of them is redundant`
      );
    }
  }
});

test('a bigger board pays longer prices', () => {
  const three = calculateOdds([mon('A'), mon('B'), mon('C')]);
  const six = calculateOdds([mon('A'), mon('B'), mon('C'), mon('D'), mon('E'), mon('F')]);

  assert.ok(six[`winner_${A.a}`] > three[`winner_${A.a}`], 'one of six is harder than one of three');
});

test('incomplete_evolution is shorter the further a fighter is from its final form', () => {
  const odds = calculateOdds([
    mon('Bulbasaur', { stage: 1, max_stages: 3 }),  // two steps to go
    mon('Ivysaur', { stage: 2, max_stages: 3 }),    // one step to go
  ]);

  // Two steps left is likelier to be left unfinished, so it pays less.
  assert.ok(
    odds[`incomplete_evolution_${A.bulbasaur}`] < odds[`incomplete_evolution_${A.ivysaur}`],
    'a fighter further from its final form should be the shorter price'
  );
});

test('a species with nothing left to evolve into is not priced at all', () => {
  const odds = calculateOdds([
    mon('Tauros', { stage: 1, max_stages: 1 }),
    mon('Bulbasaur', { stage: 1, max_stages: 3 }),
  ]);

  // The outcome is impossible, so offering any price would be a trap.
  assert.equal(odds[`incomplete_evolution_${A.tauros}`], undefined);
  assert.ok(odds[`incomplete_evolution_${A.bulbasaur}`] > 1);
  // Its other markets are unaffected.
  assert.ok(odds[`winner_${A.tauros}`] > 1);
});

test('a final-form fighter is unpriced even mid-roster', () => {
  const odds = calculateOdds([
    mon('Venusaur', { stage: 3, max_stages: 3 }),
    mon('Charmander', { stage: 1, max_stages: 3 }),
  ]);
  assert.equal(odds[`incomplete_evolution_${A.venusaur}`], undefined);
});

test('the market pays far shorter than the exclusive ones', () => {
  const odds = calculateOdds([mon('A'), mon('B'), mon('C'), mon('D'), mon('E')]);

  // Frequent, guessable, modest — that is the whole point of this market.
  assert.ok(
    odds[`incomplete_evolution_${A.a}`] < odds[`winner_${A.a}`],
    'falling short of a final form is much likelier than winning the match'
  );
  assert.ok(odds[`incomplete_evolution_${A.a}`] < 3);
});

test('priceFor is the whole rule: payback over probability, clamped', () => {
  assert.equal(priceFor(0.5), Math.round((ODDS_PAYBACK / 0.5) * 100) / 100);
  assert.equal(priceFor(1), MIN_ODDS, 'a certainty still pays the floor');
  assert.equal(priceFor(0), MAX_ODDS, 'an impossibility is capped, not infinite');
  assert.equal(priceFor(-1), MAX_ODDS);
  assert.equal(priceFor(0.0000001), MAX_ODDS);
});

test('normalise turns weights into probabilities summing to one', () => {
  const p = normalise([10, 20, 30], 1);
  assert.ok(Math.abs(p.reduce((a, b) => a + b, 0) - 1) < 1e-9);
  assert.ok(p[2] > p[1] && p[1] > p[0]);
});

test('sharpness concentrates probability on the leader', () => {
  const flat = normalise([10, 20], 1);
  const sharp = normalise([10, 20], 3);
  assert.ok(sharp[1] > flat[1], 'a higher exponent should favour the leader more');
});

test('all-zero weights fall back to an even split rather than dividing by zero', () => {
  const p = normalise([0, 0, 0], 2);
  assert.deepEqual(p, [1 / 3, 1 / 3, 1 / 3]);
});

test('missing base stats fall back instead of producing NaN', () => {
  const odds = calculateOdds([{ name: 'Mystery' }, mon('Pikachu')]);
  for (const value of Object.values(odds)) {
    assert.ok(Number.isFinite(value), 'every price should be a finite number');
  }
});

test('an empty roster prices nothing rather than throwing', () => {
  assert.deepEqual(calculateOdds([]), {});
  assert.deepEqual(calculateOdds(null), {});
});

test('a single-entry roster prices at the floor', () => {
  const odds = calculateOdds([mon('Solo')]);
  assert.equal(odds[`winner_${A.solo}`], MIN_ODDS, 'a certainty cannot pay a premium');
});


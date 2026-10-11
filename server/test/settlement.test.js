'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');

const { settleBets, resolveOutcomes, judgeBet, leaderBy } = require('../lib/settlement');

/**
 * Slot aliases are what settlement matches on; the name rides along only so the
 * results screen has something to print. They are derived from the name here so
 * a test can say what it means.
 */
const aliasOf = (name) => `c_${String(name).toLowerCase()}`;

function stats(name, overrides = {}) {
  return {
    alias: aliasOf(name),
    name,
    kills: 0,
    attacks: 0,
    hits: 0,
    dodges: 0,
    criticals: 0,
    has_evolved: false,
    evolution_count: 0,
    ...overrides,
  };
}

const MATCH = {
  winner: aliasOf('Ivysaur'),
  first_blood: aliasOf('Ivysaur'),
  first_hit: aliasOf('Kadabra'),
  all_stats: [
    // Ivysaur won, and is mid-line (Venusaur still ahead of it).
    stats('Ivysaur', { kills: 3, dodges: 2, criticals: 1, has_evolved: true, evolution_complete: false }),
    // Kadabra died one step short of Alakazam.
    stats('Kadabra', { kills: 1, dodges: 9, criticals: 4, has_evolved: true, evolution_complete: false }),
    // Tauros cannot evolve at all, so it is complete the moment it spawns.
    stats('Tauros', { kills: 0, dodges: 1, criticals: 0, evolution_complete: true }),
  ],
};

const ODDS = {
  [`winner_${aliasOf('Ivysaur')}`]: 1.5,
  [`winner_${aliasOf('Kadabra')}`]: 2.0,
  [`first_blood_${aliasOf('Ivysaur')}`]: 1.4,
  [`first_hit_${aliasOf('Kadabra')}`]: 1.2,
  [`kill_king_${aliasOf('Ivysaur')}`]: 1.6,
  [`dodge_king_${aliasOf('Kadabra')}`]: 1.1,
  [`crit_king_${aliasOf('Kadabra')}`]: 1.2,
  [`incomplete_evolution_${aliasOf('Kadabra')}`]: 2.0,
};

// ---------------------------------------------------------------- outcomes

test('resolves each market from the end-of-match report', () => {
  const outcomes = resolveOutcomes(MATCH);
  assert.equal(outcomes.winner, aliasOf('Ivysaur'));
  assert.equal(outcomes.first_blood, aliasOf('Ivysaur'));
  assert.equal(outcomes.first_hit, aliasOf('Kadabra'));
  assert.equal(outcomes.kill_king, aliasOf('Ivysaur'));
  assert.equal(outcomes.dodge_king, aliasOf('Kadabra'));
  assert.equal(outcomes.crit_king, aliasOf('Kadabra'));
  // Only Kadabra: Ivysaur won, and Tauros had already finished its (empty) line.
  assert.deepEqual(outcomes.incomplete_evolution, [aliasOf('Kadabra')]);
});

test('falls back to live event data when the report omits a field', () => {
  const outcomes = resolveOutcomes(
    { winner: aliasOf('Abra'), all_stats: [] },
    { firstBlood: aliasOf('Charmander'), firstHit: aliasOf('Abra') }
  );
  assert.equal(outcomes.first_blood, aliasOf('Charmander'));
  assert.equal(outcomes.first_hit, aliasOf('Abra'));
});

test('leaderBy returns an empty string for an empty field set', () => {
  assert.equal(leaderBy([], 'kills'), '');
});

// ---------------------------------------------------------------- judging

test('judges bets on the alias, exactly — names never enter the comparison', () => {
  const outcomes = resolveOutcomes(MATCH);

  assert.equal(judgeBet({ type: 'winner', choice: aliasOf('Ivysaur') }, outcomes).won, true);
  assert.equal(judgeBet({ type: 'winner', choice: aliasOf('Abra') }, outcomes).won, false);
  // The display name is not an identity and must not win a bet.
  assert.equal(judgeBet({ type: 'winner', choice: 'Ivysaur' }, outcomes).won, false);
  assert.equal(judgeBet({ type: 'winner', choice: 'IVYSAUR' }, outcomes).won, false);
});

test('a bet struck before an evolution still settles on the same fighter', () => {
  // The punter backed candidate1 while it was a Bulbasaur; it ended as Ivysaur.
  // Nothing in the slip was rewritten — the alias never moved.
  const outcomes = resolveOutcomes(MATCH);
  const verdict = judgeBet({ type: 'winner', choice: aliasOf('Ivysaur') }, outcomes,
    { [aliasOf('Ivysaur')]: 'Ivysaur' });

  assert.equal(verdict.won, true);
  assert.equal(verdict.actual, 'Ivysaur', 'the results screen shows the final name');
});

test('the breakdown reports display names, not aliases', () => {
  const { results } = settleBets({
    userBets: { sezer: { bets: [{ type: 'winner', choice: aliasOf('Ivysaur'), wager: 100 }], wager: 100 } },
    userPoints: { sezer: 900 },
    currentOdds: ODDS,
    matchResults: MATCH,
  });

  const bet = results.users[0].bets[0];
  assert.equal(bet.choice, 'Ivysaur', 'nobody wants to read "c_ivysaur" on the results screen');
  assert.equal(bet.actual, 'Ivysaur');
});

test('incomplete_evolution wins only for a fighter that died short of its final form', () => {
  const outcomes = resolveOutcomes(MATCH);

  assert.equal(judgeBet({ type: 'incomplete_evolution', choice: aliasOf('Kadabra') }, outcomes).won, true);
  // Won the match, so it did not die at all — mid-line or not.
  assert.equal(judgeBet({ type: 'incomplete_evolution', choice: aliasOf('Ivysaur') }, outcomes).won, false);
  // Died, but a species with no evolution is complete by definition.
  assert.equal(judgeBet({ type: 'incomplete_evolution', choice: aliasOf('Tauros') }, outcomes).won, false);
});

test('a fighter that finished its line and died still loses the market', () => {
  const outcomes = resolveOutcomes({
    winner: aliasOf('Abra'),
    all_stats: [
      stats('Abra', { evolution_complete: false }),
      stats('Venusaur', { has_evolved: true, evolution_complete: true }),
    ],
  });
  assert.deepEqual(outcomes.incomplete_evolution, []);
  assert.equal(judgeBet({ type: 'incomplete_evolution', choice: aliasOf('Venusaur') }, outcomes).won, false);
});

test('an unknown market loses rather than throwing', () => {
  const outcomes = resolveOutcomes(MATCH);
  const verdict = judgeBet({ type: 'nonsense', choice: aliasOf('Abra') }, outcomes);
  assert.equal(verdict.won, false);
  assert.equal(verdict.actual, '-');
});

// ---------------------------------------------------------------- settlement

test('pays a winning bet at the struck odds', () => {
  const { results, points } = settleBets({
    userBets: { sezer: { bets: [{ type: 'winner', choice: aliasOf('Ivysaur'), wager: 100 }], wager: 100 } },
    // Balance is post-stake: 1000 starting, 100 already debited when placed.
    userPoints: { sezer: 900 },
    currentOdds: ODDS,
    matchResults: MATCH,
  });

  const user = results.users[0];
  assert.equal(user.payout, 150);
  assert.equal(user.old_points, 900);
  assert.equal(user.new_points, 1050);
  assert.equal(points.sezer, 1050);
});

test('a losing bet pays nothing and does not double-charge the stake', () => {
  const { results, points } = settleBets({
    userBets: { sezer: { bets: [{ type: 'winner', choice: aliasOf('Abra'), wager: 100 }], wager: 100 } },
    userPoints: { sezer: 900 },
    currentOdds: ODDS,
    matchResults: MATCH,
  });

  assert.equal(results.users[0].payout, 0);
  // Still 900 — the stake left the wallet at placement time, not here.
  assert.equal(points.sezer, 900);
  assert.equal(results.users[0].new_points, 900);
});

test('net movement equals payout minus wager', () => {
  const { results } = settleBets({
    userBets: {
      sezer: {
        bets: [
          { type: 'winner', choice: aliasOf('Ivysaur'), wager: 100 }, // +150
          { type: 'dodge_king', choice: aliasOf('Kadabra'), wager: 50 }, //  +55
          { type: 'first_hit', choice: aliasOf('Charmander'), wager: 20 }, // 0
        ],
        wager: 170,
      },
    },
    userPoints: { sezer: 830 },
    currentOdds: ODDS,
    matchResults: MATCH,
  });

  const user = results.users[0];
  assert.equal(user.payout, 205);
  assert.equal(user.new_points - user.old_points, user.payout);
  assert.equal(user.new_points - user.old_points - user.wager, 35, 'net profit for the round');
});

test('settles several bettors independently', () => {
  const { points } = settleBets({
    userBets: {
      sezer: { bets: [{ type: 'winner', choice: aliasOf('Ivysaur'), wager: 100 }], wager: 100 },
      deniz: { bets: [{ type: 'winner', choice: aliasOf('Abra'), wager: 100 }], wager: 100 },
    },
    userPoints: { sezer: 900, deniz: 400 },
    currentOdds: ODDS,
    matchResults: MATCH,
  });

  assert.equal(points.sezer, 1050);
  assert.equal(points.deniz, 400);
});

test('unpriced markets settle at the fallback rather than crashing', () => {
  const { results } = settleBets({
    userBets: { sezer: { bets: [{ type: 'winner', choice: aliasOf('Ivysaur'), wager: 100 }], wager: 100 } },
    userPoints: { sezer: 900 },
    currentOdds: {}, // odds table lost, e.g. the server restarted mid-round
    matchResults: MATCH,
  });
  assert.equal(results.users[0].bets[0].odds, 1.1);
  assert.equal(results.users[0].payout, 110);
});

test('a balance can never go negative', () => {
  const { points } = settleBets({
    userBets: { broke: { bets: [{ type: 'winner', choice: aliasOf('Abra'), wager: 10 }], wager: 10 } },
    userPoints: { broke: 0 },
    currentOdds: ODDS,
    matchResults: MATCH,
  });
  assert.equal(points.broke, 0);
});

test('does not mutate the balances it is handed', () => {
  const original = { sezer: 900 };
  settleBets({
    userBets: { sezer: { bets: [{ type: 'winner', choice: aliasOf('Ivysaur'), wager: 100 }], wager: 100 } },
    userPoints: original,
    currentOdds: ODDS,
    matchResults: MATCH,
  });
  assert.equal(original.sezer, 900, 'input should be treated as immutable');
});

test('a first-time bettor is seeded at the starting stake', () => {
  const { results } = settleBets({
    userBets: { newcomer: { bets: [{ type: 'winner', choice: aliasOf('Abra'), wager: 0 }], wager: 0 } },
    userPoints: {},
    currentOdds: ODDS,
    matchResults: MATCH,
  });
  assert.equal(results.users[0].old_points, 1000);
});

test('settles nothing when nobody bet', () => {
  const { results, points } = settleBets({
    userBets: {},
    userPoints: { sezer: 900 },
    currentOdds: ODDS,
    matchResults: MATCH,
  });
  assert.deepEqual(results.users, []);
  assert.equal(points.sezer, 900);
});

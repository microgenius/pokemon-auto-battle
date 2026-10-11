'use strict';

const { BET_TYPE_LABELS, STARTING_POINTS } = require('./config');

/**
 * Bet settlement.
 *
 * Pure functions over plain data: no sockets, no filesystem, no module state.
 * That is deliberate — this is the code that decides who gains and loses points,
 * so it is the code most worth being able to test directly.
 *
 * Stakes are debited when the bet is placed, not here. `payout` is therefore the
 * gross return, and net movement for the round is `payout - wager`.
 *
 * Fighters are identified by their roster-slot alias ("candidate1"), never by
 * name. Names change mid-match when a Pokemon evolves and differ in case between
 * sources, which is exactly the class of mismatch this file used to paper over
 * with lower() on every comparison.
 */

/**
 * Only reachable if a market is missing from the priced board, which validation
 * and calculateOdds between them should prevent. Deliberately far below a real
 * price (~5x on a five-way): if this ever pays out, something upstream is
 * broken and it should be obvious in the results rather than lucrative.
 */
const FALLBACK_ODDS = 1.1;

function alias(value) {
  return String(value || '');
}

function labelFor(betType) {
  return BET_TYPE_LABELS[betType] || betType;
}

/**
 * Whoever leads a stat at the end of the match. Ties resolve to the first entry
 * encountered, which mirrors the previous behaviour.
 */
function leaderBy(allStats, field) {
  let best = '';
  let bestValue = -1;
  for (const entry of allStats) {
    const value = entry[field] || 0;
    if (value > bestValue) {
      bestValue = value;
      best = entry.alias;
    }
  }
  return best;
}

/**
 * Derives every market's outcome from the host's end-of-match report.
 */
function resolveOutcomes(matchResults, fallbacks = {}) {
  const allStats = Array.isArray(matchResults.all_stats) ? matchResults.all_stats : [];
  const winner = matchResults.winner || '';

  return {
    winner,
    first_blood: matchResults.first_blood || fallbacks.firstBlood || '',
    first_hit: matchResults.first_hit || fallbacks.firstHit || '',
    kill_king: leaderBy(allStats, 'kills'),
    dodge_king: leaderBy(allStats, 'dodges'),
    crit_king: leaderBy(allStats, 'criticals'),
    // Everyone who died still short of their final form.
    //
    // This replaces a market that asked whether a fighter had evolved *at all*.
    // That one did settle correctly, but passive XP evolves nearly everyone
    // within seconds, so it almost never paid. Asking whether they finished the
    // line instead is a far more common — and more guessable — outcome.
    //
    // A fighter with no evolution left is complete by definition, so a species
    // that cannot evolve can never satisfy this market. calculateOdds refuses to
    // price those, and the client hides them from the tab.
    incomplete_evolution: allStats
      .filter((s) => !s.evolution_complete && alias(s.alias) !== alias(winner))
      .map((s) => s.alias),
  };
}

/**
 * Decides a single bet against the resolved outcomes.
 * @returns {{won: boolean, actual: string}}
 */
function judgeBet(bet, outcomes, displayNames = {}) {
  const choice = alias(bet.choice);
  const shown = (key) => displayNames[key] || key || '-';

  if (bet.type === 'incomplete_evolution') {
    const won = outcomes.incomplete_evolution.some((a) => alias(a) === choice);
    return { won, actual: won ? shown(choice) : 'Evrimini tamamladı / Ölmedi' };
  }

  const actual = outcomes[bet.type];
  if (actual === undefined) {
    return { won: false, actual: '-' };
  }
  return { won: alias(actual) === choice, actual: shown(actual) };
}

/**
 * alias -> display name, so the results screen can show "Ivysaur" for a bet
 * struck on "candidate1" back when it was still a Bulbasaur.
 */
function displayNamesFrom(matchResults) {
  const names = {};
  for (const entry of Array.isArray(matchResults.all_stats) ? matchResults.all_stats : []) {
    if (entry && entry.alias) names[entry.alias] = entry.name || entry.alias;
  }
  return names;
}

/**
 * Settles every open bet and returns both the per-user breakdown and the wallet
 * balances that result. Does not mutate its inputs.
 *
 * @param {object} params
 * @param {object} params.userBets     username -> { bets: [...], wager }
 * @param {object} params.userPoints   username -> balance (stakes already debited)
 * @param {object} params.currentOdds  odds key -> decimal odds
 * @param {object} params.matchResults MATCH_RESULTS payload from the host
 * @param {object} [params.fallbacks]  { firstBlood, firstHit } from live events
 * @returns {{results: {users: Array}, points: object}}
 */
function settleBets({ userBets, userPoints, currentOdds, matchResults, fallbacks = {} }) {
  const outcomes = resolveOutcomes(matchResults, fallbacks);
  const displayNames = displayNamesFrom(matchResults);
  const points = { ...userPoints };
  const users = [];

  for (const [username, betData] of Object.entries(userBets)) {
    const openingBalance = points[username] !== undefined ? points[username] : STARTING_POINTS;
    const bets = Array.isArray(betData.bets) ? betData.bets : [];

    let totalPayout = 0;
    const breakdown = [];

    for (const bet of bets) {
      const odds = currentOdds[`${bet.type}_${alias(bet.choice)}`] || FALLBACK_ODDS;
      const { won, actual } = judgeBet(bet, outcomes, displayNames);
      const payout = won ? Math.round(bet.wager * odds) : 0;
      totalPayout += payout;

      breakdown.push({
        type: labelFor(bet.type),
        // The name the fighter ended the match under, not the opaque alias.
        choice: displayNames[bet.choice] || bet.choice,
        actual,
        odds,
        wager: bet.wager,
        payout,
        won,
      });
    }

    points[username] = Math.max(0, openingBalance + totalPayout);

    users.push({
      username,
      old_points: openingBalance,
      new_points: points[username],
      bets: breakdown,
      wager: betData.wager || 0,
      payout: totalPayout,
      all_won: totalPayout > (betData.wager || 0),
    });
  }

  return { results: { users }, points };
}

module.exports = {
  settleBets,
  resolveOutcomes,
  judgeBet,
  leaderBy,
  displayNamesFrom,
};

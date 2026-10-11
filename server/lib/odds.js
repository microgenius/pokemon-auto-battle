'use strict';

const { ODDS_PAYBACK, MIN_ODDS, MAX_ODDS } = require('./config');

/**
 * Odds pricing.
 *
 * Every price here is `payback / probability`. That sounds obvious, but the
 * model this replaces never did it: it pinned the favourite at 1.05x and
 * scaled everyone else *away* from the favourite by a fixed spread, using the
 * probability only to decide the ordering. On the default five-fighter roster
 * that priced a genuine 20% shot at 1.05x, so a 100 CP stake returned 21 CP in
 * expectation — a 79% house edge on every market. Nobody could win over a
 * season, which is exactly how it felt to play.
 *
 * Six of the seven markets pick exactly one fighter, so their probabilities sum
 * to 1 across the roster and a fair price is 1/p — around 5x on a five-way
 * board. incomplete_evolution is not exclusive (several fighters can satisfy it)
 * and is priced from its own probability below.
 *
 * ODDS_PAYBACK is the fraction of turnover returned in expectation. Above 1.0
 * the room drifts up, which is deliberate here: this is a game among friends,
 * not a book that needs to profit.
 *
 * These probabilities are still heuristics over base stats rather than measured
 * win rates — a Monte Carlo pass over the real simulation would do better. The
 * point of this change is that the arithmetic between probability and price is
 * now correct, so improving the probabilities improves the prices directly.
 *
 * Keys are `${betType}_${alias}`, where the alias is the fighter's roster slot
 * ("candidate1"). It does not change when a Pokemon evolves, so there is no
 * remapping step and no case folding — both of which this module used to need.
 */

/**
 * Per-market probability model.
 *
 * `weight` names the stat blend that drives the market. `sharpness` is the
 * exponent applied before normalising: 1 makes probability proportional to the
 * weight, higher values concentrate probability on the leader. Base stat totals
 * across a typical roster differ by only a few percent, so without an exponent
 * every fighter prices identically and the board is boring.
 */
const MARKETS = {
  winner: { weight: 'power', sharpness: 2.0 },
  first_blood: { weight: 'strike', sharpness: 1.5 },
  first_hit: { weight: 'initiative', sharpness: 1.5 },
  kill_king: { weight: 'sustain', sharpness: 1.5 },
  dodge_king: { weight: 'speed', sharpness: 2.0 },
  crit_king: { weight: 'endurance', sharpness: 1.5 },
};

const DEFAULT_STAT = 50;

/**
 * Rough chance a fighter clears one more evolution step before the match ends.
 *
 * Passive XP makes the first step near-certain and each further one less so, but
 * a single per-step figure is honest enough for a heuristic — the point is that
 * a fighter two steps from its final form is much likelier to fall short than
 * one that is a single step away.
 */
const EVOLUTION_STEP_CHANCE = 0.55;

function round2(value) {
  return Math.round(value * 100) / 100;
}

function clamp(value, low, high) {
  return Math.min(high, Math.max(low, value));
}

function stat(option, key) {
  const value = option[key];
  return Number.isFinite(value) ? value : DEFAULT_STAT;
}

/**
 * The stat blends each market draws on.
 *
 * Each market gets its own blend rather than sharing one. Two markets on the
 * same blend price identically, which is both wrong — landing the first kill
 * and topping the kill count reward different builds — and dull, since half the
 * board would show the same number twice.
 */
function weightsFor(option) {
  const hp = stat(option, 'base_hp');
  const atk = stat(option, 'base_atk');
  const def = stat(option, 'base_def');
  const spAtk = stat(option, 'base_sp_atk');
  const spDef = stat(option, 'base_sp_def');
  const spd = stat(option, 'base_spd');

  const offence = atk + spAtk;
  const bulk = hp + def + spDef;

  return {
    // Winning the match: every stat contributes.
    power: offence + bulk + spd,
    // First blood is damage-led: you need burst to convert a hit into a kill,
    // with pace as a secondary factor.
    strike: offence + spd / 2,
    // First hit is mostly about acting first.
    initiative: spd * 1.5 + atk,
    // Kill count rewards damage plus living long enough to keep swinging.
    sustain: offence + bulk / 3,
    // Dodging is pure speed.
    speed: spd,
    // A crit is a Sharp Eye shot, and Sharp Eye is a flat roll on every aimed
    // shot — the same odds for everyone. So crit count tracks how many shots a
    // fighter gets to take, which is how long it stays alive. Bulk, not speed:
    // speed already decides dodging and this market is not a second copy of it.
    endurance: bulk + offence / 4,
  };
}

/**
 * Turns raw weights into probabilities that sum to 1.
 *
 * Falls back to an even split when every weight is zero, so a roster of blanks
 * prices at 1/N rather than dividing by zero.
 */
function normalise(weights, sharpness) {
  const raised = weights.map((w) => Math.pow(Math.max(0, w), sharpness));
  const total = raised.reduce((sum, w) => sum + w, 0);
  if (total <= 0) return weights.map(() => 1 / Math.max(1, weights.length));
  return raised.map((w) => w / total);
}

/** The whole pricing rule. */
function priceFor(probability) {
  if (!(probability > 0)) return MAX_ODDS;
  return round2(clamp(ODDS_PAYBACK / probability, MIN_ODDS, MAX_ODDS));
}

/**
 * Probability a fighter dies short of its final form.
 *
 * Unlike the other six this market is not exclusive — every fighter that falls
 * short settles as a winner — so its probability is far higher and its price
 * far shorter. That is the point of the market: frequent, guessable, modest
 * wins rather than a one-in-five shot.
 *
 * A fighter has to both lose the match and fail to finish its evolution line.
 * Returns 0 when there is nothing left to evolve into, which makes the outcome
 * impossible — calculateOdds leaves those unpriced rather than advertising a
 * long price on something that can never happen.
 */
function incompleteEvolutionProbability(winProbability, stepsRemaining) {
  if (stepsRemaining <= 0) return 0;
  const completesLine = Math.pow(EVOLUTION_STEP_CHANCE, stepsRemaining);
  return (1 - winProbability) * (1 - completesLine);
}

/** How many evolutions this form still has ahead of it. */
function stepsRemaining(option) {
  const stage = Number.isFinite(option.stage) ? option.stage : 1;
  const maxStages = Number.isFinite(option.max_stages) ? option.max_stages : 1;
  return Math.max(0, maxStages - stage);
}

/**
 * @param {Array<object>} options roster entries broadcast in LOBBY_UPDATE
 * @returns {Record<string, number>} `${betType}_${lowercaseName}` -> decimal odds
 */
function calculateOdds(options) {
  const odds = {};
  if (!Array.isArray(options) || options.length === 0) return odds;

  const entries = options.map((option) => ({
    key: String(option.alias || ''),
    stepsRemaining: stepsRemaining(option),
    weights: weightsFor(option),
  }));

  const probabilities = {};
  for (const [market, model] of Object.entries(MARKETS)) {
    probabilities[market] = normalise(
      entries.map((e) => e.weights[model.weight]),
      model.sharpness
    );
  }

  entries.forEach((entry, i) => {
    for (const market of Object.keys(MARKETS)) {
      odds[`${market}_${entry.key}`] = priceFor(probabilities[market][i]);
    }

    const incomplete = incompleteEvolutionProbability(
      probabilities.winner[i],
      entry.stepsRemaining
    );
    // Left unpriced when impossible, so the client can hide a bet nobody could
    // ever win rather than showing it at the long-shot cap.
    if (incomplete > 0) {
      odds[`incomplete_evolution_${entry.key}`] = priceFor(incomplete);
    }
  });

  return odds;
}

module.exports = {
  calculateOdds,
  priceFor,
  normalise,
  MARKETS,
  MIN_ODDS,
  MAX_ODDS,
};

'use strict';

const {
  HEAL_TIERS,
  HEAL_MIN_COST,
  HEAL_COOLDOWN_MS,
  HEAL_MATCH_CAP,
} = require('./config');

/**
 * Paid healing: what it costs, and whether it is allowed.
 *
 * Pure functions over plain data — no sockets, no wallets — because this decides
 * who loses points and is worth testing directly.
 *
 * ## The price is the money already on that fighter
 *
 * A heal costs a multiple of everything staked on its target, across every
 * spectator and every market. Back Charmander with 150 CP and a full heal on
 * Charmander costs about 150 CP; a fighter nobody fancies is cheap to prop up,
 * and one carrying the room's money is expensive. The price therefore scales
 * with the economy on its own — no figure to re-tune when wallets grow.
 *
 * It also does most of the work against self-dealing. Healing a fighter you
 * have money on buys a better outcome on a bet you already hold, and that edge
 * is `stake x (p_after - p_before) / p_before` — proportional to the stake, so
 * only a price that is also proportional to the stake can track it. Measured
 * across realistic board positions the edge runs 0.24x to 1.27x the stake, so a
 * 1.0x multiplier covers the cheaper half of that band and HEAL_MATCH_CAP is the
 * backstop for the rest. Raise HEAL_TIERS[].stakeMultiplier above ~1.3 to close
 * it completely, at the cost of making healing rare.
 *
 * The cooldown is global, not per spectator: it paces the match, and a room of
 * ten people should not be able to heal ten times as often as a room of one.
 */

function tierById(id) {
  return HEAL_TIERS.find((t) => t.id === id) || null;
}

/** Everything staked on `alias` right now, by everyone, across every market. */
function stakeOn(userBets, alias) {
  let total = 0;
  for (const entry of Object.values(userBets || {})) {
    for (const bet of (entry && entry.bets) || []) {
      if (bet.choice === alias) total += bet.wager || 0;
    }
  }
  return total;
}

/** What one heal on this fighter costs, given the money riding on it. */
function healCost(tierId, stake = 0) {
  const tier = tierById(tierId);
  if (!tier) return null;
  return Math.max(HEAL_MIN_COST, Math.round(Math.max(0, stake) * tier.stakeMultiplier));
}

/**
 * Every rule that can refuse a heal, in one place.
 *
 * `now` and `lastHealAt` are injected so the cooldown can be tested without
 * sleeping. `lastHealAt` is a single room-wide timestamp.
 *
 * @returns {{ok: true, tier, cost, amount, fraction}|{ok: false, reason, cooldownLeftMs?}}
 */
function authorizeHeal({
  tierId,
  alias,
  roster,
  status,
  balance,
  stake = 0,
  lastHealAt = 0,
  healedThisMatch = 0,
  targetMaxHp = 0,
  targetAlive = true,
  now = Date.now(),
}) {
  if (status !== 'BATTLING') {
    return { ok: false, reason: 'Şifa sadece savaş sırasında verilebilir.' };
  }

  const tier = tierById(tierId);
  if (!tier) return { ok: false, reason: 'Geçersiz şifa paketi.' };

  const known = Array.isArray(roster) && roster.some((o) => o && o.alias === alias);
  if (!known) return { ok: false, reason: 'Böyle bir dövüşçü yok.' };

  if (!targetAlive) return { ok: false, reason: 'Bu dövüşçü hayatta değil.' };

  const waited = now - lastHealAt;
  if (lastHealAt > 0 && waited < HEAL_COOLDOWN_MS) {
    const left = HEAL_COOLDOWN_MS - waited;
    return {
      ok: false,
      reason: `Şifa bekleme süresi: ${Math.ceil(left / 1000)} sn.`,
      cooldownLeftMs: left,
    };
  }

  // A fighter must not be kept alive on subscription. This is also the backstop
  // on the self-dealing the price only partly covers.
  if (healedThisMatch >= HEAL_MATCH_CAP) {
    return { ok: false, reason: 'Bu dövüşçü bu maçta yeterince şifa aldı.' };
  }

  const cost = healCost(tierId, stake);
  if (balance < cost) {
    return { ok: false, reason: `Yetersiz bakiye: ${cost} CP gerekiyor.` };
  }

  // Never overshoot the cap, so the last heal of a match is priced for what it
  // actually delivers rather than what was asked for.
  const fraction = Math.min(tier.fraction, HEAL_MATCH_CAP - healedThisMatch);

  return { ok: true, tier, cost, amount: Math.round(targetMaxHp * fraction), fraction };
}

/**
 * Per-fighter heal availability for the spectator UI, so the page can grey a
 * button out and say why instead of letting people click into a rejection.
 */
function healStateFor({ roster, userBets, status, balance, lastHealAt, healedThisMatch, liveStats, now = Date.now() }) {
  const fighters = {};

  for (const option of Array.isArray(roster) ? roster : []) {
    if (!option || !option.alias) continue;
    const alias = option.alias;
    const stats = (liveStats || {})[alias];

    fighters[alias] = {};
    for (const tier of HEAL_TIERS) {
      const verdict = authorizeHeal({
        tierId: tier.id,
        alias,
        roster,
        status,
        balance,
        stake: stakeOn(userBets, alias),
        lastHealAt,
        healedThisMatch: (healedThisMatch || {})[alias] || 0,
        targetMaxHp: stats ? stats.max_hp : 0,
        targetAlive: stats ? Number(stats.hp) > 0 : false,
        now,
      });

      fighters[alias][tier.id] = {
        cost: healCost(tier.id, stakeOn(userBets, alias)),
        ok: verdict.ok === true,
        reason: verdict.ok ? '' : verdict.reason,
      };
    }
  }

  const waited = now - (lastHealAt || 0);
  return {
    fighters,
    cooldownLeftMs: lastHealAt > 0 ? Math.max(0, HEAL_COOLDOWN_MS - waited) : 0,
  };
}

module.exports = { authorizeHeal, healCost, stakeOn, healStateFor, tierById };

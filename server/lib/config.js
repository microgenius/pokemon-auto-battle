'use strict';

/**
 * All tunables in one place, overridable from the environment so the server can
 * be pointed at a different port or economy without editing source.
 */

function intFromEnv(name, fallback) {
  const raw = process.env[name];
  if (raw === undefined || raw === '') return fallback;
  const parsed = Number.parseInt(raw, 10);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function floatFromEnv(name, fallback) {
  const raw = process.env[name];
  if (raw === undefined || raw === '') return fallback;
  const parsed = Number.parseFloat(raw);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function stringFromEnv(name, fallback) {
  const raw = process.env[name];
  return raw === undefined || raw === '' ? fallback : raw;
}

module.exports = {
  PORT: intFromEnv('PORT', 3000),

  /**
   * Shared secret the Godot host must present as `?token=` alongside
   * `role=host`. Empty means "unset": host connections are then only accepted
   * from this machine. See lib/auth.js.
   */
  HOST_TOKEN: stringFromEnv('AUTOBATTLE_HOST_TOKEN', ''),

  /** Largest WebSocket frame accepted, in bytes. A bet slip is a few hundred. */
  MAX_PAYLOAD_BYTES: intFromEnv('AUTOBATTLE_MAX_PAYLOAD', 64 * 1024),

  /** Spectator message budget: burst size, then sustained messages per second. */
  RATE_LIMIT_BURST: intFromEnv('AUTOBATTLE_RATE_LIMIT_BURST', 20),
  RATE_LIMIT_PER_SECOND: intFromEnv('AUTOBATTLE_RATE_LIMIT_PER_SECOND', 10),

  /** Wallet balance handed to a username the first time it is seen. */
  STARTING_POINTS: intFromEnv('AUTOBATTLE_STARTING_POINTS', 1000),

  /** Bonus granted once per lobby to everyone connected. */
  MATCH_BONUS: intFromEnv('AUTOBATTLE_MATCH_BONUS', 10),

  /**
   * Fraction of turnover paid back in expectation, i.e. odds = PAYBACK / p.
   *
   * 1.0 is a fair book: the price matches the probability, so a bettor's
   * balance moves on variance alone and the board never lies about the odds.
   * The steady upward drift people feel comes from MATCH_BONUS instead —
   * showing up is what pays, which is the intended incentive.
   *
   * Raise it to make the odds themselves generous; over 40 matches at 10 CP
   * across six markets, 1.0 leaves ~90% of bettors ahead and 1.08 ~96%. Below
   * 1.0 takes a house cut.
   */
  ODDS_PAYBACK: floatFromEnv('AUTOBATTLE_ODDS_PAYBACK', 1.0),

  /** A heavy favourite still has to pay something for the risk. */
  MIN_ODDS: floatFromEnv('AUTOBATTLE_MIN_ODDS', 1.1),

  /** Ceiling so a rounding artefact on a tiny probability cannot print points. */
  MAX_ODDS: floatFromEnv('AUTOBATTLE_MAX_ODDS', 15),

  /**
   * Paid healing.
   *
   * The price is not a fixed number — it is a multiple of everything staked on
   * the fighter being healed, so it tracks the betting economy by itself. A full
   * heal on a fighter carrying 150 CP of the room's money costs about 150 CP; a
   * fighter nobody backed costs the floor. See lib/healing for why a price that
   * scales with the stake is also what keeps healing your own pick honest.
   */
  HEAL_TIERS: [
    { id: 'small', label: 'Küçük Şifa', stakeMultiplier: floatFromEnv('AUTOBATTLE_HEAL_SMALL_MULTIPLIER', 0.4), fraction: 0.10 },
    { id: 'large', label: 'Büyük Şifa', stakeMultiplier: floatFromEnv('AUTOBATTLE_HEAL_LARGE_MULTIPLIER', 1.0), fraction: 0.30 },
  ],

  /** Floor, so a fighter nobody has bet on is not free to prop up. */
  HEAL_MIN_COST: intFromEnv('AUTOBATTLE_HEAL_MIN_COST', 25),

  /**
   * Wait between heals, in milliseconds — room-wide, not per spectator. Ten
   * people should not be able to heal ten times as often as one.
   */
  HEAL_COOLDOWN_MS: intFromEnv('AUTOBATTLE_HEAL_COOLDOWN_MS', 30000),

  /** Total healing one fighter may receive in a match, as a fraction of max HP. */
  HEAL_MATCH_CAP: floatFromEnv('AUTOBATTLE_HEAL_MATCH_CAP', 0.6),

  /** Every market the client is allowed to bet on. */
  BET_TYPES: [
    'winner',
    'first_blood',
    'first_hit',
    'kill_king',
    'dodge_king',
    'crit_king',
    'incomplete_evolution',
  ],

  /** Turkish display names, used in settlement summaries. */
  BET_TYPE_LABELS: {
    winner: 'Kazanan',
    first_blood: 'İlk Kan',
    first_hit: 'İlk Vuruş',
    kill_king: 'Kill Kralı',
    dodge_king: 'Dodge Kralı',
    crit_king: 'Kritik Kralı',
    incomplete_evolution: 'Evrimini Tamamlayamadan Ölür',
  },
};

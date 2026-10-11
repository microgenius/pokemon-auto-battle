'use strict';

const { STARTING_POINTS } = require('./config');
const { transact } = require('./db');

/**
 * Persistent CP balances, one row per user in the shared `users` table.
 *
 * The JSON implementation this replaces had to hand-roll durability: an atomic
 * temp+rename on every change, a 250ms debounce so a burst of bets did not
 * rewrite the file six times, a corrupt-file quarantine path, and a flush() on
 * shutdown so nothing debounced was lost. A committed transaction is already
 * durable, so all of that is gone.
 *
 * Lookups are by lowercased username. `snapshot()` keys by the display name,
 * because that is what settlement and the results screen compare against.
 */
class WalletStore {
  constructor(db) {
    this.db = db;
    this._get = db.prepare('SELECT display_name, balance FROM users WHERE username = ?');
    this._insert = db.prepare(
      'INSERT INTO users (username, display_name, balance) VALUES (?, ?, ?)'
    );
    this._update = db.prepare(
      "UPDATE users SET balance = ?, updated_at = datetime('now') WHERE username = ?"
    );
    this._upsert = db.prepare(`
      INSERT INTO users (username, display_name, balance) VALUES (?, ?, ?)
      ON CONFLICT(username) DO UPDATE SET
        balance = excluded.balance,
        updated_at = datetime('now')
    `);
    this._all = db.prepare('SELECT display_name, balance FROM users');
  }

  /** Balance for a user, creating the row at the starting stake if new. */
  get(username) {
    const key = String(username).toLowerCase();
    const row = this._get.get(key);
    if (row) return row.balance;

    this._insert.run(key, String(username), STARTING_POINTS);
    return STARTING_POINTS;
  }

  has(username) {
    return this._get.get(String(username).toLowerCase()) !== undefined;
  }

  set(username, value) {
    const key = String(username).toLowerCase();
    const balance = Math.max(0, Math.round(value));

    if (this._get.get(key)) {
      this._update.run(balance, key);
    } else {
      this._insert.run(key, String(username), balance);
    }
    return balance;
  }

  add(username, delta) {
    return this.set(username, this.get(username) + delta);
  }

  /**
   * Bulk balance write, used after settlement recomputes everyone at once.
   *
   * Upserts rather than replacing the table: the JSON version dropped any user
   * missing from the incoming map, which with a shared row would now discard
   * their device token — and their claim on their own username — as a side
   * effect of a settlement that simply did not mention them.
   */
  replaceAll(balances) {
    transact(this.db, () => {
      for (const [username, value] of Object.entries(balances)) {
        this._upsert.run(
          String(username).toLowerCase(),
          String(username),
          Math.max(0, Math.round(value))
        );
      }
    });
  }

  /** Every balance, keyed by display name. */
  snapshot() {
    const out = {};
    for (const row of this._all.all()) out[row.display_name] = row.balance;
    return out;
  }

  /**
   * Kept so the shutdown handler still has something to call. Committed data is
   * already on disk; this only folds the WAL back into the main file so the
   * database is a single tidy file when the server is not running.
   */
  flush() {
    try {
      this.db.exec('PRAGMA wal_checkpoint(TRUNCATE)');
    } catch (err) {
      console.error('[wallets] checkpoint failed:', err.message);
    }
  }
}

module.exports = { WalletStore };

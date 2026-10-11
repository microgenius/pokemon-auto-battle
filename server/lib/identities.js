'use strict';

const { STARTING_POINTS } = require('./config');
const { newToken, safeEqual } = require('./auth');

/**
 * Binds a username to the browser that first claimed it.
 *
 * JOIN used to accept any username and hand over that name's wallet, so typing
 * someone else's name was enough to spend their points. Now the first claim
 * mints a random token that the browser keeps in localStorage and replays on
 * every later JOIN; a claim for a known name without the matching token is
 * refused.
 *
 * This is deliberately not a password system. It stops casual impersonation
 * between teammates, which is the actual threat here — it does not survive a
 * cleared localStorage (the name has to be released) or someone reading the
 * token off another person's machine.
 *
 * Shares the `users` row with WalletStore, so a claim and a balance can never
 * disagree about who a name belongs to.
 */
class IdentityStore {
  constructor(db) {
    this.db = db;
    this._get = db.prepare('SELECT display_name, device_token FROM users WHERE username = ?');
    this._insert = db.prepare(
      'INSERT INTO users (username, display_name, balance, device_token) VALUES (?, ?, ?, ?)'
    );
    this._claimExisting = db.prepare(
      "UPDATE users SET device_token = ?, updated_at = datetime('now') WHERE username = ?"
    );
    this._release = db.prepare(
      "UPDATE users SET device_token = NULL, updated_at = datetime('now') WHERE username = ?"
    );
  }

  /** True when the name has an owner. A row with no token is unclaimed. */
  has(username) {
    const row = this._get.get(String(username).toLowerCase());
    return row !== undefined && row.device_token !== null;
  }

  /**
   * Attempts to take `username`.
   *
   * Returns `{ ok: true, token, username }` where `username` is the canonical
   * spelling on record — callers should use it instead of what was typed, so a
   * differently-cased login cannot fork a wallet from its identity. Returns
   * `{ ok: false }` when the name belongs to someone else.
   */
  claim(username, presentedToken) {
    const key = String(username).toLowerCase();
    const row = this._get.get(key);

    if (row === undefined) {
      const token = newToken();
      this._insert.run(key, String(username), STARTING_POINTS, token);
      return { ok: true, token, username: String(username), issued: true };
    }

    // A wallet migrated from the JSON era has a balance but no token yet; the
    // first person to log in with that name adopts it.
    if (row.device_token === null) {
      const token = newToken();
      this._claimExisting.run(token, key);
      return { ok: true, token, username: row.display_name, issued: true };
    }

    if (safeEqual(presentedToken, row.device_token)) {
      return { ok: true, token: row.device_token, username: row.display_name, issued: false };
    }

    return { ok: false };
  }

  /** Drops a claim so the name can be taken again. Leaves the balance alone. */
  release(username) {
    this._release.run(String(username).toLowerCase());
  }
}

module.exports = { IdentityStore };

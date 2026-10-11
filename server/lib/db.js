'use strict';

const fs = require('fs');
const path = require('path');
const { DatabaseSync } = require('node:sqlite');

/**
 * The single SQLite handle every store shares.
 *
 * Replaces the pair of JSON files this used to keep (points.json and
 * identities.json). Those were rewritten in full on every change, which meant
 * the atomic temp+rename dance, a debounce to avoid rewriting six times a
 * second, and a corrupt-file recovery path — all of it hand-rolled durability
 * that a database gives for free.
 *
 * node:sqlite is used rather than a driver from npm: the API is synchronous,
 * which is what the callers already expect, and it keeps the dependency list at
 * express + ws. It is still flagged experimental, so `npm start` passes
 * --disable-warning=ExperimentalWarning; if that guarantee ever matters more
 * than the dependency count, better-sqlite3 is a drop-in for the small surface
 * used here (prepare/run/get/all/exec).
 *
 * Wallets and identities share one `users` row. They used to be keyed
 * differently — balances by the name as typed, tokens by its lowercased form —
 * so "Sezer" and "sezer" were one identity but two wallets. The primary key is
 * now the lowercased name for both, with the typed spelling kept alongside for
 * display.
 */

const SCHEMA = `
  CREATE TABLE IF NOT EXISTS users (
    username     TEXT    PRIMARY KEY,
    display_name TEXT    NOT NULL,
    balance      INTEGER NOT NULL DEFAULT 0 CHECK (balance >= 0),
    device_token TEXT,
    created_at   TEXT    NOT NULL DEFAULT (datetime('now')),
    updated_at   TEXT    NOT NULL DEFAULT (datetime('now'))
  );
`;

function openDatabase(filePath) {
  if (filePath !== ':memory:') {
    fs.mkdirSync(path.dirname(filePath), { recursive: true });
  }

  const db = new DatabaseSync(filePath);
  // WAL keeps a reader (a settlement snapshot) from blocking a writer (a bet
  // landing), which is the whole access pattern here.
  db.exec('PRAGMA journal_mode = WAL');
  db.exec('PRAGMA busy_timeout = 5000');
  db.exec('PRAGMA foreign_keys = ON');
  db.exec(SCHEMA);
  return db;
}

/** Runs `fn` inside a transaction, rolling back if it throws. */
function transact(db, fn) {
  db.exec('BEGIN');
  try {
    const result = fn();
    db.exec('COMMIT');
    return result;
  } catch (err) {
    db.exec('ROLLBACK');
    throw err;
  }
}

function readJsonIfPresent(filePath, label) {
  if (!filePath || !fs.existsSync(filePath)) return null;
  try {
    const parsed = JSON.parse(fs.readFileSync(filePath, 'utf8'));
    return parsed && typeof parsed === 'object' ? parsed : null;
  } catch (err) {
    console.error(`[db] could not read legacy ${label} at ${filePath}:`, err.message);
    return null;
  }
}

/**
 * One-shot import of the old JSON files.
 *
 * Only runs when the table is empty, so it cannot clobber live data on a later
 * boot. The files are renamed to *.migrated afterwards rather than deleted —
 * these are people's balances, and a rename is reversible.
 *
 * Returns the number of users imported.
 */
function importLegacyJson(db, { pointsPath, identitiesPath } = {}) {
  const existing = db.prepare('SELECT COUNT(*) AS n FROM users').get();
  if (existing.n > 0) return 0;

  const balances = readJsonIfPresent(pointsPath, 'points.json');
  const tokens = readJsonIfPresent(identitiesPath, 'identities.json');
  if (!balances && !tokens) return 0;

  // Both files keyed by name; balances kept the typed casing, tokens the
  // lowercased one. Collapse onto the lowercased key.
  const merged = new Map();
  const pick = (name) => {
    const key = String(name).toLowerCase();
    if (!merged.has(key)) merged.set(key, { displayName: String(name), balance: null, token: null });
    return merged.get(key);
  };

  for (const [name, balance] of Object.entries(balances || {})) {
    const row = pick(name);
    const value = Number.parseInt(balance, 10);
    if (!Number.isFinite(value)) continue;
    if (row.balance === null) {
      row.balance = Math.max(0, value);
      row.displayName = String(name);
    } else {
      // Two spellings of one name each had a wallet. Keeping the larger is the
      // choice that cannot silently take points away from somebody.
      console.warn(
        `[db] legacy wallets collided on "${row.displayName}" / "${name}" — keeping the larger balance`
      );
      row.balance = Math.max(row.balance, Math.max(0, value));
    }
  }

  for (const [name, token] of Object.entries(tokens || {})) {
    const row = pick(name);
    row.token = String(token);
  }

  const insert = db.prepare(
    'INSERT INTO users (username, display_name, balance, device_token) VALUES (?, ?, ?, ?)'
  );

  transact(db, () => {
    for (const [key, row] of merged) {
      insert.run(key, row.displayName, row.balance === null ? 0 : row.balance, row.token);
    }
  });

  for (const [filePath, label] of [[pointsPath, 'points.json'], [identitiesPath, 'identities.json']]) {
    if (filePath && fs.existsSync(filePath)) {
      try {
        fs.renameSync(filePath, `${filePath}.migrated`);
      } catch (err) {
        console.error(`[db] imported ${label} but could not rename it:`, err.message);
      }
    }
  }

  console.log(`[db] imported ${merged.size} user(s) from the legacy JSON files`);
  return merged.size;
}

module.exports = { openDatabase, importLegacyJson, transact, SCHEMA };

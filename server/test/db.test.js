'use strict';

const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');

const { openDatabase, importLegacyJson, transact } = require('../lib/db');
const { WalletStore } = require('../lib/wallets');
const { IdentityStore } = require('../lib/identities');

function tempDir() {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'autobattle-migrate-'));
}

function legacyFiles(dir, points, identities) {
  const pointsPath = path.join(dir, 'points.json');
  const identitiesPath = path.join(dir, 'identities.json');
  if (points) fs.writeFileSync(pointsPath, JSON.stringify(points));
  if (identities) fs.writeFileSync(identitiesPath, JSON.stringify(identities));
  return { pointsPath, identitiesPath };
}

test('the schema is created on first open', () => {
  const db = openDatabase(':memory:');
  const columns = db.prepare('PRAGMA table_info(users)').all().map((c) => c.name);
  assert.deepStrictEqual(columns.sort(), [
    'balance', 'created_at', 'device_token', 'display_name', 'updated_at', 'username',
  ]);
});

test('balances cannot be stored negative', () => {
  const db = openDatabase(':memory:');
  assert.throws(() =>
    db.prepare('INSERT INTO users (username, display_name, balance) VALUES (?, ?, ?)')
      .run('x', 'x', -1));
});

test('transact rolls back everything when the body throws', () => {
  const db = openDatabase(':memory:');
  const insert = db.prepare('INSERT INTO users (username, display_name, balance) VALUES (?, ?, ?)');

  assert.throws(() => transact(db, () => {
    insert.run('a', 'a', 10);
    throw new Error('boom');
  }));

  assert.strictEqual(db.prepare('SELECT COUNT(*) AS n FROM users').get().n, 0);
});

test('legacy balances and tokens are imported and joined onto one row', () => {
  const dir = tempDir();
  const files = legacyFiles(dir, { Sezer: 42, ali: 100 }, { sezer: 'tok-sezer' });
  const db = openDatabase(path.join(dir, 'game.db'));

  assert.strictEqual(importLegacyJson(db, files), 2);

  const wallets = new WalletStore(db);
  const identities = new IdentityStore(db);

  assert.strictEqual(wallets.get('sezer'), 42);
  assert.strictEqual(wallets.get('ali'), 100);
  // The balance file's spelling is what shows up.
  assert.deepStrictEqual(wallets.snapshot(), { Sezer: 42, ali: 100 });
  // And the token from the other file landed on the same row.
  assert.ok(identities.claim('sezer', 'tok-sezer').ok);
  assert.strictEqual(identities.has('ali'), false, 'no token means unclaimed');
});

test('imported files are renamed, not deleted', () => {
  const dir = tempDir();
  const files = legacyFiles(dir, { sezer: 42 }, { sezer: 'tok' });
  const db = openDatabase(path.join(dir, 'game.db'));

  importLegacyJson(db, files);

  assert.strictEqual(fs.existsSync(files.pointsPath), false);
  assert.strictEqual(fs.existsSync(`${files.pointsPath}.migrated`), true);
  assert.strictEqual(fs.existsSync(`${files.identitiesPath}.migrated`), true);
});

test('import is a no-op once the table has rows', () => {
  const dir = tempDir();
  const files = legacyFiles(dir, { sezer: 42 }, null);
  const db = openDatabase(path.join(dir, 'game.db'));

  const wallets = new WalletStore(db);
  wallets.set('sezer', 999);

  assert.strictEqual(importLegacyJson(db, files), 0);
  assert.strictEqual(wallets.get('sezer'), 999, 'live data must win over a stale file');
});

test('two spellings of one name collapse to the larger balance', () => {
  const dir = tempDir();
  const files = legacyFiles(dir, { Sezer: 42, sezer: 900 }, null);
  const db = openDatabase(path.join(dir, 'game.db'));

  assert.strictEqual(importLegacyJson(db, files), 1);
  assert.strictEqual(new WalletStore(db).get('SEZER'), 900);
});

test('a corrupt legacy file is skipped rather than fatal', () => {
  const dir = tempDir();
  const pointsPath = path.join(dir, 'points.json');
  fs.writeFileSync(pointsPath, '{ not json at all');

  const db = openDatabase(path.join(dir, 'game.db'));
  assert.strictEqual(importLegacyJson(db, { pointsPath }), 0);
  assert.strictEqual(fs.existsSync(pointsPath), true, 'the bad file is left in place');
});

test('import does nothing when there are no legacy files', () => {
  const dir = tempDir();
  const db = openDatabase(path.join(dir, 'game.db'));
  assert.strictEqual(
    importLegacyJson(db, {
      pointsPath: path.join(dir, 'points.json'),
      identitiesPath: path.join(dir, 'identities.json'),
    }),
    0
  );
});

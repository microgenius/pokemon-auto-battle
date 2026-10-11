'use strict';

const test = require('node:test');
const assert = require('node:assert');
const fs = require('fs');
const os = require('os');
const path = require('path');

const { openDatabase } = require('../lib/db');
const { IdentityStore } = require('../lib/identities');
const { WalletStore } = require('../lib/wallets');

function store() {
  return new IdentityStore(openDatabase(':memory:'));
}

test('the first claim on a name issues a token', () => {
  const claim = store().claim('sezer', '');

  assert.ok(claim.ok);
  assert.ok(claim.issued);
  assert.match(claim.token, /^[0-9a-f]{48}$/);
});

test('the same token reclaims the name, a wrong one does not', () => {
  const identities = store();
  const first = identities.claim('sezer', '');

  const again = identities.claim('sezer', first.token);
  assert.ok(again.ok);
  assert.ok(!again.issued);
  assert.strictEqual(again.token, first.token);

  assert.strictEqual(identities.claim('sezer', 'guessed').ok, false);
  assert.strictEqual(identities.claim('sezer', '').ok, false);
  assert.strictEqual(identities.claim('sezer', undefined).ok, false);
});

test('names are case-insensitive so casing cannot fork an identity', () => {
  const identities = store();
  const first = identities.claim('Sezer', '');

  assert.strictEqual(identities.claim('SEZER', '').ok, false);
  assert.ok(identities.claim('sezer', first.token).ok);
});

test('claim returns the canonical spelling, not what was typed', () => {
  const identities = store();
  const first = identities.claim('Sezer', '');
  assert.strictEqual(first.username, 'Sezer');

  const again = identities.claim('SEZER', first.token);
  assert.ok(again.ok);
  assert.strictEqual(again.username, 'Sezer', 'callers must use the name on record');
});

test('claims survive a restart', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'autobattle-identities-'));
  const file = path.join(dir, 'game.db');

  const first = openDatabase(file);
  const claim = new IdentityStore(first).claim('sezer', '');
  first.close();

  const second = openDatabase(file);
  const identities = new IdentityStore(second);
  assert.ok(identities.has('sezer'));
  assert.ok(identities.claim('sezer', claim.token).ok);
  assert.strictEqual(identities.claim('sezer', 'nope').ok, false);
  second.close();
});

test('releasing a name lets someone else take it, keeping the balance', () => {
  const db = openDatabase(':memory:');
  const identities = new IdentityStore(db);
  const wallets = new WalletStore(db);

  identities.claim('sezer', '');
  wallets.set('sezer', 777);
  identities.release('sezer');

  assert.strictEqual(identities.has('sezer'), false);
  const retaken = identities.claim('sezer', '');
  assert.ok(retaken.ok);
  assert.ok(retaken.issued);
  assert.strictEqual(wallets.get('sezer'), 777, 'release must not wipe the wallet');
});

test('a wallet with no token yet is adopted by the first claimer', () => {
  const db = openDatabase(':memory:');
  const wallets = new WalletStore(db);
  const identities = new IdentityStore(db);

  // How a row imported from the JSON era looks: balance, no owner.
  wallets.set('legacy', 250);
  assert.strictEqual(identities.has('legacy'), false);

  const claim = identities.claim('legacy', '');
  assert.ok(claim.ok);
  assert.ok(claim.issued);
  assert.strictEqual(wallets.get('legacy'), 250, 'adopting must not reset the balance');

  // And now it is owned.
  assert.strictEqual(identities.claim('legacy', '').ok, false);
});

test('a brand new identity starts with the standard wallet', () => {
  const db = openDatabase(':memory:');
  const identities = new IdentityStore(db);
  const wallets = new WalletStore(db);

  identities.claim('sezer', '');
  assert.strictEqual(wallets.get('sezer'), require('../lib/config').STARTING_POINTS);
});

'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('fs');
const os = require('os');
const path = require('path');

const { openDatabase } = require('../lib/db');
const { WalletStore } = require('../lib/wallets');
const { STARTING_POINTS } = require('../lib/config');

function store() {
  return new WalletStore(openDatabase(':memory:'));
}

function tempDbPath() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'autobattle-wallets-'));
  return path.join(dir, 'game.db');
}

test('seeds a new user at the starting balance', () => {
  const wallets = store();
  assert.equal(wallets.get('sezer'), STARTING_POINTS);
  assert.equal(wallets.has('sezer'), true);
  assert.equal(wallets.has('nobody'), false);
});

test('persists across instances', () => {
  const file = tempDbPath();

  const first = openDatabase(file);
  new WalletStore(first).set('sezer', 4242);
  first.close();

  const second = openDatabase(file);
  assert.equal(new WalletStore(second).get('sezer'), 4242);
  second.close();
});

test('clamps balances at zero', () => {
  const wallets = store();
  wallets.set('sezer', -500);
  assert.equal(wallets.get('sezer'), 0);
});

test('add applies a delta on top of the current balance', () => {
  const wallets = store();
  wallets.set('sezer', 100);
  assert.equal(wallets.add('sezer', 10), 110);
  assert.equal(wallets.add('sezer', -60), 50);
});

test('one name means one wallet regardless of casing', () => {
  const wallets = store();
  wallets.set('Sezer', 500);

  assert.equal(wallets.get('sezer'), 500);
  assert.equal(wallets.get('SEZER'), 500);
  assert.equal(wallets.has('sEzEr'), true);

  wallets.add('SEZER', 100);
  assert.equal(wallets.get('Sezer'), 600);
});

test('snapshot keys by the spelling the user was first stored under', () => {
  const wallets = store();
  wallets.set('Sezer', 300);
  wallets.set('ALI', 200);

  assert.deepEqual(wallets.snapshot(), { Sezer: 300, ALI: 200 });
});

test('snapshot is a copy, not a live handle', () => {
  const wallets = store();
  wallets.set('sezer', 100);

  const snap = wallets.snapshot();
  snap.sezer = 999;

  assert.equal(wallets.get('sezer'), 100);
});

test('replaceAll writes every balance it is given', () => {
  const wallets = store();
  wallets.set('sezer', 100);

  wallets.replaceAll({ sezer: 250, deniz: 500 });

  assert.equal(wallets.get('sezer'), 250);
  assert.equal(wallets.get('deniz'), 500);
});

test('replaceAll leaves users it does not mention alone', () => {
  const wallets = store();
  wallets.set('sezer', 100);
  wallets.set('absent', 42);

  wallets.replaceAll({ sezer: 250 });

  // The JSON store dropped these. On a shared row that would now also discard
  // the device token, and with it the user's claim on their own name.
  assert.equal(wallets.has('absent'), true);
  assert.equal(wallets.get('absent'), 42);
});

test('replaceAll is atomic — a rejected row rolls the whole batch back', () => {
  const wallets = store();
  wallets.set('sezer', 100);

  assert.throws(() => {
    // NaN fails the CHECK (balance >= 0) constraint partway through.
    wallets.replaceAll({ sezer: 250, ali: Number.NaN });
  });

  assert.equal(wallets.get('sezer'), 100, 'the earlier write must not survive');
});

test('boots cleanly against an empty database', () => {
  assert.deepEqual(store().snapshot(), {});
});

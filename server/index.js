'use strict';

const path = require('path');
const http = require('http');
const express = require('express');
const WebSocket = require('ws');

const {
  PORT,
  MATCH_BONUS,
  HOST_TOKEN,
  MAX_PAYLOAD_BYTES,
  RATE_LIMIT_BURST,
  RATE_LIMIT_PER_SECOND,
} = require('./lib/config');
const { calculateOdds } = require('./lib/odds');
const { settleBets } = require('./lib/settlement');
const { WalletStore } = require('./lib/wallets');
const { IdentityStore } = require('./lib/identities');
const { openDatabase, importLegacyJson } = require('./lib/db');
const { authorizeHost } = require('./lib/auth');
const { sanitizeUsername, sanitizeBets } = require('./lib/validation');
const { RateLimiter } = require('./lib/ratelimit');
const { authorizeHeal, stakeOn, healStateFor } = require('./lib/healing');

/**
 * Pokémon Auto Battle server.
 *
 * Transport and state machine only. Odds pricing, bet settlement and wallet
 * persistence live in ./lib so they can be unit tested without a socket.
 *
 * The Godot host owns the simulation; this process never simulates anything. It
 * tracks lobby state, prices markets, holds balances, and fans events out.
 */

const app = express();
const server = http.createServer(app);
const wss = new WebSocket.Server({ server, maxPayload: MAX_PAYLOAD_BYTES });

app.use(express.static(path.join(__dirname, 'public')));
app.use('/assets', express.static(path.join(__dirname, '../assets')));

const db = openDatabase(path.join(__dirname, 'game.db'));
importLegacyJson(db, {
  pointsPath: path.join(__dirname, 'points.json'),
  identitiesPath: path.join(__dirname, 'identities.json'),
});
const wallets = new WalletStore(db);
const identities = new IdentityStore(db);

/** ws -> { username, bet } for spectators. */
const clients = new Map();
let hostSocket = null;

const gameState = {
  status: 'WAITING', // WAITING | LOBBY | BATTLING | END
  // Bumped on every LOBBY_UPDATE. The page uses it to tell a fresh round from a
  // reconnect: without it, last round's picks stayed selected and got submitted
  // again, and the "bet accepted" screen kept people out of the new lobby.
  round: 0,
  options: [],
  bets: {}, // fighter alias -> [usernames] (winner market only, for the host UI)
  players: [], // [{ username, ready }] for the lobby roster
  winner: null,
  firstBlood: null,
  firstHit: null,
  matchBonusGiven: false,
};

/** username -> { bets: [{type, choice, wager}], wager } for the open round. */
let userBets = {};
let currentOdds = {};

/** Last LIVE_STATS by alias, so a heal can be sized against real max HP. */
let liveStats = {};
/** Room-wide timestamp of the last accepted heal; the cooldown is not per user. */
let lastHealAt = 0;
/** alias -> fraction of max HP healed so far this match. */
let healedThisMatch = {};
/** Heals debited but not yet acknowledged by the host: id -> {username, cost}. */
const pendingHeals = new Map();
let nextHealId = 1;

/**
 * The host is the only thing that can actually change HP, and it may never
 * answer — the fighter can die first, or the host can drop. A debit with no
 * acknowledgement is a charge for nothing, so every pending heal is refunded if
 * it is not confirmed in time.
 */
const HEAL_ACK_TIMEOUT_MS = 5000;

/**
 * Pushes per-fighter heal availability so the page can grey a button out and
 * say why, instead of letting people click into a rejection.
 */
function broadcastHealState() {
  if (gameState.status !== 'BATTLING') return;
  try {
    sendHealState();
  } catch (err) {
    // Never let this take the LIVE_STATS handler down with it: the stats table
    // would keep updating while the heal panel sat on "waiting for prices"
    // forever, with nothing in the log to say why.
    console.error('[heal] could not build heal state:', err.message);
  }
}

function sendHealState() {
  for (const [ws, info] of clients) {
    if (!info.username) continue;
    send(ws, {
      type: 'HEAL_STATE',
      ...healStateFor({
        roster: gameState.options,
        userBets,
        status: gameState.status,
        balance: wallets.get(info.username),
        lastHealAt,
        healedThisMatch,
        liveStats,
      }),
    });
  }
}

function refundHeal(id, why) {
  const pending = pendingHeals.get(id);
  if (!pending) return;
  pendingHeals.delete(id);
  clearTimeout(pending.timer);

  wallets.add(pending.username, pending.cost);
  console.log(`[heal] refunded ${pending.cost} CP to ${pending.username} — ${why}`);
  for (const [ws, info] of clients) {
    if (info.username === pending.username) {
      send(ws, { type: 'HEAL_REJECTED', reason: 'Şifa uygulanamadı, puanınız iade edildi.' });
      pushBalance(ws, pending.username);
    }
  }
}

// ---------------------------------------------------------------- transport

function send(ws, message) {
  if (ws && ws.readyState === WebSocket.OPEN) {
    ws.send(JSON.stringify(message));
  }
}

/**
 * Every socket needs one of these. A ws instance with no 'error' listener
 * rethrows as an uncaught exception and takes the process down — an oversized
 * frame alone was enough to kill the server, which made maxPayload a way to
 * stop the game rather than a protection.
 */
function guard(ws, label) {
  ws.on('error', (err) => {
    console.error(`[${label}] socket error:`, err.message);
    ws.terminate();
  });
}

function broadcast(message) {
  const data = JSON.stringify(message);
  for (const ws of clients.keys()) {
    if (ws.readyState === WebSocket.OPEN) ws.send(data);
  }
}

function sendToHost(message) {
  send(hostSocket, message);
}

function broadcastState() {
  broadcast({ type: 'STATE_UPDATE', state: gameState, odds: currentOdds });
}

/** Named spectators and whether each has pressed ready, in join order. */
function refreshPlayers() {
  gameState.players = [];
  for (const info of clients.values()) {
    if (info.username) gameState.players.push({ username: info.username, ready: !!info.ready });
  }
}

/**
 * Pushes the lobby roster to the host and, once everyone has pressed ready,
 * tells it to start. An empty lobby never counts as ready — otherwise the match
 * would fire the moment the host opened it.
 */
function syncLobbyReadiness() {
  refreshPlayers();
  sendToHost({ type: 'PLAYERS_UPDATE', players: gameState.players });
  broadcastState();

  if (gameState.status !== 'LOBBY') return;
  if (gameState.players.length > 0 && gameState.players.every((p) => p.ready)) {
    sendToHost({ type: 'ALL_READY' });
  }
}

/** Every heal still waiting on the host is money owed back. */
function refundPendingHeals(reason) {
  for (const id of [...pendingHeals.keys()]) refundHeal(id, reason);
}

/**
 * Hands every open stake back.
 *
 * Stakes leave the wallet at placement, so any path that drops userBets without
 * settling them has to refund or the points are simply gone: abandoning a match
 * to the main menu, restarting the lobby mid-match, or the host dropping off.
 * Settled bets are cleared in MATCH_RESULTS, so this only ever sees live ones.
 */
function voidOpenBets(reason) {
  refundPendingHeals(reason);

  const usernames = Object.keys(userBets);
  if (usernames.length === 0) return;

  for (const username of usernames) {
    const wager = userBets[username].wager || 0;
    if (wager > 0) wallets.add(username, wager);
  }
  userBets = {};
  gameState.bets = {};

  console.log(`[bets] voided ${usernames.length} slip(s), stakes refunded — ${reason}`);
  broadcast({ type: 'BETS_VOIDED', reason });
  pushAllBalances();
}

function pushBalance(ws, username) {
  send(ws, { type: 'USER_POINTS', points: wallets.get(username) });
}

function pushAllBalances() {
  for (const [ws, info] of clients) {
    if (info.username && wallets.has(info.username)) pushBalance(ws, info.username);
  }
}

// ---------------------------------------------------------------- host events

const hostHandlers = {
  LOBBY_UPDATE(data) {
    gameState.status = 'LOBBY';
    gameState.round += 1;
    gameState.options = data.options;
    gameState.bets = {};
    gameState.winner = null;
    gameState.firstBlood = null;
    gameState.firstHit = null;
    // A lobby opening while a match was still live means that match was
    // abandoned; those stakes go back.
    voidOpenBets('lobby reopened');
    currentOdds = calculateOdds(data.options);

    // A new round starts with nobody ready, or the previous round's readiness
    // would start this one instantly.
    for (const info of clients.values()) info.ready = false;

    if (!gameState.matchBonusGiven) {
      gameState.matchBonusGiven = true;
      for (const [ws, info] of clients) {
        if (!info.username) continue;
        wallets.add(info.username, MATCH_BONUS);
        pushBalance(ws, info.username);
      }
    }

    syncLobbyReadiness();
  },

  MATCH_START() {
    gameState.status = 'BATTLING';
    healedThisMatch = {};
    lastHealAt = 0;
    broadcastState();
    // Also pushed here and on JOIN, so the panel does not sit blank for a whole
    // LIVE_STATS interval — or forever, if that message never lands.
    broadcastHealState();
  },

  LIVE_STATS(data) {
    liveStats = {};
    for (const s of Array.isArray(data.stats) ? data.stats : []) {
      if (s && s.alias) liveStats[s.alias] = s;
    }
    broadcast(data);
    broadcastHealState();
  },

  /** Host confirming (or refusing) a heal it was asked to apply. */
  HEAL_RESULT(data) {
    const pending = pendingHeals.get(data.id);
    if (!pending) return;

    if (!data.ok) {
      refundHeal(data.id, data.reason || 'host refused');
      return;
    }

    pendingHeals.delete(data.id);
    clearTimeout(pending.timer);
    healedThisMatch[pending.alias] = (healedThisMatch[pending.alias] || 0) + pending.fraction;
    broadcastHealState();

    // Healing is a public act. Everyone sees who propped up whom.
    broadcast({
      type: 'HEAL',
      alias: pending.alias,
      username: pending.username,
      amount: data.healed || pending.amount,
      tier: pending.tier,
    });
  },

  FIRST_BLOOD(data) {
    gameState.firstBlood = data.killer;
    broadcast(data);
  },

  FIRST_HIT(data) {
    gameState.firstHit = data.attacker;
    broadcast(data);
  },

  MATCH_END(data) {
    gameState.status = 'END';
    gameState.winner = data.winner;
    broadcastState();
  },

  MATCH_RESULTS(data) {
    gameState.status = 'END';
    gameState.winner = data.winner;
    // Re-arm the attendance bonus for the next lobby.
    gameState.matchBonusGiven = false;

    const matchResults = { ...data };
    if (!Array.isArray(matchResults.all_stats)) {
      matchResults.all_stats = gameState.options.map((o) => ({ alias: o.alias, name: o.name, kills: 0 }));
    }

    const { results, points } = settleBets({
      userBets,
      userPoints: wallets.snapshot(),
      currentOdds,
      matchResults,
      fallbacks: { firstBlood: gameState.firstBlood, firstHit: gameState.firstHit },
    });
    wallets.replaceAll(points);

    // Settled, so no longer open. Without this the next voidOpenBets would
    // refund stakes that have already been paid out.
    userBets = {};

    broadcastState();
    broadcast({ type: 'BET_RESULTS', results });
    sendToHost({ type: 'BET_RESULTS', results });
    pushAllBalances();
  },

  /** Host walked out of a live match, e.g. back to the main menu. */
  MATCH_ABORTED() {
    voidOpenBets('match abandoned');
    gameState.status = 'WAITING';
    gameState.winner = null;
    broadcastState();
  },

  EVOLUTION(data) {
    // Nothing to rewrite. Bets, odds keys and gameState.bets are all keyed by
    // the fighter's roster-slot alias, which does not change here — that is the
    // whole point of having one. This handler used to rewrite open bets, remap
    // every odds key and patch each client's stored pick, all to chase a name
    // that had shifted underneath them.
    //
    // Relayed so the spectator UI can relabel the card and swap its sprite.
    if (!data.alias) return;
    const option = gameState.options.find((o) => o.alias === data.alias);
    if (option) {
      option.name = data.new_name || option.name;
      if (data.new_sprite_url) option.sprite_url = data.new_sprite_url;
    }
    broadcast(data);
  },
};

// ------------------------------------------------------------ spectator events

const clientHandlers = {
  JOIN(ws, info, data) {
    const requested = sanitizeUsername(data.username);
    if (!requested) {
      send(ws, { type: 'JOIN_REJECTED', reason: 'Geçersiz kullanıcı adı.' });
      return;
    }

    // A name belongs to the browser that first claimed it. Without the matching
    // token, this JOIN is someone else reaching for that wallet.
    const claim = identities.claim(requested, data.deviceToken);
    if (!claim.ok) {
      console.warn(`[join] refused "${requested}" — token mismatch`);
      send(ws, {
        type: 'JOIN_REJECTED',
        reason: 'Bu kullanıcı adı başka bir cihaza ait. Farklı bir ad seçin.',
      });
      return;
    }

    // The spelling on record wins over whatever was typed, so logging in as
    // "SEZER" cannot fork a second wallet away from "Sezer".
    const username = claim.username;
    info.username = username;
    const balance = wallets.get(username);
    console.log(`[join] ${username} (${balance} CP)${claim.issued ? ' — new' : ''}`);

    // The browser stores this and replays it on the next JOIN. Clearing site
    // data loses the name until someone releases it server-side.
    send(ws, { type: 'IDENTITY', username, deviceToken: claim.token });
    send(ws, { type: 'USER_POINTS', points: balance });
    if (userBets[username]) {
      send(ws, { type: 'RESTORE_BETS', bets: userBets[username] });
    }

    syncLobbyReadiness();
    broadcastHealState();
  },

  PLACE_BETS(ws, info, data) {
    if (gameState.status !== 'LOBBY') {
      send(ws, { type: 'BET_REJECTED', reason: 'Bahisler kapandı.' });
      return;
    }

    const username = info.username;
    if (!username) {
      send(ws, { type: 'BET_REJECTED', reason: 'Önce bir kullanıcı adı seçin.' });
      return;
    }

    // Checked against the current roster, so a slip cannot name a fighter that
    // is not in the match.
    const valid = sanitizeBets(data.bets, gameState.options);
    if (valid.length === 0) {
      send(ws, { type: 'BET_REJECTED', reason: 'Geçerli bir bahis bulunamadı.' });
      return;
    }

    const totalWager = valid.reduce((sum, b) => sum + b.wager, 0);

    // Replacing an existing slip refunds the previous stake first, so editing a
    // bet is not charged twice.
    const refund = userBets[username] ? userBets[username].wager : 0;
    const available = wallets.get(username) + refund;

    if (totalWager > available) {
      send(ws, {
        type: 'BET_REJECTED',
        reason: `Yetersiz bakiye: ${totalWager} CP gerekiyor, ${available} CP var.`,
      });
      return;
    }

    wallets.set(username, available - totalWager);
    userBets[username] = { bets: valid, wager: totalWager };

    const winnerBet = valid.find((b) => b.type === 'winner');
    if (winnerBet) {
      info.bet = winnerBet.choice;
      if (!gameState.bets[winnerBet.choice]) gameState.bets[winnerBet.choice] = [];
      if (!gameState.bets[winnerBet.choice].includes(username)) {
        gameState.bets[winnerBet.choice].push(username);
      }
    }

    // No RESTORE_BETS echo here. The client already knows what it sent, and now
    // that confirming leaves you on the lobby screen the echo arrives after any
    // edit made in the meantime and silently reverts it. JOIN still sends one —
    // that is the case where the client genuinely does not know.
    send(ws, { type: 'USER_POINTS', points: wallets.get(username) });
    broadcast({ type: 'BETS_UPDATE', bets: gameState.bets });
    sendToHost({ type: 'BETS_UPDATE', bets: gameState.bets });
  },

  READY(ws, info, data) {
    if (!info.username) return;
    info.ready = data.ready !== false;
    syncLobbyReadiness();
  },

  HEAL_REQUEST(ws, info, data) {
    if (!info.username) return;

    const alias = String(data.alias || '');
    const stats = liveStats[alias];
    const verdict = authorizeHeal({
      tierId: String(data.tier || ''),
      alias,
      roster: gameState.options,
      status: gameState.status,
      balance: wallets.get(info.username),
      stake: stakeOn(userBets, alias),
      lastHealAt,
      healedThisMatch: healedThisMatch[alias] || 0,
      targetMaxHp: stats ? stats.max_hp : 0,
      targetAlive: stats ? Number(stats.hp) > 0 : false,
    });

    if (!verdict.ok) {
      send(ws, { type: 'HEAL_REJECTED', reason: verdict.reason });
      return;
    }

    // Debit now, refund if the host never confirms. The other order would let a
    // fast clicker heal for free.
    wallets.add(info.username, -verdict.cost);
    lastHealAt = Date.now();
    pushBalance(ws, info.username);
    broadcastHealState();

    const id = nextHealId++;
    pendingHeals.set(id, {
      username: info.username,
      cost: verdict.cost,
      alias,
      amount: verdict.amount,
      fraction: verdict.fraction,
      tier: verdict.tier.id,
      timer: setTimeout(() => refundHeal(id, 'host did not answer'), HEAL_ACK_TIMEOUT_MS),
    });

    sendToHost({ type: 'APPLY_HEAL', id, alias, amount: verdict.amount, username: info.username });
  },

  EMOTE(ws, info, data) {
    if (gameState.status !== 'BATTLING' || !info.bet) return;
    sendToHost({
      type: 'EMOTE',
      username: info.username,
      pokemon: info.bet,
      emoteType: data.emoteType,
    });
  },
};

// ---------------------------------------------------------------- connections

wss.on('connection', (ws, req) => {
  // Attached before anything else so even a connection we are about to refuse
  // cannot crash the process.
  guard(ws, 'socket');

  const query = new URL(req.url || '/', 'http://localhost').searchParams;

  if (query.get('role') !== 'host') {
    attachSpectator(ws);
    return;
  }

  const verdict = authorizeHost({
    presentedToken: query.get('token'),
    remoteAddress: req.socket.remoteAddress,
    expectedToken: HOST_TOKEN,
    hostConnected: hostSocket !== null,
  });

  if (!verdict.ok) {
    console.warn(`[host] refused from ${req.socket.remoteAddress}: ${verdict.reason}`);
    // 4003 is in the private range; the client shows it rather than retrying blind.
    ws.close(4003, verdict.reason);
    return;
  }

  attachHost(ws);
});

function attachHost(ws) {
  console.log('[host] connected');
  hostSocket = ws;

  ws.on('message', (raw) => {
    let data;
    try {
      data = JSON.parse(raw);
    } catch (err) {
      console.error('[host] malformed message:', err.message);
      return;
    }

    const handler = hostHandlers[data.type];
    if (!handler) return;
    try {
      handler(data);
    } catch (err) {
      console.error(`[host] ${data.type} failed:`, err);
    }
  });

  ws.on('close', () => {
    // Only the socket that currently holds the role may give it up, so a late
    // close from a replaced socket cannot orphan a live host.
    if (hostSocket !== ws) return;
    console.log('[host] disconnected');
    hostSocket = null;
    voidOpenBets('host disconnected');
    gameState.status = 'WAITING';
    broadcastState();
  });
}

function attachSpectator(ws) {
  const info = { username: null, bet: null, ready: false };
  const limiter = new RateLimiter(RATE_LIMIT_BURST, RATE_LIMIT_PER_SECOND);
  clients.set(ws, info);
  send(ws, { type: 'STATE_UPDATE', state: gameState, odds: currentOdds });

  let dropped = false;

  ws.on('message', (raw) => {
    // close() only starts the handshake, so frames already buffered still
    // arrive. Latch instead of re-closing, or a flood logs once per message.
    if (dropped) return;

    if (!limiter.allow()) {
      // Dropping beats replying: an answer to every message is exactly the
      // amplification a flood is after.
      dropped = true;
      console.warn(`[client] rate limit exceeded (${info.username || 'anonymous'})`);
      ws.close(4029, 'too many messages');
      return;
    }

    let data;
    try {
      data = JSON.parse(raw);
    } catch (err) {
      console.error('[client] malformed message:', err.message);
      return;
    }

    const handler = clientHandlers[data.type];
    if (!handler) return;
    try {
      handler(ws, info, data);
    } catch (err) {
      console.error(`[client] ${data.type} failed:`, err);
    }
  });

  ws.on('close', () => {
    clients.delete(ws);
    // Someone leaving can be what makes the rest of the lobby unanimous.
    syncLobbyReadiness();
  });
}

// ---------------------------------------------------------------- lifecycle

server.listen(PORT, () => {
  console.log(`Pokémon Auto Battle server listening on http://localhost:${PORT}`);
});

for (const signal of ['SIGINT', 'SIGTERM']) {
  process.on(signal, () => {
    console.log(`\n[shutdown] ${signal} — checkpointing the database`);
    wallets.flush();
    db.close();
    server.close(() => process.exit(0));
    // Do not hang forever on lingering sockets.
    setTimeout(() => process.exit(0), 2000).unref();
  });
}

module.exports = { app, server };

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Pokémon Auto Battle is a multiplayer Pokemon battle betting simulator played by a remote team. A Godot 4.7 client runs the battle simulation; a Node.js/Express server manages game state, odds and wallets, and serves a web spectator UI where people place bets on the outcome.

Unofficial non-commercial fan project — see `LICENSE` before adding assets or changing anything user-facing.

## Running the Project

### Node.js Server
```bash
cd server
npm install       # first time only
npm start         # or: npm run dev  (node --watch)
npm test          # 101 node:test cases over odds, settlement, wallets, auth, validation
```

Environment variables: `PORT` (3000), `AUTOBATTLE_STARTING_POINTS` (1000),
`AUTOBATTLE_MATCH_BONUS` (10), `AUTOBATTLE_HOST_TOKEN` (unset), `AUTOBATTLE_MAX_PAYLOAD`
(65536), `AUTOBATTLE_RATE_LIMIT_BURST` (20), `AUTOBATTLE_RATE_LIMIT_PER_SECOND` (10),
`AUTOBATTLE_ODDS_PAYBACK` (1.0), `AUTOBATTLE_MIN_ODDS` (1.1), `AUTOBATTLE_MAX_ODDS` (15).

`AUTOBATTLE_HOST_TOKEN` must be set on both sides — the server reads it from the
environment, and the Godot host appends it as `?token=` (see `Settings.gd`).
Leave it unset for local play: the server then only accepts a host on loopback.

### Godot Game Client
- Open project in Godot 4.7 editor, press F5 to run
- Host connects to `ws://127.0.0.1:3000/?role=host`
- Server address is configurable via `Settings.server_url` or the `AUTOBATTLE_SERVER_URL` env var

### Web Spectator UI
- After server starts, open `http://localhost:3000` in browser

### Asset pipeline (`tools/`, runnable from any directory)
```bash
python3 tools/setup.py                       # fresh clone: sprites, icons, poke.png, then verifies
python3 tools/fetch_pokemon_data.py          # rebuilds pokemon_advanced_data.json
```
`assets/pokemon_sprites/` is gitignored — Pokémon artwork is not ours to
redistribute. A fresh clone must run `setup.py` before opening Godot.
**Never commit Nintendo-owned art** (sprites, icons, Poké Ball, characters in
backgrounds). See `tools/README.md` for the full script list.

## Architecture

### Communication Flow
```
Godot Client (host) <--WebSocket--> Node.js Server <--WebSocket--> Web Browsers (spectators)
```

1. The Godot client is the **single source of truth for the simulation** and broadcasts events (`scripts/NetworkManager.gd`)
2. The server never simulates anything — it tracks state, prices markets, holds wallets, fans events out
3. Web spectators (`server/public/index.html`) view live stats and place bets

### Game States (server-managed)
`WAITING` → `LOBBY` → `BATTLING` → `END`

### Key WebSocket Message Types

**Host → Server**: `LOBBY_UPDATE`, `MATCH_START`, `LIVE_STATS`, `FIRST_BLOOD`, `FIRST_HIT`, `MATCH_END`, `MATCH_RESULTS`, `EVOLUTION`, `MATCH_ABORTED`, `HEAL_RESULT`

**Audience → Server**: `JOIN`, `PLACE_BETS`, `EMOTE`, `READY`, `HEAL_REQUEST`

**Server → All**: `STATE_UPDATE`, `BETS_UPDATE`, `BET_RESULTS`, `BET_REJECTED`, `USER_POINTS`, `RESTORE_BETS`, `EVOLUTION`, `IDENTITY`, `JOIN_REJECTED`, `BETS_VOIDED`, `HEAL`, `HEAL_REJECTED`

**Server → Host**: `PLAYERS_UPDATE`, `ALL_READY`, `APPLY_HEAL`, `BETS_UPDATE`, `BET_RESULTS`

### Fighter identity: aliases, not names

**Every fighter is identified on the wire by its roster-slot alias —
`candidate1`, `candidate2` — assigned at spawn and never reassigned.** Display
names ride alongside (`winner` + `winner_name`, `alias` + `name`) and are only
ever drawn on screen.

`GameManager.alias_for_slot(i)` and `Lobby.gd` must agree for the same roster
index. `Pokemon.alias` is set once in `spawn_pokemons_geometrically` and
survives evolution untouched, unlike `pokemon_name` or `current_pokemon_id`.

This is what removed a whole class of bug. Names change mid-match when a Pokemon
evolves and differ in case between sources, so matching on them needed: an
`EVOLUTION` handler that rewrote every open bet, remapped every odds key and
patched each client's stored pick; `lower()` on both sides of every settlement
comparison; a spectator-emote lookup that checked the current name *and* the
original species name out of the database. All of it is gone. `remapOddsForEvolution`
no longer exists.

When adding a message or a market, key it on the alias. If you find yourself
comparing names to decide *which fighter*, that is the bug.

### GDScript Architecture

Autoloads (registered in `project.godot`):

| File | Role |
|------|------|
| `scripts/Global.gd` | Static game data (species DB, attack table, type chart) + session state. **Not persisted.** |
| `scripts/Settings.gd` | Player-chosen config (tuning knobs, roster, map, server URL). Persisted to `user://settings.cfg`. |
| `scripts/NetworkManager.gd` | WebSocket client (host role), with exponential-backoff reconnect |

Gameplay:

| File | Role |
|------|------|
| `scripts/GameManager.gd` | Match flow: map load, spawning, countdown, win condition, network dispatch. Coordinates UI but does not build it. |
| `scripts/Pokemon.gd` | Entity: stats, wandering AI, combat, levelling, evolution |
| `scripts/AttackProjectile.gd` | Projectile physics + per-type procedural rendering |
| `scripts/Lobby.gd` | Roster selection and pre-match intro reel |
| `scripts/MainMenu.gd` | Menu and settings panel |
| `scripts/GameResources.gd` | **Central registry for every resource path.** Use `preload`ed constants from here instead of `load("res://...")`. |
| `scripts/PokemonMatchStats.gd` | Per-fighter match record; the one shape all consumers see |

UI components (`scripts/ui/`) — presentation only, instantiated from GameManager:

| File | Role |
|------|------|
| `Scoreboard.gd` | Live standings. Attached to a node in `Main.tscn`. Updates **in place**, coalesced to ~6 Hz. |
| `EventLog.gd` | Slide-out combat log, capped at 150 entries |
| `BetResultsPanel.gd` | Full-screen settlement breakdown |
| `MatchStatsPanel.gd` | End-of-match stats rows |
| `DevStatsPanel.gd` | Developer inspector (click a fighter when `Settings.developer_mode`) |
| `EmotePopup.gd` | Spectator reaction over a fighter |
| `FloatingText.gd` | Combat callouts ("DODGE", "ÇOK ETKİLİ") |
| `GhostTrail.gd` | Pooled dodge afterimages |
| `HealAura.gd` | Paid-heal effect: hollow red ring, rising plus signs. Drawn procedurally. |

### Server Architecture

`server/index.js` is transport + state machine only. Logic lives in `server/lib/`:

| File | Role |
|------|------|
| `lib/config.js` | Env-overridable tunables, bet type list and labels |
| `lib/odds.js` | Odds pricing. Pure. |
| `lib/settlement.js` | Bet resolution and payout. Pure, no I/O, no module state. |
| `lib/db.js` | Opens the SQLite handle, creates the schema, imports the legacy JSON once |
| `lib/wallets.js` | `WalletStore` — CP balances over SQL |
| `lib/auth.js` | Host authorization and constant-time token compare. Pure. |
| `lib/identities.js` | `IdentityStore` — binds a username to the browser that claimed it |
| `lib/validation.js` | Sanitises usernames and bet slips against the live roster. Pure. |
| `lib/ratelimit.js` | Per-connection token bucket. Pure, clock injected. |
| `lib/healing.js` | Heal pricing and eligibility. Pure, clock injected. |

Wallets and identities share one `users` row in `server/game.db`, keyed by
the lowercased username with the typed spelling kept for display. They used to
be two JSON files keyed differently, so `Sezer` and `sezer` were one identity
but two wallets. `IdentityStore.claim()` returns the canonical spelling —
**use it instead of what the client typed**, or a differently-cased login forks
a wallet away from its own identity.

Persistence is `node:sqlite` (no npm driver), which is still flagged
experimental, so the npm scripts pass `--disable-warning=ExperimentalWarning`.
Only prepare/run/get/all/exec are used, so better-sqlite3 is a drop-in if that
flag ever becomes a problem.

Tests live in `server/test/` and mirror the lib modules.

## Conventions

- **Resources**: add new paths to `GameResources.gd` and `preload` them. Avoid `load("res://...")` on hot paths (per-frame, per-hit, per-shot).
- **Node access in `Main.tscn`**: use `%UniqueName`, not `$"../UI/A/B/C"` chains.
- **UI**: new panels go in `scripts/ui/` as their own class. Do not add Control-building code to `GameManager.gd`.
- **Server logic**: anything worth testing goes in `server/lib/` as a pure function, not inline in a socket handler.
- **Scoreboard**: call `game_manager.request_scoreboard_refresh()` (coalesced). `refresh_now()` is for one-off moments only.
- Comments and player-facing strings are Turkish; documentation is English.

## Betting System

Seven markets: Winner, First Blood, First Hit, Kill King, Dodge King, Crit King,
Incomplete Evolution. Bets settle independently — there is no parlay.

**Every price is `ODDS_PAYBACK / probability`.** Six markets pick exactly one
fighter, so their probabilities sum to 1 and a five-way board prices around 5x.
`incomplete_evolution` is not exclusive (several fighters can satisfy it) and
prices from its own probability, which is far higher — around 1.6x rather than
5x. That is deliberate: it is the market you win often for a little.

It resolves on `evolution_complete` (an empty `evolves_to`, reported per fighter
by the host), not on `has_evolved`. The market it replaced asked whether a
fighter had evolved *at all*, which settled correctly but almost never paid,
because passive XP evolves nearly everyone within seconds.

A species that cannot evolve is complete the moment it spawns, so the outcome is
impossible for it. `calculateOdds` deliberately emits **no key** for those, and
the lobby hides any option the current tab has no price for — never invent a
price for a bet that cannot be won.

`ODDS_PAYBACK` defaults to 1.0 — a fair book, where price matches probability.
The upward drift players feel is `MATCH_BONUS`, not the odds. Raise the payback
to make the board itself generous.

Odds keys are `${betType}_${alias}`. Each market has its own stat blend and
`sharpness` exponent in `MARKETS` (`lib/odds.js`). Two markets sharing a blend price identically, which is both
wrong and dull — a test guards against it.

Probabilities are still heuristics over base stats, not measured win rates. What
changed is that the arithmetic between probability and price is now correct, so
better probabilities feed straight through to better prices.

Starting wallet 1000 CP; +10 CP per match attended. Stakes are debited at
placement, so `payout` is gross and net movement is `payout - wager`.

## Pokemon Data

- `assets/pokemon_advanced_data.json` — stat database (#0001–#0251)
- `assets/pokemon_sprites/<ID>/sprite_frames.tres` — animation resources (Idle, Walk, Attack, Hurt, Hop, Pose), generated locally by `tools/`, gitignored
- Default roster: Bulbasaur (0001), Charmander (0004), Squirtle (0007), Abra (0063), Haunter (0092)

## Known Bugs

None open. The three that were tracked here are fixed; the reasoning is kept
below because each was mis-described before it was looked at, and the same
mistake is easy to repeat.

## Paid healing

Spectators spend CP to restore HP to any living fighter. The server never
applies it — the host owns the simulation — so the flow is
`HEAL_REQUEST` → debit → `APPLY_HEAL` → `HEAL_RESULT` → broadcast `HEAL`.

**The refund path is not optional.** The fighter can die between the request and
the host handling it, and `LIVE_STATS` is up to 3 s stale so the server's view of
"alive" is a guess. Every debited heal is refunded if the host refuses or does
not answer inside `HEAL_ACK_TIMEOUT_MS`.

### The price is the money already on that fighter

A heal costs `stakeMultiplier x everything staked on its target`, across every
spectator and every market, floored at `HEAL_MIN_COST`. Back Charmander with
150 CP and a full heal on Charmander costs 150 CP. The price therefore tracks
the betting economy by itself — nothing to re-tune as wallets grow — and a
fighter carrying the room's money is expensive to prop up while an ignored one
is cheap.

That shape is also what keeps self-dealing in check. Healing a fighter you have
money on buys a better outcome on a bet you already hold, and that edge is
`stake x (p_after - p_before) / p_before` — proportional to the stake, so only a
price that is also proportional can track it. Measured across realistic board
positions the edge runs 0.24x to 1.27x the stake, so the default 1.0x multiplier
covers the cheaper half and `HEAL_MATCH_CAP` is the backstop for the rest.

The cooldown is **room-wide, not per spectator** — ten people should not be able
to heal ten times as often as one. Every heal is publicly attributed, and the
page greys out what it cannot buy rather than letting people click into a
rejection (`HEAL_STATE`).

## Simulation notes worth keeping

**Crit King was priced on the wrong driver.** A critical *is* a Sharp Eye shot:
`total_criticals`, the damage multiplier and the roll all agree on that. What
disagreed was `get_crit_chance()`, which returned a speed-based figure the
simulation never called — only the developer panel read it. Sharp Eye fires on a
flat `prob_predictive_aim x prob_perfect_aim` roll (4% by default), identical for
everyone, so crit count tracks *how many shots a fighter lives to take*. The
market is now priced on bulk (`endurance`), not speed. Speed already decides
dodging; pricing both on it made two markets that were near-copies of each other.

**First blood is the first kill, not the first death.** A shooter that dies while
its own shot is in flight leaves the victim with no killer. The old code fired
anyway, scanned for anyone with a score, found nobody, and settled the market
against `""` — every bet on it lost. An unattributed death now simply does not
count, and the next kill takes the honour.

**Passive XP was 95% of all XP.** At `EXP_PER_SECOND` 200 every fighter levelled
in lockstep, because passive XP is the same for everyone — a shared clock, not a
source of difference. Matches were decided by base stats and RNG before anyone
landed a shot. The awards were rebalanced to keep an average fighter on the same
pace (~29k XP over two minutes, so the ~2 minute match length is unchanged) while
moving half the total onto earned XP. Levels reached by a weak / average / strong
fighter went from 38 / 40 / 44 to 32 / 41 / 50.

These probabilities are still heuristics over base stats rather than measured win
rates. A Monte Carlo pass over the real simulation would price them properly.

## Security

The trust model: the Godot host is authoritative over the simulation, and
everything arriving over a socket — from a spectator *or* from the host — is
attacker-controlled input.

| Control | Where | Notes |
|---|---|---|
| Host authorization | `lib/auth.js` | `AUTOBATTLE_HOST_TOKEN` must match. Unset means loopback-only, so local dev needs no config. A second host is refused, never swapped in. |
| Username ownership | `lib/identities.js` | First claim mints a device token the browser replays on later `JOIN`s. Stops teammates taking each other's wallet; it is not a password system. |
| Input validation | `lib/validation.js` | `PLACE_BETS` choices are checked against the live roster and normalised to its spelling; one bet per market. |
| Flood control | `lib/ratelimit.js` | Per-connection token bucket plus `maxPayload`. |
| XSS | `public/index.html` | No `innerHTML` anywhere. Text goes through `textContent` via the `el()` helper, sprite paths through `safeSpriteUrl()`. **Keep it that way** — the host controls every name and URL the page renders. |

Every socket needs an `error` listener (`guard()` in `index.js`). A `ws` instance
without one rethrows as an uncaught exception and takes the process down; an
oversized frame alone was enough to kill the server.

`server/game.db` holds balances and device tokens. It is gitignored and
should stay that way.

## Server Dependencies
- `express` 5.2.1 — HTTP + static file serving
- `ws` 8.21.1 — WebSocket server

# Pokémon Auto Battle

A multiplayer auto-battler where nobody plays.

Six Pokémon are dropped into an arena and fight each other unattended — they
wander, shoot, dodge, level up and evolve entirely on their own. The humans sit
on the sidelines and bet fake points on what will happen. It exists so a remote
team has something to watch together for four minutes a day.

> **Unofficial fan project.** Not affiliated with Nintendo, Creatures Inc.,
> GAME FREAK, or The Pokémon Company. Non-commercial, no real money involved.
> See [LICENSE](LICENSE).

---

## How a match works

```
		LOBBY                  BATTLE                    END
  pick roster, place bets  →  simulation runs   →  payouts + stats
	 (~30-60s window)        (broadcast live)      (wallets updated)
```

1. **Lobby** — the host picks 3–6 species and a map. The server broadcasts the
   roster and computed odds; spectators place bets from their browser while an
   intro reel cycles through each fighter's stats and evolution tree.
2. **Battle** — Pokémon hatch from Pokéballs, then wander and fire type-themed
   projectiles at the nearest opponent. Damage uses the type chart; speed drives
   dodge chance; passive and combat XP drives levelling and evolution. Spectators
   watch live HP/level/kill stats and can spam emotes that pop up over their
   pick's head.
3. **End** — last one standing wins. The server settles every bet, updates
   wallets, and both the game and the web UI show a breakdown.

## Betting

Everyone starts with **1000 CP** and gets **+10 CP** for showing up to a match.
CP is a scoreboard — it has no value and cannot be cashed out.

Bets settle independently — there is no parlay, so a slip across several markets
tends to land small wins often rather than one big one.

Every price is `payback ÷ probability`, with the probability estimated from the
roster's base stats. Six of the seven markets pick exactly one fighter, so a
five-way board prices around 5×; a rank outsider in a speed market can reach
12×. By default the book is fair — the steady drip upward is the +10 CP for
turning up, not the odds.

`incomplete_evolution` is the odd one out and the friendliest: several fighters
can satisfy it at once, so it pays around 1.6× and lands often. A species with
no evolution left can never satisfy it, so it simply is not offered for that
fighter.

Seven markets:

| Market | Resolves to |
|---|---|
| `winner` | Last Pokémon alive |
| `first_blood` | First to score a kill |
| `first_hit` | First to land any hit |
| `kill_king` | Most kills |
| `dodge_king` | Most dodges |
| `crit_king` | Most critical hits |
| `incomplete_evolution` | Dies still short of its final form |

## Healing

During a battle, spectators can spend CP to restore HP to any living fighter — a
red ring flares around it and plus signs drift up. Every heal is announced with
the name of whoever paid for it.

A heal costs a multiple of everything staked on its target, so a fighter
carrying 150 CP of the room's money costs about 150 CP to top up while one
nobody fancies costs the floor. That is what stops people propping up their own
pick for profit — the edge from doing so scales with the stake, so the price has
to as well. The cooldown is room-wide, and one fighter can only receive so much
healing per match.

## Architecture

```
   Godot 4.7 client (host)          Node.js server              Browsers
  ┌──────────────────────┐      ┌───────────────────┐      ┌──────────────┐
  │ runs the simulation  │  ws  │ game state, odds, │  ws  │ place bets,  │
  │ broadcasts events    │─────▶│ bets, wallets     │◀────▶│ live stats,  │
  │ renders the arena    │◀─────│ serves web UI     │      │ emotes       │
  └──────────────────────┘      └───────────────────┘      └──────────────┘
```

The Godot client is the **single source of truth for the simulation**. The server
never simulates anything — it tracks state, prices markets, holds wallets, and
fans events out to spectators.

### Layout

```
scenes/          Godot scenes (MainMenu, Lobby, Main arena, Level1/2, entities)
scripts/         Gameplay code
  Global.gd        autoload — species DB, attack table, type chart
  Settings.gd      autoload — persisted user settings + match config
  NetworkManager.gd autoload — WebSocket client (host role)
  GameManager.gd   match flow, spawning, win condition, event dispatch
  Pokemon.gd       entity: stats, AI, combat, levelling, evolution
  AttackProjectile.gd projectile physics + per-type procedural rendering
  ui/              extracted HUD panels (scoreboard, event log, results, dev)
server/
  index.js         HTTP + WebSocket entry point
  lib/             pure modules (odds pricing, bet settlement) — unit tested
  public/          spectator web UI (single file)
  test/            node:test suites
assets/          fonts, themes, maps, species data (Pokémon sprites are downloaded, see below)
tools/           one-off asset pipeline scripts (see tools/README.md)
```

### Protocol

WebSocket, JSON frames, discriminated on `type`.

| Direction | Messages |
|---|---|
| Host → Server | `LOBBY_UPDATE` `MATCH_START` `LIVE_STATS` `FIRST_BLOOD` `FIRST_HIT` `MATCH_END` `MATCH_RESULTS` `EVOLUTION` |
| Spectator → Server | `JOIN` `PLACE_BETS` `EMOTE` |
| Server → clients | `STATE_UPDATE` `BETS_UPDATE` `BET_RESULTS` `USER_POINTS` `RESTORE_BETS` `EVOLUTION` |

Server-side game states: `WAITING` → `LOBBY` → `BATTLING` → `END`.

Fighters are identified by a roster-slot alias (`candidate1`, `candidate2`) that
is fixed for the whole match. Display names travel alongside it and are only
used on screen — so a bet placed on a Bulbasaur still settles correctly after it
becomes an Ivysaur, with nothing rewritten anywhere.

## Running it

### 1. Sprites (not included)

This repository ships the code, the species data and its own art, but **not the
Pokémon sprites**. Every animation sheet and icon depicts a character owned by
Nintendo, Creatures Inc., GAME FREAK and The Pokémon Company, and that is not
something a fan project can redistribute — even where the sprite artists
themselves have released their work freely.

All of it is already published openly by community projects. One script fetches
it straight from the source into `assets/pokemon_sprites/`, which is gitignored:

```bash
python3 tools/setup.py
```

| Files | Source | Terms |
|---|---|---|
| `*-Anim.png`, `AnimData.xml` | [PMDCollab/SpriteCollab](https://github.com/PMDCollab/SpriteCollab) | Fan-made, CC BY-NC 4.0. Artists are credited in that repo's `credit_names.txt`. |
| `icon.png`, `poke.png` | [PokeAPI/sprites](https://github.com/PokeAPI/sprites) | Images © The Pokémon Company; the repository itself is CC0. |
| `sprite_frames.tres` | Generated locally from `AnimData.xml` | — |

Python 3.9+, standard library only — nothing to `pip install`. It is about 2,000
files and 40 MB for #0001–#0251. Files that already exist are skipped, and the
script ends by naming any species still missing, so if the connection drops just
run it again.

Do this **before** opening the project in Godot. If the editor was already open,
use *Project → Reload Current Project* so it imports the new textures.

### 2. Server

```bash
cd server
npm install
npm start          # http://localhost:3000
```

Configuration via environment variables:

| Variable | Default | Purpose |
|---|---|---|
| `PORT` | `3000` | HTTP/WebSocket port |
| `AUTOBATTLE_STARTING_POINTS` | `1000` | Wallet balance for new users |
| `AUTOBATTLE_MATCH_BONUS` | `10` | CP granted per match attended |
| `AUTOBATTLE_ODDS_PAYBACK` | `1.0` | Expected return per unit staked. 1.0 is a fair book |
| `AUTOBATTLE_MIN_ODDS` | `1.1` | Floor, so a heavy favourite still pays something |
| `AUTOBATTLE_MAX_ODDS` | `15` | Ceiling on a long shot |
| `AUTOBATTLE_HOST_TOKEN` | unset | Secret the host must present. Unset ⇒ loopback-only host |
| `AUTOBATTLE_MAX_PAYLOAD` | `65536` | Largest accepted WebSocket frame, in bytes |
| `AUTOBATTLE_RATE_LIMIT_BURST` | `20` | Messages a spectator may send back to back |
| `AUTOBATTLE_RATE_LIMIT_PER_SECOND` | `10` | Sustained rate once the burst is spent |
| `AUTOBATTLE_HEAL_SMALL_MULTIPLIER` | `0.4` | Small heal (+10% max HP), as a multiple of the stake on that fighter |
| `AUTOBATTLE_HEAL_LARGE_MULTIPLIER` | `1.0` | Large heal (+30% max HP), likewise |
| `AUTOBATTLE_HEAL_MIN_COST` | `25` | Floor, for a fighter nobody has backed |
| `AUTOBATTLE_HEAL_COOLDOWN_MS` | `30000` | Wait between heals — room-wide, not per spectator |
| `AUTOBATTLE_HEAL_MATCH_CAP` | `0.6` | Total healing one fighter may receive, as a fraction of max HP |

Balances and username ownership live in `server/game.db`, a SQLite database.
It is gitignored — runtime state, not source, and the device tokens in it are
secrets.

An older checkout that still has `points.json` / `identities.json` is imported
automatically on first boot; the files are renamed to `*.migrated` rather than
deleted, so the move is reversible.

Requires Node 22.5 or newer for the built-in `node:sqlite` module. There is no
native build step and no extra dependency.

### 3. Game client

Open the project in **Godot 4.7** and press <kbd>F5</kbd>. From the main menu,
start a match as host; the client connects to the server automatically.

To point at a server on another machine, set the address in the in-game settings
panel, or export `AUTOBATTLE_SERVER_URL` before launching.

If the server runs anywhere other than the host's own machine, it will refuse
the host role unless both sides share a secret:

```bash
export AUTOBATTLE_HOST_TOKEN=$(openssl rand -hex 24)   # same value on both machines
```

Without it, only a host connecting over loopback is accepted — which is exactly
what you want for local play, and what stops anyone else on the network from
claiming the role and fabricating match results.

### 4. Spectators

Everyone else opens `http://<host-machine>:3000` and picks a username. The page
reconnects on its own and restores any bets already placed for the round.

The first browser to claim a username owns it: the server hands back a token the
page stores locally and replays on later joins, so nobody else can take that
name or its wallet. Clearing site data gives the name up — clear that user's
`device_token` in `server/game.db` to hand it back:

```bash
sqlite3 server/game.db "UPDATE users SET device_token = NULL WHERE username = 'sezer'"
```

### Tests

```bash
cd server
npm test
```

Covers odds pricing and bet settlement — the two places where a silent mistake
costs somebody points — plus host authorization, username ownership, bet-slip
validation and rate limiting.

## Development notes

- **Tuning knobs** live in the main menu settings panel (direction-change and
  attack probabilities, predictive aim rates, arena HP multiplier) and persist
  to `user://settings.cfg`. Developer mode lets you click a Pokémon mid-match to
  pause and inspect its full stat block.
- **Adding species** — the roster picker exposes every base-form Pokémon in
  #0001–#0251 that has generated sprite resources. To add more, extend the ID
  range in `tools/download_and_generate_all.py` and re-run it.
- **Stat model** roughly follows the mainline games: per-Pokémon IVs, a
  level-scaled stat formula, physical/special split, and the full type chart in
  `Global.gd`. It is close to canon, not faithful to it.

## Credits

Sprites, downloaded rather than bundled, by the
[PMDCollab SpriteCollab](https://github.com/PMDCollab/SpriteCollab) community
(CC BY-NC 4.0); icons via [PokeAPI/sprites](https://github.com/PokeAPI/sprites).
Species data via [PokéAPI](https://pokeapi.co/).
Built on [Godot](https://godotengine.org/). Full attribution in [LICENSE](LICENSE).

# Asset pipeline

One-off scripts that fetch Pokémon data and sprites and turn them into Godot
resources. The sprite output under `assets/pokemon_sprites/` is gitignored —
Pokémon artwork is not ours to redistribute — so a fresh clone runs `setup.py`
once (see the main README). The rest are only needed when adding species or
regenerating resources.

Every script resolves paths relative to the project root, so it does not matter
which directory you invoke them from.

## Python scripts

Requires Python 3.9+. `check_sizes.py` additionally needs Pillow
(`pip install pillow`).

| Script | What it does |
|---|---|
| `setup.py` | First-time setup: runs the two scripts below, fetches `poke.png`, and fails loudly if any species is still missing. **This is the one you usually want.** |
| `download_and_generate_all.py` | Downloads sprite sheets + `AnimData.xml` for #0001–#0251 and writes `sprite_frames.tres` for each. |
| `fetch_pokemon_data.py` | Rebuilds `assets/pokemon_advanced_data.json` (base stats, types, evolution graph) from PokéAPI. |
| `download_names.py` | Rebuilds the simpler `assets/pokemon_data.json` name list from PokéAPI. |
| `download_icons.py` | Downloads the roster/web-UI icon for each species from PokeAPI/sprites. |
| `download_sprites.py` | Downloads animation sheets for a hardcoded subset of species. |
| `download_xml.py` | Downloads `AnimData.xml` for the same subset. |
| `generate_tres.py` | Builds `sprite_frames.tres` from already-downloaded sheets. |
| `check_sizes.py` | Prints frame dimensions — useful when a new sheet renders wrong. |

```bash
python3 tools/setup.py
```

Sprite data comes from [PMDCollab/SpriteCollab](https://github.com/PMDCollab/SpriteCollab),
icons from [PokeAPI/sprites](https://github.com/PokeAPI/sprites), stats from
[PokéAPI](https://pokeapi.co/). See `LICENSE` for attribution.

## Godot editor scripts

Run headlessly against the project:

```bash
godot --headless --script tools/godot/create_theme.gd
```

| Script | What it does |
|---|---|
| `godot/create_theme.gd` | Regenerates `assets/themes/pixel_theme.tres`. |
| `godot/generate_spriteframes.gd` | Godot-side equivalent of `generate_tres.py`. |

class_name GameResources
extends RefCounted
## Central registry for every resource path the game touches at runtime.
##
## Two reasons this exists:
##
##  1. Hot paths. Pokemon.gd used to call load() on the projectile scene for
##     every shot and on the pixel font for every floating damage number. Godot
##     caches resources, so this was not catastrophic, but it put a hash lookup
##     and a string concat in the inner loop for no reason. preload() resolves
##     at compile time instead.
##
##  2. Failure timing. A typo in a preload() path is a parse error you see the
##     moment you open the project. A typo in a load() path is a null you see
##     mid-match, three minutes into a game everyone is watching.
##
## Per-species sprite paths still have to be built at runtime (the ID is only
## known once a Pokemon spawns), so those go through sprite_frames_for() and
## icon_for(), which at least keeps the string formatting in one place.

# --- Scenes ---
const POKEMON_SCENE := preload("res://scenes/Pokemon.tscn")
const PROJECTILE_SCENE := preload("res://scenes/AttackProjectile.tscn")
const FIREWORK_SCENE := preload("res://scenes/Firework.tscn")

# --- Scene paths (for change_scene_to_file, which takes a path not a resource) ---
const MAIN_MENU_PATH := "res://scenes/MainMenu.tscn"
const LOBBY_PATH := "res://scenes/Lobby.tscn"
const ARENA_PATH := "res://scenes/Main.tscn"
const LEVEL_1_PATH := "res://scenes/Level1.tscn"
const LEVEL_2_PATH := "res://scenes/Level2.tscn"

# --- Styling ---
## Effects Pokemon.gd spawns. Preloaded rather than referenced by class_name:
## a global class is only visible once Godot has rescanned, so a freshly added
## one makes every script that names it fail to parse until the editor catches
## up — which silently took the whole simulation down once.
const HEAL_AURA := preload("res://scripts/ui/HealAura.gd")
const EVOLUTION_SHIELD := preload("res://scripts/ui/EvolutionShield.gd")

const PIXEL_THEME := preload("res://assets/themes/pixel_theme.tres")
const PIXEL_FONT := preload("res://assets/fonts/PressStart2P-Regular.ttf")

# --- Sprites ---
const POKEBALL_TEXTURE := preload("res://assets/pokemon_sprites/poke.png")

const SPRITE_ROOT := "res://assets/pokemon_sprites/"

## Web-facing icon URL, served by the Node server from the same assets folder.
const ICON_URL_ROOT := "/assets/pokemon_sprites/"


## SpriteFrames for a species, or null when that species has no generated
## resources yet. Callers must null-check — an incomplete asset pipeline is a
## normal state, not an error.
static func sprite_frames_for(pokemon_id: String) -> SpriteFrames:
	var path := SPRITE_ROOT + pokemon_id + "/sprite_frames.tres"
	if not ResourceLoader.exists(path):
		return null
	return load(path) as SpriteFrames


static func icon_for(pokemon_id: String) -> Texture2D:
	var path := SPRITE_ROOT + pokemon_id + "/icon.png"
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


## URL the web spectator UI uses to show this species. Not a res:// path.
static func icon_url_for(pokemon_id: String) -> String:
	return ICON_URL_ROOT + pokemon_id + "/icon.png"

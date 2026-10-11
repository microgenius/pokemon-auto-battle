extends Node
## Autoload: player preferences and match configuration, persisted to disk.
##
## Responsibility split with Global.gd:
##   Settings.gd — things the player chooses. Survives restarts.
##   Global.gd   — static game data (species DB, attacks, type chart) and
##                 per-session state that must NOT be persisted.
##
## Anything added here should be player-facing configuration. Runtime state
## belongs in Global or in the node that owns it.

const CONFIG_PATH := "user://settings.cfg"
const DEFAULT_SERVER_URL := "ws://127.0.0.1:3000"
const ENV_SERVER_URL := "AUTOBATTLE_SERVER_URL"
## Shared secret the server checks before granting the host role. Only needed
## when the server sets AUTOBATTLE_HOST_TOKEN; a local server accepts a local host
## without one. Read from the environment so the secret never lands in
## settings.cfg.
const ENV_HOST_TOKEN := "AUTOBATTLE_HOST_TOKEN"

const MIN_ROSTER_SIZE := 3
const MAX_ROSTER_SIZE := 6

const DEFAULT_ROSTER: Array[String] = ["0001", "0004", "0007", "0063", "0092"]
const DEFAULT_MAP_PATH := "res://scenes/Level1.tscn"

## Windowed sizes offered in the menu, in dropdown order. The index one past the
## end of this list means fullscreen — see fullscreen_index().
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
]
## Kept beside RESOLUTIONS so the labels cannot drift out of sync with the sizes.
const RESOLUTION_LABELS: Array[String] = [
	"1280x720 (HD)",
	"1600x900",
	"1920x1080 (Full HD)",
]
const FULLSCREEN_LABEL := "Tam Ekran (Fullscreen)"
## Matches window_width_override / window_height_override in project.godot.
const DEFAULT_RESOLUTION_INDEX := 2

## Emitted after values change from disk or a bulk edit, so open UI can refresh.
signal settings_changed

# --- Simulation tuning (percentages, 0.0 - 100.0) ---
var prob_direction_change: float = 40.0   ## Chance to pick a new heading
var prob_attack_decision: float = 85.0    ## Chance to actually fire on cooldown
var prob_predictive_aim: float = 40.0     ## Chance to lead the target
var prob_perfect_aim: float = 10.0        ## Chance a led shot becomes Sharp Eye
var arena_hp_multiplier: float = 3.0      ## Stretches match length
var developer_mode: bool = false          ## Click a Pokemon mid-match to inspect

# --- Match configuration ---
var selected_pokemons: Array[String] = DEFAULT_ROSTER.duplicate()
var selected_map_path: String = DEFAULT_MAP_PATH

# --- Display ---
## Index into RESOLUTIONS, or fullscreen_index() for fullscreen.
var resolution_index: int = DEFAULT_RESOLUTION_INDEX

# --- Networking ---
## Base server address, without the role query string. NetworkManager appends it.
var server_url: String = DEFAULT_SERVER_URL


func _ready() -> void:
	load_settings()
	apply_resolution()


func fullscreen_index() -> int:
	return RESOLUTIONS.size()


## Pushes resolution_index onto the actual window. Called on startup so a saved
## choice survives a restart, and again whenever the menu changes it.
func apply_resolution() -> void:
	if resolution_index >= RESOLUTIONS.size():
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		return

	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(RESOLUTIONS[resolution_index])
	_center_window()


## window_set_size grows from the top-left corner, so picking a size close to
## the display's can push the title bar off-screen. Re-centre on the usable area.
func _center_window() -> void:
	var usable := DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var window_size := DisplayServer.window_get_size()
	DisplayServer.window_set_position(usable.position + (usable.size - window_size) / 2)


## Resolution order: environment variable > saved config > built-in default.
## The env var wins so a match can be pointed at another host without touching
## the saved config: AUTOBATTLE_SERVER_URL=ws://10.0.0.5:3000 godot ...
func get_host_socket_url() -> String:
	var base := server_url
	var from_env := OS.get_environment(ENV_SERVER_URL)
	if from_env != "":
		base = from_env
	base = base.strip_edges().trim_suffix("/")
	if base == "":
		base = DEFAULT_SERVER_URL

	var url := base + "/?role=host"
	var token := OS.get_environment(ENV_HOST_TOKEN).strip_edges()
	if token != "":
		url += "&token=" + token.uri_encode()
	return url


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		# No saved settings yet (first launch) — defaults already apply.
		return

	prob_direction_change = config.get_value("simulation", "prob_direction_change", prob_direction_change)
	prob_attack_decision = config.get_value("simulation", "prob_attack_decision", prob_attack_decision)
	prob_predictive_aim = config.get_value("simulation", "prob_predictive_aim", prob_predictive_aim)
	prob_perfect_aim = config.get_value("simulation", "prob_perfect_aim", prob_perfect_aim)
	arena_hp_multiplier = config.get_value("simulation", "arena_hp_multiplier", arena_hp_multiplier)
	developer_mode = config.get_value("simulation", "developer_mode", developer_mode)

	selected_map_path = config.get_value("match", "selected_map_path", selected_map_path)
	# ConfigFile hands back an untyped Array; copy into the typed one element by
	# element so an edited config file cannot corrupt the roster's type.
	var saved_roster: Array = config.get_value("match", "selected_pokemons", [])
	if saved_roster.size() >= MIN_ROSTER_SIZE:
		var roster: Array[String] = []
		for entry in saved_roster:
			roster.append(str(entry))
		selected_pokemons = roster

	resolution_index = clampi(
		int(config.get_value("display", "resolution_index", resolution_index)),
		0,
		fullscreen_index()
	)

	server_url = config.get_value("network", "server_url", server_url)

	settings_changed.emit()


func save_settings() -> void:
	var config := ConfigFile.new()

	config.set_value("simulation", "prob_direction_change", prob_direction_change)
	config.set_value("simulation", "prob_attack_decision", prob_attack_decision)
	config.set_value("simulation", "prob_predictive_aim", prob_predictive_aim)
	config.set_value("simulation", "prob_perfect_aim", prob_perfect_aim)
	config.set_value("simulation", "arena_hp_multiplier", arena_hp_multiplier)
	config.set_value("simulation", "developer_mode", developer_mode)

	config.set_value("match", "selected_pokemons", selected_pokemons)
	config.set_value("match", "selected_map_path", selected_map_path)

	config.set_value("display", "resolution_index", resolution_index)

	config.set_value("network", "server_url", server_url)

	var err := config.save(CONFIG_PATH)
	if err != OK:
		push_warning("Settings: could not write %s (error %d)" % [CONFIG_PATH, err])


func reset_to_defaults() -> void:
	prob_direction_change = 40.0
	prob_attack_decision = 85.0
	prob_predictive_aim = 40.0
	prob_perfect_aim = 10.0
	arena_hp_multiplier = 3.0
	developer_mode = false
	selected_pokemons = DEFAULT_ROSTER.duplicate()
	selected_map_path = DEFAULT_MAP_PATH
	resolution_index = DEFAULT_RESOLUTION_INDEX
	server_url = DEFAULT_SERVER_URL
	save_settings()
	settings_changed.emit()

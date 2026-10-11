extends Node
class_name GameManager
## Owns match flow: load the map, spawn the roster, run the countdown, track
## eliminations, decide the winner, and relay events to the server.
##
## Presentation lives in scripts/ui/ — this node coordinates those components but
## does not build UI itself. That split is why the file is a third of its former
## size: it used to construct the event log, the bet results screen and the
## developer inspector inline, roughly 400 lines of Control wiring mixed into the
## game loop.

@export var pokeball_scene: PackedScene

# --- Scene references (unique names, see Main.tscn) ---
@onready var _ui: CanvasLayer = %UI
@onready var _entities: Node2D = %Entities
@onready var _camera: Camera2D = %Camera2D
@onready var _scoreboard: Scoreboard = %Scoreboard
@onready var _scoreboard_panel: PanelContainer = %ScoreboardPanel
@onready var _toggle_score_button: Button = %ToggleScoreButton
@onready var _countdown_label: Label = %CountdownLabel
@onready var _pause_label: Label = %PauseLabel
@onready var _end_game_screen: CenterContainer = %EndGameScreen
@onready var _end_game_buttons: VBoxContainer = %EndGameButtons
@onready var _winner_label: Label = %WinnerText
@onready var _reset_button: Button = %ResetButton
@onready var _menu_button: Button = %MenuButton
@onready var _replay_button: Button = %ReplayButton
@onready var _end_menu_button: Button = %EndMenuButton
@onready var _stats_button: Button = %StatsButton
@onready var _stats_panel: ColorRect = %StatsPanel
@onready var _stats_list: VBoxContainer = %StatsList
@onready var _close_stats_button: Button = %CloseStatsButton

const LIVE_STATS_INTERVAL := 3.0
const COUNTDOWN_FROM := 3
const SPAWN_RADIUS_RATIO := 0.4
const FIREWORK_COUNT := 15
const FIREWORK_INTERVAL := 0.4
const DEV_CLICK_RADIUS := 40.0
const BET_RESULTS_BUTTON_TEXT := "Bahis Sonuçları"

## Per-roster-slot colours, used to tint names in the event log.
const PALETTE := ["#FF5555", "#5555FF", "#55FF55", "#FFFF55", "#FF55FF", "#FFAA55"]

var pokemon_colors: Dictionary = {}

var is_game_over := false
var current_level: Level = null
var spawn_area := Rect2(100, 100, 1080, 1080)

var death_counter := 0
var all_match_stats: Array = []  ## of PokemonMatchStats

# Names are for the log and the screen; aliases are what the server settles on.
var first_blood_pokemon := ""
var first_blood_alias := ""
var first_blood_victim := ""
var first_blood_announced := false
var first_hit_pokemon := ""
var first_hit_alias := ""
var first_hit_announced := false

var _event_log: EventLog
var _dev_panel: DevStatsPanel
var _live_stats_timer: Timer


# ---------------------------------------------------------------- lifecycle

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

	_assign_roster_colors()
	_apply_theme()
	_build_event_log()
	_start_live_stats_timer()
	_wire_buttons()
	_connect_network()

	_end_game_screen.visible = false
	_countdown_label.visible = false

	load_selected_map()
	await get_tree().create_timer(0.5).timeout
	start_game()


## Slot identity for roster position `index`, matching what Lobby.gd broadcasts.
## Stable across evolution, and unique even if the same species is picked twice.
static func alias_for_slot(index: int) -> String:
	return "candidate%d" % (index + 1)


func _assign_roster_colors() -> void:
	for i in Settings.selected_pokemons.size():
		pokemon_colors[alias_for_slot(i)] = PALETTE[i % PALETTE.size()]


func color_for(alias: String) -> String:
	return pokemon_colors.get(alias, "#FFFFFF")


func _apply_theme() -> void:
	for child in _ui.get_children():
		if child is Control:
			child.theme = GameResources.PIXEL_THEME


func _build_event_log() -> void:
	_event_log = EventLog.new()
	_ui.add_child(_event_log)


func _start_live_stats_timer() -> void:
	_live_stats_timer = Timer.new()
	_live_stats_timer.wait_time = LIVE_STATS_INTERVAL
	_live_stats_timer.timeout.connect(_broadcast_live_stats)
	add_child(_live_stats_timer)


func _wire_buttons() -> void:
	_reset_button.pressed.connect(_on_reset_pressed)
	_menu_button.pressed.connect(_on_menu_pressed)
	_replay_button.pressed.connect(_on_reset_pressed)
	_end_menu_button.pressed.connect(_on_menu_pressed)
	_stats_button.pressed.connect(_on_stats_pressed)
	_close_stats_button.pressed.connect(func(): _stats_panel.visible = false)
	_toggle_score_button.pressed.connect(_on_toggle_scoreboard)


func _connect_network() -> void:
	var nm := get_node_or_null("/root/NetworkManager")
	if not nm:
		return
	if not nm.emote_received.is_connected(_on_emote_received):
		nm.emote_received.connect(_on_emote_received)
	if not nm.bet_results_received.is_connected(_on_bet_results_received):
		nm.bet_results_received.connect(_on_bet_results_received)
	if not nm.heal_requested.is_connected(_on_heal_requested):
		nm.heal_requested.connect(_on_heal_requested)


# ---------------------------------------------------------------- match setup

func load_selected_map() -> void:
	var map_scene := load(Settings.selected_map_path)
	if not map_scene:
		push_error("GameManager: could not load map " + Settings.selected_map_path)
		return

	current_level = map_scene.instantiate()
	get_parent().call_deferred("add_child", current_level)
	get_parent().call_deferred("move_child", current_level, 0)

	if "spawn_area" in current_level:
		spawn_area = current_level.spawn_area

	if is_instance_valid(_camera):
		_camera.position = spawn_area.get_center()
		_countdown_label.pivot_offset = get_viewport().get_visible_rect().size * 0.5


func start_game() -> void:
	spawn_pokemons_geometrically()
	await _run_countdown()
	if _live_stats_timer:
		_live_stats_timer.start()


func spawn_pokemons_geometrically() -> void:
	var roster := Settings.selected_pokemons
	if roster.is_empty():
		push_error("GameManager: roster is empty, nothing to spawn")
		return

	var center := spawn_area.get_center()
	var radius: float = minf(spawn_area.size.x, spawn_area.size.y) * SPAWN_RADIUS_RATIO

	for i in roster.size():
		var pokemon := GameResources.POKEMON_SCENE.instantiate()
		pokemon.alias = alias_for_slot(i)
		pokemon.assigned_id = roster[i]
		var angle := (float(i) / roster.size()) * TAU
		pokemon.position = center + Vector2(cos(angle), sin(angle)) * radius
		pokemon.game_manager = self
		_entities.add_child(pokemon)

	_scoreboard.call_deferred("refresh_now")


func _run_countdown() -> void:
	_countdown_label.visible = true

	for i in range(COUNTDOWN_FROM, 0, -1):
		_countdown_label.text = str(i)
		_pop_countdown_label()
		await get_tree().create_timer(1.0).timeout

	_countdown_label.text = "SAVAŞ!"
	_countdown_label.modulate = Color.GOLD
	_countdown_label.scale = Vector2(0.5, 0.5)

	var tween := get_tree().create_tween()
	tween.tween_property(_countdown_label, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(_countdown_label, "modulate:a", 0.0, 0.5).set_delay(0.5)


func _pop_countdown_label() -> void:
	_countdown_label.scale = Vector2(0.5, 0.5)
	var tween := get_tree().create_tween()
	tween.tween_property(_countdown_label, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


# ---------------------------------------------------------------- events

## Appends a BBCode line to the combat log. Kept on GameManager because every
## Pokemon already holds a reference to it.
func log_event(bbcode: String) -> void:
	if _event_log:
		_event_log.add_entry(bbcode)


## Coalesced scoreboard update. Safe to call on every hit.
func request_scoreboard_refresh() -> void:
	if not is_game_over and is_instance_valid(_scoreboard):
		_scoreboard.request_refresh()


func register_first_hit(shooter: Pokemon, target: Pokemon) -> void:
	if first_hit_announced or not is_instance_valid(shooter) or not is_instance_valid(target):
		return

	first_hit_pokemon = shooter.pokemon_name
	first_hit_alias = shooter.alias
	first_hit_announced = true

	_send({
		"type": "FIRST_HIT",
		"attacker": first_hit_alias,
		"attacker_name": first_hit_pokemon,
		"target": target.alias,
		"target_name": target.pokemon_name,
	})
	log_event("[color=orange]İLK VURUŞ![/color] [color=%s]%s[/color] ilk isabeti [color=%s]%s[/color] üzerinde gerçekleştirdi!" % [
		color_for(shooter.alias), first_hit_pokemon,
		color_for(target.alias), target.pokemon_name,
	])


func register_death(pokemon: Pokemon, killer: Pokemon = null) -> void:
	death_counter += 1

	var stats := PokemonMatchStats.from_pokemon(pokemon)
	stats.death_order = death_counter
	all_match_stats.append(stats)

	_scoreboard.register_death(pokemon, death_counter)
	_announce_first_blood(pokemon, killer)


func _announce_first_blood(victim: Pokemon, killer: Pokemon) -> void:
	# First blood means the first *kill*, so an unattributed death does not count
	# and the next one gets the honour. A shooter that dies while its own shot is
	# still in flight leaves the victim with no killer; the old code fired anyway,
	# scanned for anyone with a score, found nobody, and settled the whole market
	# against "" — every bet on it lost.
	if first_blood_announced or not is_instance_valid(killer):
		return

	first_blood_pokemon = killer.pokemon_name
	first_blood_alias = killer.alias

	first_blood_victim = victim.pokemon_name
	first_blood_announced = true

	_send({
		"type": "FIRST_BLOOD",
		"killer": first_blood_alias,
		"killer_name": first_blood_pokemon,
		"victim": victim.alias,
		"victim_name": first_blood_victim,
	})
	log_event("[color=red]İLK KAN![/color] %s, %s adlı hedefi ilk olarak eledi!" % [first_blood_pokemon, first_blood_victim])


func on_pokemon_died(_dead_pokemon: Pokemon) -> void:
	if is_game_over:
		return
	_scoreboard.call_deferred("refresh_now")
	call_deferred("check_win_condition")


func check_win_condition() -> void:
	if is_game_over:
		return

	var remaining: Array = []
	for p in get_tree().get_nodes_in_group("pokemon"):
		if not p.is_queued_for_deletion():
			remaining.append(p)

	if remaining.size() <= 1:
		end_game(remaining[0] if remaining.size() > 0 else null)


# ---------------------------------------------------------------- match end

func end_game(winner: Pokemon) -> void:
	if _live_stats_timer:
		_live_stats_timer.stop()
	is_game_over = true
	_end_game_screen.visible = true

	if not winner:
		_winner_label.text = "Berabere!"
		_stats_button.visible = true
		return

	var winner_stats := PokemonMatchStats.from_pokemon(winner)
	all_match_stats.append(winner_stats)

	_report_results(winner)
	_present_winner(winner)
	_stats_button.visible = true
	spawn_fireworks_around(winner)


func _report_results(winner: Pokemon) -> void:
	_send({"type": "MATCH_END", "winner": winner.alias, "winner_name": winner.pokemon_name})
	_send({
		"type": "MATCH_RESULTS",
		"winner": winner.alias,
		"winner_name": winner.pokemon_name,
		"first_blood": first_blood_alias,
		"first_hit": first_hit_alias,
		"all_stats": PokemonMatchStats.list_to_dicts(all_match_stats),
	})


func _present_winner(winner: Pokemon) -> void:
	winner.start_celebration()

	# Park the winner near the top so the result text below stays readable.
	winner.global_position = Vector2(
		spawn_area.get_center().x,
		spawn_area.position.y + spawn_area.size.y * 0.15
	)

	_winner_label.text = "Kazanan:\n" + winner.pokemon_name + _winning_bettors_suffix(winner)
	_winner_label.modulate = winner.sprite.modulate
	_winner_label.add_theme_font_size_override("font_size", 48)


func _winning_bettors_suffix(winner: Pokemon) -> String:
	var nm := get_node_or_null("/root/NetworkManager")
	if not nm or not nm.is_connected_to_server:
		return ""

	# Keyed by alias, so this no longer has to case-fold names and no longer
	# misses a winner that evolved after the bets were placed.
	var bettors = nm.current_bets.get(winner.alias, [])
	if typeof(bettors) == TYPE_ARRAY and bettors.size() > 0:
		return "\n\nSeyirciler: " + ", ".join(PackedStringArray(bettors))
	return ""


func spawn_fireworks_around(winner: Pokemon) -> void:
	for _i in FIREWORK_COUNT:
		await get_tree().create_timer(FIREWORK_INTERVAL).timeout
		if not is_instance_valid(winner) or not is_inside_tree():
			return

		var firework := GameResources.FIREWORK_SCENE.instantiate()
		firework.global_position = Vector2(
			randf_range(spawn_area.position.x + 200.0, spawn_area.position.x + spawn_area.size.x - 200.0),
			randf_range(spawn_area.position.y + 150.0, spawn_area.position.y + spawn_area.size.y * 0.6)
		)
		get_parent().add_child(firework)


# ---------------------------------------------------------------- networking

func _send(payload: Dictionary) -> void:
	var nm := get_node_or_null("/root/NetworkManager")
	if nm and nm.is_connected_to_server:
		nm.send_message(payload)


func _broadcast_live_stats() -> void:
	var nm := get_node_or_null("/root/NetworkManager")
	if not nm or not nm.is_connected_to_server:
		return

	var stats: Array = []
	for p in get_tree().get_nodes_in_group("pokemon"):
		if p.is_queued_for_deletion():
			continue
		stats.append({
			"alias": p.alias,
			"name": p.pokemon_name,
			"hp": round(p.current_hp),
			"max_hp": round(p.max_hp),
			"level": p.level,
			"kills": p.score,
			"hits": p.successful_hits,
			"attacks": p.total_attacks,
			"dodges": p.total_dodges,
			"criticals": p.total_criticals,
			"has_evolved": p.has_evolved,
			"evolution_count": p.evolution_count,
			"evolution_complete": p.evolves_to.is_empty(),
			"primary_type": p.primary_type,
		})

	nm.send_message({"type": "LIVE_STATS", "stats": stats, "alive_count": stats.size()})


func _on_emote_received(username: String, target_alias: String, emote_type: String) -> void:
	# The alias survives evolution, so this no longer has to look the fighter's
	# original species name out of the database and case-fold both candidates.
	for child in _entities.get_children():
		if child is Pokemon and child.alias == target_alias:
			EmotePopup.spawn_on(child, username, emote_type)
			return


## The server has already taken the points; it needs to know whether the heal
## landed so it can refund when it did not.
func _on_heal_requested(id: int, alias: String, amount: float, username: String) -> void:
	var healed := 0.0
	for child in _entities.get_children():
		if child is Pokemon and child.alias == alias:
			healed = child.heal(amount, username)
			break

	_send({"type": "HEAL_RESULT", "id": id, "ok": healed > 0.0, "healed": healed})


func _on_bet_results_received(results: Dictionary) -> void:
	if not is_instance_valid(_end_game_buttons):
		return

	# Guard against a duplicate button if results arrive twice.
	for child in _end_game_buttons.get_children():
		if child is Button and child.text == BET_RESULTS_BUTTON_TEXT:
			child.queue_free()

	var button := Button.new()
	button.text = BET_RESULTS_BUTTON_TEXT
	button.add_theme_font_size_override("font_size", 32)
	button.pressed.connect(func(): _ui.add_child(BetResultsPanel.create(results)))
	_end_game_buttons.add_child(button)


# ---------------------------------------------------------------- input / UI

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") or (event is InputEventKey and event.keycode == KEY_P and event.pressed and not event.echo):
		toggle_pause()

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if Settings.developer_mode:
			var pokemon := _pokemon_under_cursor()
			if pokemon:
				show_dev_stats(pokemon)


func _pokemon_under_cursor() -> Pokemon:
	var mouse_pos := _camera.get_global_mouse_position() if _camera else get_viewport().get_mouse_position()
	var closest: Pokemon = null
	var closest_dist := DEV_CLICK_RADIUS

	for child in _entities.get_children():
		if not (child is Pokemon):
			continue
		var pokemon := child as Pokemon
		var dist := pokemon.global_position.distance_to(mouse_pos)
		if dist < closest_dist:
			closest_dist = dist
			closest = pokemon

	return closest


func show_dev_stats(pokemon: Pokemon) -> void:
	if not Settings.developer_mode:
		return

	if not get_tree().paused:
		toggle_pause()

	if is_instance_valid(_dev_panel):
		_dev_panel.queue_free()

	_dev_panel = DevStatsPanel.create(pokemon)
	_dev_panel.closed.connect(func():
		if get_tree().paused:
			toggle_pause()
	)
	_ui.add_child(_dev_panel)


func toggle_pause() -> void:
	if is_game_over:
		return
	var tree := get_tree()
	tree.paused = not tree.paused
	if _pause_label:
		_pause_label.visible = tree.paused


func _on_toggle_scoreboard() -> void:
	_scoreboard_panel.visible = not _scoreboard_panel.visible
	_toggle_score_button.text = "Skor Goster" if not _scoreboard_panel.visible else "Skor Gizle"


func _on_stats_pressed() -> void:
	MatchStatsPanel.populate(_stats_list, all_match_stats)
	_stats_panel.visible = true


func _on_reset_pressed() -> void:
	get_tree().change_scene_to_file(GameResources.LOBBY_PATH)


func _on_menu_pressed() -> void:
	# Walking out mid-match means nothing will ever settle, so the server has to
	# hand the stakes back. Restarting into the lobby is covered by LOBBY_UPDATE.
	if not is_game_over:
		_send({"type": "MATCH_ABORTED"})
	get_tree().change_scene_to_file(GameResources.MAIN_MENU_PATH)

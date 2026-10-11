extends CharacterBody2D
class_name Pokemon
## A single fighter: stats, wandering AI, combat, levelling and evolution.
##
## Presentation helpers it used to own inline (floating combat text, dodge
## afterimages) now live in scripts/ui/, so this file is about the simulation.

enum State { WANDER, CELEBRATING, HATCHING, EVOLVING }

const MAX_LEVEL := 50
const SPECIAL_ATTACK_TIER_2_LEVEL := 14
const SPECIAL_ATTACK_TIER_3_LEVEL := 26

const DODGE_DASH_DURATION := 0.3
const DODGE_SPEED_MULTIPLIER := 5.0
const COLLISION_TURN_COOLDOWN := 0.5

const CRIT_DAMAGE_MULTIPLIER := 1.5
const DAMAGE_ROLL_MIN := 0.85
const DAMAGE_ROLL_MAX := 1.0
const DEFENSE_CONSTANT := 40.0

# Experience awards.
#
# Passive XP is the same for everyone, so it is a shared clock, not a source of
# difference. At 200/s it was 95% of all XP earned and the whole roster levelled
# in lockstep — a match was decided by base stats and RNG before anyone landed a
# shot. The totals below keep an average fighter on the same pace (~29k XP over
# two minutes, as before) while moving half of it onto things you have to earn.
const EXP_PER_SECOND := 100.0
const EXP_ON_HIT_DEALT := 1000.0
const EXP_ON_DODGE := 1500.0
const EXP_ON_SHARP_EYE := 3000.0
const EXP_ON_KILL := 5000.0

# Hatching sequence timings
const BOUNCE_LOOPS := 3
const BOUNCE_HALF_DURATION := 0.5
const SHAKE_LOOPS := 4
const SHAKE_HALF_DURATION := 0.15

## Animation suffixes indexed by movement octant, starting at "facing right" and
## going clockwise.
const DIRECTION_OCTANTS := ["Right", "BottomRight", "Down", "BottomLeft", "Left", "TopLeft", "Up", "TopRight"]

@export var speed: float = 50.0
@export var max_hp: float = 100.0
@export var change_direction_min_time: float = 2.0
@export var change_direction_max_time: float = 5.0

@onready var attack_timer: Timer = $AttackCooldown
@onready var sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var pokeball_sprite: Sprite2D = $PokeballSprite
@onready var health_bar: ProgressBar = $InfoBox/HealthBar
@onready var info_box: HBoxContainer = $InfoBox

var move_direction := Vector2.ZERO
var current_state: State = State.HATCHING
var direction_time_left := 0.0
var dodge_time_left := 0.0

var pokemon_name := ""
var score := 0
var current_hp := 100.0
var game_manager: Node = null

var total_attacks := 0
var successful_hits := 0
var total_dodges := 0
var total_criticals := 0

## Stable identity for this roster slot, e.g. "candidate1". Assigned once at
## spawn and never reassigned — unlike the species id or the display name, it
## survives evolution untouched. Everything that has to match a fighter across
## the wire keys on this; names are for the screen only.
var alias := ""
var assigned_id := ""
var current_pokemon_id := ""
var current_anim_action := "Walk"

# --- RPG stats ---
var level := 1
var level_at_last_evolution := -1
var current_exp := 0.0

var iv_hp := 0
var iv_atk := 0
var iv_def := 0
var iv_sp_atk := 0
var iv_sp_def := 0
var iv_spd := 0

var base_hp := 50.0
var base_atk := 50.0
var base_def := 50.0
var base_sp_atk := 50.0
var base_sp_def := 50.0
var base_spd := 50.0

var atk_stat := 5.0
var def_stat := 5.0
var sp_atk_stat := 5.0
var sp_def_stat := 5.0
var spd_stat := 5.0

var primary_type := "normal"
var secondary_type := ""
var max_stages := 1
var evolves_to: Array = []
var evolution_level := -1
var has_evolved := false
var evolution_count := 0

var _ghost_trail: GhostTrail


# ---------------------------------------------------------------- setup

func _ready() -> void:
	add_to_group("pokemon")

	current_state = State.HATCHING
	sprite.visible = false
	pokeball_sprite.visible = true

	current_pokemon_id = assigned_id if assigned_id != "" else Settings.selected_pokemons.pick_random()

	_roll_ivs()
	_load_species_data(current_pokemon_id)
	calculate_stats()
	_restore_to_full_health()
	sprite.sprite_frames = GameResources.sprite_frames_for(current_pokemon_id)

	_spawn_ghost_trail()
	_play_hatch_sequence()


## IVs are cubed to skew the distribution toward low rolls, so a lucky spawn is
## genuinely rare rather than uniformly likely.
func _roll_ivs() -> void:
	iv_hp = _roll_iv()
	iv_atk = _roll_iv()
	iv_def = _roll_iv()
	iv_sp_atk = _roll_iv()
	iv_sp_def = _roll_iv()
	iv_spd = _roll_iv()


func _roll_iv() -> int:
	return int(floor(31.0 * pow(randf(), 3)))


## Copies one species record into this entity's stat block. Called on spawn and
## again on every evolution — it used to be duplicated verbatim in both places,
## which is how base_spd came to be read with a default in one copy and not the
## other.
func _load_species_data(pokemon_id: String) -> void:
	if not get_node_or_null("/root/Global"):
		return

	var db: Dictionary = get_node("/root/Global").pokemon_db
	if not db.has(pokemon_id):
		return

	var data: Dictionary = db[pokemon_id]
	pokemon_name = str(data["name"]).capitalize()
	base_hp = float(data.get("base_hp", 50.0))
	base_atk = float(data.get("base_atk", 50.0))
	base_def = float(data.get("base_def", 50.0))
	base_sp_atk = float(data.get("base_sp_atk", 50.0))
	base_sp_def = float(data.get("base_sp_def", 50.0))
	base_spd = float(data.get("base_spd", 50.0))
	primary_type = data.get("primary_type", "normal")
	secondary_type = data.get("secondary_type", "")
	max_stages = data.get("max_stages", 1)
	evolves_to = data.get("evolves_to", [])
	evolution_level = data.get("evolution_level", -1)


func calculate_stats() -> void:
	var hp_multiplier: float = Settings.arena_hp_multiplier if get_node_or_null("/root/Settings") else 3.0
	# HP uses the mainline formula (+level +10); every other stat uses the flat +5
	# variant, so it cannot share _stat_formula.
	max_hp = (floor(0.01 * (2.0 * base_hp + float(iv_hp)) * float(level)) + float(level) + 10.0) * hp_multiplier

	atk_stat = _stat_formula(base_atk, iv_atk)
	def_stat = _stat_formula(base_def, iv_def)
	sp_atk_stat = _stat_formula(base_sp_atk, iv_sp_atk)
	sp_def_stat = _stat_formula(base_sp_def, iv_sp_def)
	spd_stat = _stat_formula(base_spd, iv_spd)

	if health_bar:
		health_bar.max_value = max_hp


func _stat_formula(base: float, iv: int) -> float:
	return floor(0.01 * (2.0 * base + float(iv)) * float(level)) + 5.0


func _restore_to_full_health() -> void:
	current_hp = max_hp
	if health_bar:
		health_bar.max_value = max_hp
		health_bar.value = current_hp


func _spawn_ghost_trail() -> void:
	_ghost_trail = GhostTrail.new()
	# Parented to the arena, not to this node, so afterimages stay where they
	# were dropped instead of following the dash.
	get_parent().add_child.call_deferred(_ghost_trail)


# ---------------------------------------------------------------- hatching

func _play_hatch_sequence() -> void:
	pokeball_sprite.modulate = Color.WHITE
	pokeball_sprite.scale = Vector2(3.0, 3.0)

	var bounce := get_tree().create_tween()
	bounce.set_loops(BOUNCE_LOOPS)
	bounce.tween_property(pokeball_sprite, "position:y", -50.0, BOUNCE_HALF_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	bounce.tween_property(pokeball_sprite, "position:y", 0.0, BOUNCE_HALF_DURATION).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)

	var next := get_tree().create_tween()
	next.tween_interval(BOUNCE_LOOPS * BOUNCE_HALF_DURATION * 2.0)
	next.tween_callback(start_shake_animation)


func start_shake_animation() -> void:
	var shake := get_tree().create_tween()
	shake.set_loops(SHAKE_LOOPS)
	shake.tween_property(pokeball_sprite, "rotation_degrees", 15.0, SHAKE_HALF_DURATION)
	shake.tween_property(pokeball_sprite, "rotation_degrees", -15.0, SHAKE_HALF_DURATION)

	var next := get_tree().create_tween()
	next.tween_interval(SHAKE_LOOPS * SHAKE_HALF_DURATION * 2.0)
	next.tween_callback(_on_hatch_complete)


func _on_hatch_complete() -> void:
	_spawn_hatch_flash()

	pokeball_sprite.visible = false
	sprite.visible = true
	sprite.scale = Vector2(0.1, 0.1)

	var pop := get_tree().create_tween()
	pop.tween_property(sprite, "scale", Vector2(1.25, 1.25), 0.4).set_trans(Tween.TRANS_BOUNCE)

	current_state = State.WANDER
	info_box.visible = true
	pick_random_direction()
	start_random_attack_timer()
	update_animation("Walk")


func _spawn_hatch_flash() -> void:
	var flash := Sprite2D.new()
	flash.texture = GameResources.POKEBALL_TEXTURE
	flash.global_position = global_position
	flash.modulate = Color(2.0, 2.0, 2.0, 1.0)
	flash.scale = Vector2(3.0, 3.0)
	get_tree().current_scene.add_child(flash)

	var tween := get_tree().create_tween()
	tween.set_parallel(true)
	tween.tween_property(flash, "scale", Vector2(10.0, 10.0), 0.3)
	tween.tween_property(flash, "modulate:a", 0.0, 0.3)
	tween.chain().tween_callback(flash.queue_free)


# ---------------------------------------------------------------- movement

func _physics_process(delta: float) -> void:
	if current_state != State.WANDER:
		return

	gain_exp(EXP_PER_SECOND * delta)

	var current_speed := speed
	if dodge_time_left > 0.0:
		dodge_time_left -= delta
		current_speed *= DODGE_SPEED_MULTIPLIER
		_emit_dodge_afterimage(delta)

	velocity = move_direction * current_speed
	move_and_slide()

	_update_heading(delta)


func _emit_dodge_afterimage(delta: float) -> void:
	if not is_instance_valid(_ghost_trail) or not sprite.sprite_frames:
		return
	var frame_texture := sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	_ghost_trail.try_emit(delta, frame_texture, global_position, sprite.modulate, sprite.scale)


func _update_heading(delta: float) -> void:
	direction_time_left -= delta
	if direction_time_left <= 0.0:
		if (randf() * 100.0) <= Settings.prob_direction_change:
			pick_random_direction()
			update_animation(current_anim_action)
		else:
			direction_time_left = randf_range(change_direction_min_time, change_direction_max_time)

	# Bounce off geometry, but only if we have been on this heading a while —
	# otherwise a corner produces a turn every single frame.
	if get_slide_collision_count() > 0 and direction_time_left > COLLISION_TURN_COOLDOWN:
		pick_random_direction()
		direction_time_left = COLLISION_TURN_COOLDOWN
		update_animation(current_anim_action)


func pick_random_direction() -> void:
	var angle := randf() * TAU
	move_direction = Vector2(cos(angle), sin(angle))
	direction_time_left = randf_range(change_direction_min_time, change_direction_max_time)


func update_animation(action: String) -> void:
	if not sprite.sprite_frames:
		return

	current_anim_action = action
	sprite.speed_scale = 1.0

	var anim_name := action + "_" + _direction_suffix()
	if sprite.sprite_frames.has_animation(anim_name):
		if sprite.animation != anim_name or not sprite.is_playing():
			sprite.play(anim_name)
	elif sprite.sprite_frames.has_animation(action):
		if sprite.animation != action or not sprite.is_playing():
			sprite.play(action)


func _direction_suffix() -> String:
	var octant := int(round(8 * move_direction.angle() / TAU)) % 8
	if octant < 0:
		octant += 8
	return DIRECTION_OCTANTS[octant]


# ---------------------------------------------------------------- combat

func start_random_attack_timer() -> void:
	attack_timer.wait_time = randf_range(3.0, 8.0)
	if not attack_timer.timeout.is_connected(_on_attack_timer_timeout):
		attack_timer.timeout.connect(_on_attack_timer_timeout)
	attack_timer.start()


func _on_attack_timer_timeout() -> void:
	if current_state == State.CELEBRATING:
		return
	if (randf() * 100.0) <= Settings.prob_attack_decision:
		perform_attack()
	start_random_attack_timer()


## Move list is picked purely from the primary type and current level.
func get_current_attack() -> Dictionary:
	var db: Dictionary = {}
	if get_node_or_null("/root/Global"):
		db = get_node("/root/Global").attacks_db

	var type_key := primary_type if db.has(primary_type) else "normal"
	var moves: Array = db[type_key]

	if level >= SPECIAL_ATTACK_TIER_3_LEVEL:
		return moves[2]
	if level >= SPECIAL_ATTACK_TIER_2_LEVEL:
		return moves[1]
	return moves[0]


func perform_attack() -> void:
	if current_state != State.WANDER:
		return

	total_attacks += 1

	var target := find_nearest_enemy()
	if not target:
		return

	var attack_info := get_current_attack()
	var power := float(attack_info["power"])
	var is_special: bool = attack_info["is_special"]

	var projectile := GameResources.PROJECTILE_SCENE.instantiate()
	projectile.global_position = global_position
	projectile.target = target
	projectile.shooter = self
	projectile.attack_name = attack_info["name"]
	projectile.attack_type = primary_type
	projectile.is_special = is_special
	projectile.attack_power = power
	projectile.damage = ((sp_atk_stat if is_special else atk_stat) * power) / DEFENSE_CONSTANT

	_apply_aim(projectile, target)
	get_tree().current_scene.add_child(projectile)


func _apply_aim(projectile: Node, target: Pokemon) -> void:
	if (randf() * 100.0) > Settings.prob_predictive_aim:
		return

	# Lead the target by half a second of its current velocity.
	projectile.predicted_target_pos = target.global_position + (target.velocity * 0.5)

	if (randf() * 100.0) > Settings.prob_perfect_aim:
		return

	projectile.is_sharp_eye_shot = true
	_log("[color=%s]%s[/color] [b]SHARP EYE[/b] (Keskin Göz) tetikledi!" % [_own_color(), pokemon_name])
	gain_exp(EXP_ON_SHARP_EYE)


func find_nearest_enemy() -> Pokemon:
	var nearest: Pokemon = null
	var min_dist := INF

	for p in get_tree().get_nodes_in_group("pokemon"):
		if p == self or p.current_state != State.WANDER:
			continue
		var dist := global_position.distance_to(p.global_position)
		if dist < min_dist:
			min_dist = dist
			nearest = p

	return nearest


func get_dodge_chance() -> float:
	return clampf((spd_stat * 0.25) + 5.0, 5.0, 40.0)


## NOTE: currently informational only — criticals are driven by Sharp Eye, not
## by this roll. Tracked as a known bug.
## Chance that any given shot lands as a critical.
##
## A critical *is* a Sharp Eye shot — same roll, same counter, same damage
## multiplier. This used to return a speed-based figure that nothing in the
## simulation ever used, so the developer panel showed one number while the
## fight ran on another. Speed already decides dodging; it does not decide this.
func get_crit_chance() -> float:
	return (Settings.prob_predictive_aim / 100.0) * Settings.prob_perfect_aim


func take_damage(amount: float, shooter: Node2D = null, attack_name: String = "Saldırı", attack_type: String = "normal", is_special: bool = false, is_critical: bool = false) -> void:
	if current_state != State.WANDER:
		return

	if _try_dodge():
		return

	var effectiveness := _type_effectiveness(attack_type)
	if is_zero_approx(effectiveness):
		_report_immunity(shooter)
		return

	var actual_damage := _compute_damage(amount, is_special, is_critical, effectiveness)
	current_hp -= actual_damage
	health_bar.value = current_hp

	_report_hit(shooter, attack_name, actual_damage, is_critical, effectiveness)

	if is_instance_valid(game_manager):
		game_manager.request_scoreboard_refresh()

	if current_hp <= 0.0:
		_die(shooter)


## Restores HP from a spectator's paid heal. Returns how much actually landed,
## which is what the server bills against — a heal that overshoots max HP or
## arrives after the fighter died must not be charged in full.
func heal(amount: float, source_username: String = "") -> float:
	if current_state != State.WANDER or current_hp <= 0.0:
		return 0.0

	var restored := minf(amount, max_hp - current_hp)
	if restored <= 0.0:
		return 0.0

	current_hp += restored
	health_bar.value = current_hp

	add_child(GameResources.HEAL_AURA.new())
	FloatingText.spawn(get_tree().current_scene, global_position, "+%d" % int(restored), Color(0.95, 0.35, 0.4), -20.0)

	var who := source_username if source_username != "" else "Seyirci"
	_log("[color=%s]%s[/color], [b]%s[/b] tarafından %d HP iyileştirildi!" % [
		_own_color(), pokemon_name, who, int(restored),
	])

	if is_instance_valid(game_manager):
		game_manager.request_scoreboard_refresh()
	return restored


func _try_dodge() -> bool:
	if (randf() * 100.0) > get_dodge_chance():
		return false

	dodge_time_left = DODGE_DASH_DURATION
	pick_random_direction()
	update_animation(current_anim_action)
	total_dodges += 1
	_spawn_floating_text("DODGE", Color.WHITE)
	_log("[color=%s]%s[/color] gelen saldırıyı [b]DODGE[/b] (Atlatma) yeteneğiyle savuşturdu!" % [_own_color(), pokemon_name])
	gain_exp(EXP_ON_DODGE)
	return true


func _type_effectiveness(attack_type: String) -> float:
	if not get_node_or_null("/root/Global"):
		return 1.0

	var chart: Dictionary = get_node("/root/Global").type_chart
	if not chart.has(attack_type):
		return 1.0

	var matchups: Dictionary = chart[attack_type]
	var multiplier := 1.0
	if matchups.has(primary_type):
		multiplier *= float(matchups[primary_type])
	if secondary_type != "" and matchups.has(secondary_type):
		multiplier *= float(matchups[secondary_type])
	return multiplier


func _compute_damage(amount: float, is_special: bool, is_critical: bool, effectiveness: float) -> float:
	var defense := sp_def_stat if is_special else def_stat
	var base := (amount * DEFENSE_CONSTANT) / (DEFENSE_CONSTANT + defense)
	var roll := randf_range(DAMAGE_ROLL_MIN, DAMAGE_ROLL_MAX)
	var crit := CRIT_DAMAGE_MULTIPLIER if is_critical else 1.0
	return maxf(1.0, base * roll * crit * effectiveness)


func _report_immunity(shooter: Node2D) -> void:
	_spawn_floating_text("ETKİSİZ", Color.GRAY)
	if is_instance_valid(shooter) and shooter is Pokemon:
		_log("[color=%s]%s[/color], [color=%s]%s[/color] hedefine saldırdı ama [color=gray]hiç etkisi olmadı![/color]" % [
			_color_of(shooter), shooter.pokemon_name, _own_color(), pokemon_name,
		])


func _report_hit(shooter: Node2D, attack_name: String, damage: float, is_critical: bool, effectiveness: float) -> void:
	if not (is_instance_valid(shooter) and shooter is Pokemon):
		return

	var crit_text := " [color=yellow](Kritik Vuruş!)[/color]" if is_critical else ""
	var effect_text := ""
	if effectiveness > 1.0:
		effect_text = " [color=green](Çok Etkili!)[/color]"
		_spawn_floating_text("ÇOK ETKİLİ", Color.GREEN)
	elif effectiveness < 1.0:
		effect_text = " [color=red](Pek Etkili Değil!)[/color]"
		_spawn_floating_text("AZ ETKİLİ", Color.RED)

	_log("[color=%s]%s[/color], [b]%s[/b] ile [color=%s]%s[/color] hedefine [b]%d[/b] hasar vurdu!%s%s" % [
		_color_of(shooter), shooter.pokemon_name, attack_name,
		_own_color(), pokemon_name, round(damage), crit_text, effect_text,
	])

	shooter.gain_exp(EXP_ON_HIT_DEALT)


func _die(killer: Node2D) -> void:
	var killer_pokemon: Pokemon = killer if (is_instance_valid(killer) and killer is Pokemon) else null

	if killer_pokemon:
		killer_pokemon.score += 1
		killer_pokemon.gain_exp(EXP_ON_KILL)
		_log("[color=%s]%s[/color], [color=%s]%s[/color] adlı hedefi eledi!" % [
			_color_of(killer_pokemon), killer_pokemon.pokemon_name, _own_color(), pokemon_name,
		])
	else:
		_log("[color=%s]%s[/color] savaş dışı kaldı!" % [_own_color(), pokemon_name])

	if is_instance_valid(game_manager):
		game_manager.request_scoreboard_refresh()
		game_manager.register_death(self, killer_pokemon)
		game_manager.on_pokemon_died(self)

	_spawn_floating_text("ELIMINATED", Color.RED, -30.0)

	if is_instance_valid(_ghost_trail):
		_ghost_trail.queue_free()

	queue_free()


# ---------------------------------------------------------------- progression

func exp_to_next_level() -> float:
	return 100.0 + (float(level) * 30.0)


func gain_exp(amount: float) -> void:
	if level >= MAX_LEVEL or current_state == State.EVOLVING:
		return

	current_exp += amount
	while current_exp >= exp_to_next_level() and level < MAX_LEVEL:
		if current_state == State.EVOLVING:
			break
		current_exp -= exp_to_next_level()
		level_up()


func level_up() -> void:
	if level >= MAX_LEVEL:
		return

	level += 1
	var previous_max := max_hp
	calculate_stats()
	current_hp += max_hp - previous_max
	health_bar.value = current_hp

	_log("[color=%s]%s[/color] Level [b]%d[/b] oldu!" % [_own_color(), pokemon_name, level])

	if evolution_level != -1 and level >= evolution_level and not evolves_to.is_empty():
		if level > level_at_last_evolution:
			start_evolution()


func start_evolution() -> void:
	current_state = State.EVOLVING
	attack_timer.stop()
	velocity = Vector2.ZERO
	if sprite:
		sprite.stop()

	_add_evolution_shield()
	_log("[color=%s]%s[/color] evrim geçiriyor!" % [_own_color(), pokemon_name])

	var pulse := get_tree().create_tween()
	pulse.set_loops(6)
	pulse.tween_property(sprite, "scale", Vector2(1.5, 1.5), 0.3).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(sprite, "scale", Vector2(1.0, 1.0), 0.3).set_trans(Tween.TRANS_SINE)

	var finish := get_tree().create_tween()
	finish.tween_interval(6 * 0.6)
	finish.tween_callback(_on_evolution_complete)


func _add_evolution_shield() -> void:
	add_child(GameResources.EVOLUTION_SHIELD.new())


## True while the fighter cannot be hit. Projectiles ask this before crediting a
## hit, so a shot absorbed by the evolution bubble does not count as a landed
## one — it used to bump successful_hits and could even claim first hit.
func is_shielded() -> bool:
	return current_state == State.EVOLVING


func _on_evolution_complete() -> void:
	level_at_last_evolution = level
	has_evolved = true
	evolution_count += 1

	var shield := get_node_or_null("EvolutionShield")
	if shield:
		shield.queue_free()

	var new_id := _lookup_species_id(evolves_to.pick_random())
	if new_id != "":
		var previous_name := pokemon_name
		current_pokemon_id = new_id

		var frames := GameResources.sprite_frames_for(current_pokemon_id)
		if frames:
			sprite.sprite_frames = frames

		_load_species_data(current_pokemon_id)

		# Colours are keyed by the slot alias, which does not change here, so the
		# event log and scoreboard stay consistent with no re-registration.
		var nm := get_node_or_null("/root/NetworkManager")
		if nm:
			nm.broadcast_evolution(alias, previous_name, pokemon_name, GameResources.icon_url_for(current_pokemon_id))

		var previous_max := max_hp
		calculate_stats()
		current_hp += max_hp - previous_max
		health_bar.value = current_hp

		_log("Evrim tamamlandı! Yeni form: [color=%s][b]%s[/b][/color]" % [_own_color(), pokemon_name])

	current_state = State.WANDER
	start_random_attack_timer()
	update_animation(current_anim_action)


func _lookup_species_id(species_name: String) -> String:
	if not get_node_or_null("/root/Global"):
		return ""
	var db: Dictionary = get_node("/root/Global").pokemon_db
	for pid in db:
		if db[pid]["name"] == species_name:
			return pid
	return ""


# ---------------------------------------------------------------- celebration

func start_celebration() -> void:
	current_state = State.CELEBRATING
	attack_timer.stop()
	if is_instance_valid(info_box):
		info_box.visible = false

	move_direction = Vector2.DOWN
	update_animation("Idle")

	var tween := get_tree().create_tween()
	tween.tween_property(sprite, "scale", sprite.scale * 2.0, 0.5).set_trans(Tween.TRANS_BOUNCE)


# ---------------------------------------------------------------- helpers

func _spawn_floating_text(text: String, color: Color, y_offset: float = 0.0) -> void:
	FloatingText.spawn(get_tree().current_scene, global_position, text, color, y_offset)


func _log(bbcode: String) -> void:
	if is_instance_valid(game_manager):
		game_manager.log_event(bbcode)


func _own_color() -> String:
	if is_instance_valid(game_manager):
		return game_manager.color_for(alias)
	return "#FFFFFF"


func _color_of(other: Pokemon) -> String:
	if is_instance_valid(game_manager) and is_instance_valid(other):
		return game_manager.color_for(other.alias)
	return "#FFFFFF"

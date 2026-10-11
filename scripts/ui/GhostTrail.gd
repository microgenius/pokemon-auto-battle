class_name GhostTrail
extends Node2D
## Afterimage streak left behind by a dodge dash.
##
## The original version created a Sprite2D *and* a Tween inside _physics_process
## for every frame the dash lasted. At 60 fps a 0.3s dodge meant 18 nodes plus 18
## tweens, all allocated and freed within a third of a second, and the emission
## rate silently scaled with framerate — a 144 Hz machine produced two and a half
## times as many ghosts as a 60 Hz one.
##
## This preallocates a small ring of sprites, reuses them forever, fades them by
## hand in _process, and emits on a wall-clock interval so the effect looks the
## same regardless of framerate. Steady-state allocations during combat: zero.

const POOL_SIZE := 8
const EMIT_INTERVAL := 0.045
const FADE_TIME := 0.3
const START_ALPHA := 0.5

var _pool: Array[Sprite2D] = []
var _life: Array[float] = []
var _next_index := 0
var _emit_cooldown := 0.0
var _active_count := 0


func _ready() -> void:
	# Ghosts are world-space marks; keep them out of the emitter's transform so
	# they stay put while the Pokemon dashes away.
	top_level = true

	for _i in POOL_SIZE:
		var ghost := Sprite2D.new()
		ghost.visible = false
		add_child(ghost)
		_pool.append(ghost)
		_life.append(0.0)

	set_process(false)


## Call every physics frame while dashing; it self-throttles.
func try_emit(delta: float, texture: Texture2D, world_position: Vector2, tint: Color, sprite_scale: Vector2) -> void:
	_emit_cooldown -= delta
	if _emit_cooldown > 0.0 or texture == null:
		return
	_emit_cooldown = EMIT_INTERVAL

	var ghost := _pool[_next_index]
	if _life[_next_index] <= 0.0:
		_active_count += 1
	_life[_next_index] = FADE_TIME

	ghost.texture = texture
	ghost.global_position = world_position
	ghost.scale = sprite_scale
	ghost.modulate = Color(tint.r, tint.g, tint.b, START_ALPHA)
	ghost.visible = true

	_next_index = (_next_index + 1) % POOL_SIZE
	set_process(true)


func _process(delta: float) -> void:
	for i in POOL_SIZE:
		if _life[i] <= 0.0:
			continue

		_life[i] -= delta
		if _life[i] <= 0.0:
			_pool[i].visible = false
			_active_count -= 1
		else:
			_pool[i].modulate.a = (_life[i] / FADE_TIME) * START_ALPHA

	# Nothing left to fade — stop burning a frame callback until the next dash.
	if _active_count <= 0:
		set_process(false)

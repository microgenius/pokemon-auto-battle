class_name HealAura
extends Node2D
## The visual for a paid heal: a hollow red ring around the fighter, with plus
## signs of mixed sizes drifting up out of it.
##
## Drawn procedurally rather than shipped as a sprite, the same way
## AttackProjectile renders its per-type shapes — nothing to import, and the ring
## scales to whatever the fighter's size turns out to be.
##
## Parented to the fighter so it travels with it — a heal that stayed pinned to
## the cast position drifted off a Pokemon that never stops wandering. Freed when
## the fighter is, and short-lived regardless.

const LIFETIME := 1.6
const RING_RADIUS := 46.0
const RING_WIDTH := 4.0
const RING_COLOR := Color(0.95, 0.25, 0.32)
const PLUS_COUNT := 9
const PLUS_RISE := 90.0

var _ring_alpha := 1.0
var _ring_scale := 0.6
var _plus_marks: Array = []  ## of { offset: Vector2, size: float, alpha: float, rise: float }


## No static factory and no reference to the class name anywhere in here: a
## global class is invisible until Godot rescans, so naming it inside the file
## that defines it makes every dependent script fail to parse until it does.
## Callers instantiate through GameResources.HEAL_AURA and add it as a child.
func _ready() -> void:
	# z high enough to sit over the fighter and its health bar.
	z_index = 50
	position = Vector2.ZERO
	_seed_plus_marks()

	var tween := create_tween()
	tween.set_parallel(true)
	# The ring snaps outward, then fades where it lands.
	tween.tween_property(self, "_ring_scale", 1.0, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(self, "_ring_alpha", 0.0, LIFETIME).set_delay(0.25)
	tween.chain().tween_callback(queue_free)

	# Each plus rises on its own tween so they do not move as one block.
	for i in _plus_marks.size():
		var mark: Dictionary = _plus_marks[i]
		var t := create_tween()
		t.set_parallel(true)
		t.tween_method(_set_plus_rise.bind(i), 0.0, mark["distance"], mark["duration"]).set_delay(mark["delay"])
		t.tween_method(_set_plus_alpha.bind(i), 1.0, 0.0, mark["duration"]).set_delay(mark["delay"])


## Plus signs start on the ring itself, so they read as rising out of it.
func _seed_plus_marks() -> void:
	_plus_marks.clear()
	for i in PLUS_COUNT:
		var angle := randf() * TAU
		_plus_marks.append({
			"offset": Vector2(cos(angle), sin(angle)) * RING_RADIUS * randf_range(0.85, 1.05),
			"size": randf_range(4.0, 11.0),
			"alpha": 1.0,
			"rise": 0.0,
			"distance": PLUS_RISE * randf_range(0.6, 1.2),
			"duration": LIFETIME * randf_range(0.55, 0.9),
			"delay": randf() * 0.5,
		})


func _set_plus_rise(value: float, index: int) -> void:
	_plus_marks[index]["rise"] = value
	queue_redraw()


func _set_plus_alpha(value: float, index: int) -> void:
	_plus_marks[index]["alpha"] = value
	queue_redraw()


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if _ring_alpha > 0.0:
		var ring := RING_COLOR
		ring.a = _ring_alpha
		# filled = false is what makes it a ring rather than a disc.
		draw_arc(Vector2.ZERO, RING_RADIUS * _ring_scale, 0.0, TAU, 48, ring, RING_WIDTH, true)

	for mark in _plus_marks:
		if mark["alpha"] <= 0.0:
			continue
		var colour := RING_COLOR
		colour.a = mark["alpha"]
		var centre: Vector2 = mark["offset"] - Vector2(0, mark["rise"])
		var arm: float = mark["size"]
		var thickness: float = maxf(2.0, arm * 0.32)
		draw_line(centre - Vector2(arm, 0), centre + Vector2(arm, 0), colour, thickness)
		draw_line(centre - Vector2(0, arm), centre + Vector2(0, arm), colour, thickness)

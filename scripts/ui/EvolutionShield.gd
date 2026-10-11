class_name EvolutionShield
extends Node2D
## The bubble a Pokemon sits inside while it evolves.
##
## Replaces a Panel with a rounded StyleBoxFlat, which drew a solid disc that hid
## the fighter behind it. This is a soap bubble: a bright rim, a barely-there
## interior, and a highlight that drifts so it reads as curved glass rather than
## a flat circle.
##
## Drawn procedurally for the same reason HealAura is — nothing to import, and it
## sizes itself. Shots that reach it are absorbed by AttackProjectile, which asks
## the fighter whether it is shielded rather than asking this node.

const RADIUS := 44.0
const RIM_WIDTH := 3.0
const RIM_COLOR := Color(0.55, 0.85, 1.0, 0.95)
const FILL_COLOR := Color(0.5, 0.8, 1.0, 0.10)
const BOB_PERIOD := 1.4

var _phase := 0.0


## Instantiated through GameResources.EVOLUTION_SHIELD, not by class name — see
## the note in HealAura for why naming the class inside its own file breaks
## every dependent script until Godot rescans.
func _ready() -> void:
	name = "EvolutionShield"
	# Behind the sprite's z so the Pokemon stays readable inside the bubble.
	z_index = 10
	position = Vector2.ZERO


func _process(delta: float) -> void:
	_phase += delta
	queue_redraw()


func _draw() -> void:
	# A gentle breathe, so the bubble looks like a membrane under pressure.
	var breathe := 1.0 + sin(_phase * TAU / BOB_PERIOD) * 0.04
	var r := RADIUS * breathe

	# Interior first: nearly transparent, just enough to tint what is behind it.
	draw_circle(Vector2.ZERO, r, FILL_COLOR)

	# The rim is what makes it read as hollow.
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 64, RIM_COLOR, RIM_WIDTH, true)

	# A soft inner rim gives the glass some thickness.
	var inner := RIM_COLOR
	inner.a = 0.25
	draw_arc(Vector2.ZERO, r - RIM_WIDTH * 1.6, 0.0, TAU, 64, inner, RIM_WIDTH * 0.8, true)

	# Specular highlight, drifting slowly around the top-left quadrant.
	var sweep := -PI * 0.75 + sin(_phase * 0.6) * 0.35
	var highlight := Color(1.0, 1.0, 1.0, 0.7)
	draw_arc(Vector2.ZERO, r - RIM_WIDTH, sweep - 0.35, sweep + 0.35, 16, highlight, RIM_WIDTH * 0.9, true)

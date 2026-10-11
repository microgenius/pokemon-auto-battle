class_name FloatingText
extends Label
## Short-lived combat callout — "DODGE", "ÇOK ETKİLİ", damage confirmations —
## that drifts up from a fighter and fades.
##
## Pulled out of Pokemon.gd so the entity does not carry presentation code, and
## so the pixel font is resolved once at compile time instead of being load()ed
## on every single spawn.

const LIFETIME := 2.0
const RISE_DISTANCE := 50.0
const FONT_SIZE := 24
const SPAWN_OFFSET := Vector2(-40, -40)


static func spawn(parent: Node, world_position: Vector2, text: String, color: Color, y_offset: float = 0.0) -> FloatingText:
	var label := FloatingText.new()
	label.text = text
	label.modulate = color
	label.global_position = world_position + SPAWN_OFFSET + Vector2(0, y_offset)
	parent.add_child(label)
	return label


func _ready() -> void:
	add_theme_font_size_override("font_size", FONT_SIZE)
	add_theme_font_override("font", GameResources.PIXEL_FONT)

	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "global_position:y", global_position.y - RISE_DISTANCE, LIFETIME)
	tween.tween_property(self, "scale", Vector2(0.5, 0.5), LIFETIME)
	tween.tween_property(self, "modulate:a", 0.0, LIFETIME)
	tween.chain().tween_callback(queue_free)

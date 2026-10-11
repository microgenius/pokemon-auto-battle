class_name EmotePopup
extends Node2D
## Floating reaction a spectator triggers on the fighter they backed: the
## Pokemon's own sprite playing a one-shot animation with the sender's name
## underneath, drifting up and fading out.

const LIFETIME := 1.5
const RISE_DISTANCE := 50.0
const SPAWN_OFFSET := Vector2(0, -60)

## Emote name -> animation prefix. Anything unrecognised falls back to Idle.
const ANIMATION_BY_EMOTE := {
	"attack": "Attack_Down",
	"hop": "Hop_Down",
	"pain": "Hurt_Down",
	"pose": "Pose_Down",
}
const FALLBACK_ANIMATION := "Idle_Down"


static func spawn_on(target: Node2D, username: String, emote_type: String) -> EmotePopup:
	var popup := EmotePopup.new()
	popup._username = username
	popup._emote_type = emote_type
	popup._pokemon_id = target.current_pokemon_id
	popup.global_position = target.global_position + SPAWN_OFFSET
	target.get_parent().add_child(popup)
	return popup


var _username := ""
var _emote_type := ""
var _pokemon_id := ""


func _ready() -> void:
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 2)
	box.position = Vector2(-40, -50)

	var sprite_slot := Control.new()
	sprite_slot.custom_minimum_size = Vector2(60, 60)
	sprite_slot.size_flags_horizontal = Control.SIZE_SHRINK_CENTER

	var sprite := AnimatedSprite2D.new()
	sprite.sprite_frames = GameResources.sprite_frames_for(_pokemon_id)
	sprite.position = Vector2(30, 30)
	sprite.scale = Vector2(1.5, 1.5)
	sprite_slot.add_child(sprite)

	var label := Label.new()
	label.text = _username
	label.add_theme_font_size_override("font_size", 16)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 4)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	box.add_child(sprite_slot)
	box.add_child(label)
	add_child(box)

	if sprite.sprite_frames:
		sprite.play(_resolve_animation(sprite.sprite_frames))

	var tween := create_tween()
	tween.tween_property(self, "global_position", global_position + Vector2(0, -RISE_DISTANCE), LIFETIME) \
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tween.parallel().tween_property(self, "modulate:a", 0.0, LIFETIME)
	tween.tween_callback(queue_free)


func _resolve_animation(frames: SpriteFrames) -> String:
	var wanted: String = ANIMATION_BY_EMOTE.get(_emote_type, FALLBACK_ANIMATION)
	if frames.has_animation(wanted):
		return wanted
	return FALLBACK_ANIMATION

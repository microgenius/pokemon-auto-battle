class_name EventLog
extends HBoxContainer
## Slide-out combat log docked to the right edge of the arena.
##
## Builds its own UI so the arena scene stays free of a panel that is only ever
## touched from code.
##
## Entries are capped. The old implementation appended a RichTextLabel per event
## and never removed one — a busy four-minute match with six fighters produces
## well over a thousand damage lines, so the log alone ended up being the biggest
## node consumer in the scene.

const MAX_ENTRIES := 150
const PANEL_WIDTH := 400.0
const HANDLE_WIDTH := 40.0
const SLIDE_DURATION := 0.3

var _panel: PanelContainer
var _entries: VBoxContainer
var _scroll: ScrollContainer
var _toggle_button: Button
var _is_open := false


func _ready() -> void:
	theme = GameResources.PIXEL_THEME
	# Sağ kenara yapışık, tam yükseklik. position yerine offset kullanılıyor:
	# _ready sırasında size henüz hesaplanmadığı için set_position dikey
	# anchor'ları bozuyor.
	anchor_left = 1.0
	anchor_right = 1.0
	anchor_top = 0.0
	anchor_bottom = 1.0
	offset_top = 0.0
	offset_bottom = 0.0
	_apply_slide(_closed_offset())

	_toggle_button = Button.new()
	_toggle_button.text = "<<"
	_toggle_button.custom_minimum_size = Vector2(HANDLE_WIDTH, 100)
	_toggle_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_toggle_button.pressed.connect(toggle)
	add_child(_toggle_button)

	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(PANEL_WIDTH - HANDLE_WIDTH, 0)
	_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0.7)
	_panel.add_theme_stylebox_override("panel", style)

	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL

	_entries = VBoxContainer.new()
	_entries.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_entries.add_theme_constant_override("separation", 10)

	_scroll.add_child(_entries)
	_panel.add_child(_scroll)
	add_child(_panel)


func _apply_slide(left_offset: float) -> void:
	offset_left = left_offset
	offset_right = left_offset + PANEL_WIDTH


func _closed_offset() -> float:
	return -HANDLE_WIDTH


func _open_offset() -> float:
	return -PANEL_WIDTH


## Appends a BBCode line. Safe to call before _ready has run.
func add_entry(bbcode: String) -> void:
	if not is_instance_valid(_entries):
		return

	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.text = bbcode
	label.fit_content = true
	label.custom_minimum_size = Vector2(PANEL_WIDTH - HANDLE_WIDTH - 20.0, 0)
	label.add_theme_font_size_override("normal_font_size", 14)
	_entries.add_child(label)

	_trim_to_cap()
	# Layout has not run yet, so the scrollbar's max is still stale.
	call_deferred("_scroll_to_bottom")


func _trim_to_cap() -> void:
	var overflow := _entries.get_child_count() - MAX_ENTRIES
	while overflow > 0:
		var oldest := _entries.get_child(0)
		_entries.remove_child(oldest)
		oldest.queue_free()
		overflow -= 1


func _scroll_to_bottom() -> void:
	if is_instance_valid(_scroll):
		_scroll.scroll_vertical = int(_scroll.get_v_scroll_bar().max_value)


func toggle() -> void:
	var target := _closed_offset() if _is_open else _open_offset()
	_toggle_button.text = "<<" if _is_open else ">>"

	var tween := create_tween()
	tween.tween_method(_apply_slide, offset_left, target, SLIDE_DURATION).set_trans(Tween.TRANS_CUBIC)

	_is_open = not _is_open


func clear() -> void:
	if not is_instance_valid(_entries):
		return
	for child in _entries.get_children():
		child.queue_free()

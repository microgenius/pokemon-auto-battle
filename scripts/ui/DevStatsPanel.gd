class_name DevStatsPanel
extends PanelContainer
## Developer inspector: click a fighter mid-match to pause and read its full
## stat block. Only reachable when Settings.developer_mode is on.

signal closed


static func create(pokemon) -> DevStatsPanel:
	var panel := DevStatsPanel.new()
	panel._pokemon = pokemon
	return panel


var _pokemon


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = GameResources.PIXEL_THEME
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)

	var title := Label.new()
	title.text = "GELIŞTIRICI STATLARI: " + _pokemon.pokemon_name
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", Color.YELLOW)
	box.add_child(title)

	var info := Label.new()
	info.text = _build_stat_text()
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(info)

	var close_button := Button.new()
	close_button.text = "KAPAT VE DEVAM ET"
	close_button.pressed.connect(func():
		closed.emit()
		queue_free()
	)
	box.add_child(close_button)


func _build_stat_text() -> String:
	var dodge: float = _pokemon.get_dodge_chance()
	var crit: float = _pokemon.get_crit_chance()
	var exp_needed: float = _pokemon.exp_to_next_level()
	var secondary: String = _pokemon.secondary_type.to_upper() if _pokemon.secondary_type != "" else "-"

	var lines := [
		"Level: %d | EXP: %d/%d" % [_pokemon.level, round(_pokemon.current_exp), round(exp_needed)],
		"Tip 1: %s | Tip 2: %s" % [_pokemon.primary_type.to_upper(), secondary],
		"HP: %d / %d" % [round(_pokemon.current_hp), round(_pokemon.max_hp)],
		"ATK: %d | DEF: %d" % [_pokemon.atk_stat, _pokemon.def_stat],
		"SP.ATK: %d | SP.DEF: %d" % [_pokemon.sp_atk_stat, _pokemon.sp_def_stat],
		"SPD: %d (Base: %d)" % [_pokemon.spd_stat, _pokemon.base_spd],
		"Dodge Şansı: %%%s" % snapped(dodge, 0.1),
		"Kritik Şansı: %%%s" % snapped(crit, 0.1),
	]
	return "\n".join(lines)

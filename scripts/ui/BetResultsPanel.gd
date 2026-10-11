class_name BetResultsPanel
extends ColorRect
## Full-screen settlement breakdown shown after a match, one block per bettor.
##
## Built from the BET_RESULTS payload the server pushes back to the host.

const TITLE_FONT_SIZE := 48
const USER_FONT_SIZE := 24
const BET_FONT_SIZE := 20


static func create(results: Dictionary) -> BetResultsPanel:
	var panel := BetResultsPanel.new()
	panel._results = results
	return panel


var _results: Dictionary = {}


func _ready() -> void:
	name = "BetResultsPanel"
	color = Color(0, 0, 0, 0.95)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = GameResources.PIXEL_THEME

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 60)
	add_child(margin)

	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_child(scroll)

	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 24)
	scroll.add_child(content)

	content.add_child(_make_title())

	for user_data in _results.get("users", []):
		_add_user_block(content, user_data)

	content.add_child(_make_close_button())


func _make_title() -> Label:
	var title := Label.new()
	title.text = "BAHİS SONUÇLARI"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	title.add_theme_color_override("font_color", Color(1.0, 0.84, 0.0))
	return title


func _add_user_block(parent: VBoxContainer, user_data: Dictionary) -> void:
	var wager: int = user_data.get("wager", 0)
	var payout: int = user_data.get("payout", 0)
	var new_points: int = user_data.get("new_points", 0)
	var net := payout - wager

	# The server already tells us the pre-settlement balance. Recomputing it from
	# the payout is what produced a wrong "old points" figure before, because the
	# stake had already been deducted when the bet was placed.
	var old_points: int = user_data.get("old_points", new_points - payout)

	var header := Label.new()
	header.text = "%s\nEski Puan: %d  ->  Yeni Puan: %d" % [user_data.get("username", "?"), old_points, new_points]
	header.add_theme_font_size_override("font_size", USER_FONT_SIZE)
	header.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if net > 0:
		header.add_theme_color_override("font_color", Color.GREEN)
	elif net < 0:
		header.add_theme_color_override("font_color", Color.RED)
	parent.add_child(header)

	var bets: Array = user_data.get("bets", [])
	if not bets.is_empty():
		var bets_box := VBoxContainer.new()
		bets_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bets_box.add_theme_constant_override("separation", 8)
		for bet in bets:
			bets_box.add_child(_make_bet_line(bet))
		parent.add_child(bets_box)

	parent.add_child(_make_net_label(net, wager, payout))
	parent.add_child(HSeparator.new())


func _make_bet_line(bet: Dictionary) -> RichTextLabel:
	var line := RichTextLabel.new()
	line.bbcode_enabled = true
	line.fit_content = true
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	line.custom_minimum_size = Vector2(500, 0)
	line.add_theme_font_size_override("normal_font_size", BET_FONT_SIZE)

	var icon := "✅" if bet.get("won", false) else "❌"
	line.text = "%s %s: %s (x%s) - Yatırılan: %d CP\n[color=#aaaaaa][font_size=16]Gerçekleşen: %s | Kazanılan: %d CP[/font_size][/color]" % [
		icon,
		bet.get("type", "?"),
		bet.get("choice", "?"),
		snapped(bet.get("odds", 1.0), 0.01),
		bet.get("wager", 0),
		bet.get("actual", "-"),
		bet.get("payout", 0),
	]
	return line


func _make_net_label(net: int, wager: int, payout: int) -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", USER_FONT_SIZE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var detail := "\n(Yatırılan: %d | Toplam Getiri: %d)" % [wager, payout]
	if net > 0:
		label.text = "NET KAZANÇ: +%d CP%s" % [net, detail]
		label.add_theme_color_override("font_color", Color.GREEN)
	elif net < 0:
		label.text = "NET KAYIP: %d CP%s" % [net, detail]
		label.add_theme_color_override("font_color", Color.RED)
	else:
		label.text = "BAŞABAŞ: 0 CP%s" % detail
	return label


func _make_close_button() -> Button:
	var button := Button.new()
	button.text = "KAPAT"
	button.custom_minimum_size = Vector2(300, 60)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_size_override("font_size", 32)
	button.pressed.connect(queue_free)
	return button

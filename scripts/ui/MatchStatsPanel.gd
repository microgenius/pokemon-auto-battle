class_name MatchStatsPanel
extends RefCounted
## Fills the end-of-match statistics list.
##
## Not a node: the panel itself lives in Main.tscn (it has a fixed layout worth
## editing visually). This just owns the rendering of the rows, so GameManager
## does not need to know what a stats row looks like.

const ROW_FONT_SIZE := 20


static func populate(list_container: VBoxContainer, stats: Array) -> void:
	for child in list_container.get_children():
		child.queue_free()

	var sorted := stats.duplicate()
	sorted.sort_custom(func(a, b): return a.kills > b.kills)

	for entry in sorted:
		list_container.add_child(_make_row(entry))


static func _make_row(entry: PokemonMatchStats) -> Label:
	var label := Label.new()
	label.text = "%s | Skor: %d | Atış: %d | İsabet: %%%d" % [
		entry.name,
		entry.kills,
		entry.attacks,
		round(entry.hit_ratio()),
	]
	label.modulate = entry.color
	label.add_theme_font_size_override("font_size", ROW_FONT_SIZE)
	return label

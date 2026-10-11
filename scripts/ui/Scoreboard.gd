class_name Scoreboard
extends VBoxContainer
## Live standings panel: one row per fighter, alive first, then the fallen.
##
## Performance note — this is why the class exists.
##
## The original implementation was called from Pokemon.take_damage(), i.e. on
## every single hit, and each call did:
##
##     for child in container.get_children(): child.queue_free()
##     ... then rebuilt every row from scratch
##
## Six fighters trading blows produces dozens of damage events per second, so the
## game was allocating and freeing ~24 Control nodes per hit and forcing a full
## layout pass each time, purely to change two numbers.
##
## This version keeps the rows alive and only writes the values that changed,
## coalescing bursts of updates into at most one refresh per REFRESH_INTERVAL.

## Redraw at most ~6x/second. Fast enough to feel live, slow enough that a
## flurry of simultaneous hits collapses into one layout pass.
const REFRESH_INTERVAL := 0.15

const HP_BAR_HEIGHT := 15.0
const DEAD_ROW_ALPHA := 0.5

var _rows: Dictionary = {}  ## pokemon instance id -> {root, label, bar}
## Snapshots of the fallen, so their rows survive the node being freed.
var _dead: Array = []  ## of {key, name, color, score, death_order}
var _refresh_pending := false
var _time_since_refresh := 0.0


func _ready() -> void:
	# Must keep ticking while the tree is paused, otherwise a refresh requested
	# on the frame a pause began would never land.
	process_mode = Node.PROCESS_MODE_ALWAYS


## Coalescing entry point. Call as often as you like; the work happens later.
func request_refresh() -> void:
	_refresh_pending = true


func _process(delta: float) -> void:
	_time_since_refresh += delta
	if _refresh_pending and _time_since_refresh >= REFRESH_INTERVAL:
		_refresh_pending = false
		_time_since_refresh = 0.0
		refresh_now()


## Immediate rebuild. Use for one-off moments (match start, match end) where the
## next frame matters more than the coalescing.
func refresh_now() -> void:
	var living := _living_pokemon()
	living.sort_custom(func(a, b): return a.score > b.score)

	var seen: Dictionary = {}
	var slot := 0

	for pokemon in living:
		var key: int = pokemon.get_instance_id()
		seen[key] = true
		var row: Dictionary = _rows.get(key, {})
		if row.is_empty():
			row = _create_row(key)
		_apply_living(row, pokemon)
		_place(row["root"], slot)
		slot += 1

	# The fallen keep their rows, greyed out, most recent death first.
	var fallen := _fallen_rows(seen)
	for entry in fallen:
		seen[entry["key"]] = true
		_place(entry["row"]["root"], slot)
		slot += 1

	_drop_stale_rows(seen)


## Records a death so the row can persist after the node is freed. Called by
## GameManager before the Pokemon leaves the tree.
func register_death(pokemon, death_order: int) -> void:
	_dead.append({
		"key": pokemon.get_instance_id(),
		"name": pokemon.pokemon_name,
		"color": pokemon.sprite.modulate if pokemon.sprite else Color.WHITE,
		"score": pokemon.score,
		"death_order": death_order,
	})


func reset() -> void:
	for row in _rows.values():
		row["root"].queue_free()
	_rows.clear()
	_dead.clear()


func _living_pokemon() -> Array:
	var out: Array = []
	for pokemon in get_tree().get_nodes_in_group("pokemon"):
		if not pokemon.is_queued_for_deletion():
			out.append(pokemon)
	return out


func _fallen_rows(seen: Dictionary) -> Array:
	var sorted_dead := _dead.duplicate()
	sorted_dead.sort_custom(func(a, b): return a["death_order"] > b["death_order"])

	var out: Array = []
	for record in sorted_dead:
		var key = record["key"]
		if seen.has(key):
			continue
		var row: Dictionary = _rows.get(key, {})
		if row.is_empty():
			row = _create_row(key)
		_apply_dead(row, record)
		out.append({"key": key, "row": row})
	return out


func _create_row(key: int) -> Dictionary:
	var root := VBoxContainer.new()

	var label := Label.new()
	root.add_child(label)

	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(0, HP_BAR_HEIGHT)
	root.add_child(bar)

	add_child(root)

	var row := {"root": root, "label": label, "bar": bar}
	_rows[key] = row
	return row


func _apply_living(row: Dictionary, pokemon) -> void:
	var color: Color = pokemon.sprite.modulate if pokemon.sprite else Color.WHITE
	var text := "%s - Skor: %d" % [pokemon.pokemon_name, pokemon.score]

	# Only touch properties that actually changed — every assignment to a Control
	# property queues a redraw whether or not the value differs.
	var label: Label = row["label"]
	if label.text != text:
		label.text = text
	if label.modulate != color:
		label.modulate = color

	var bar: ProgressBar = row["bar"]
	if bar.max_value != pokemon.max_hp:
		bar.max_value = pokemon.max_hp
	if bar.value != pokemon.current_hp:
		bar.value = pokemon.current_hp
	if bar.modulate != color:
		bar.modulate = color


func _apply_dead(row: Dictionary, record: Dictionary) -> void:
	var faded: Color = record["color"]
	faded.a = DEAD_ROW_ALPHA
	var text := "%s - Skor: %d" % [record["name"], record["score"]]

	var label: Label = row["label"]
	if label.text != text:
		label.text = text
	if label.modulate != faded:
		label.modulate = faded

	var bar: ProgressBar = row["bar"]
	if bar.max_value != 100:
		bar.max_value = 100
	if bar.value != 0:
		bar.value = 0
	if bar.modulate != faded:
		bar.modulate = faded


func _place(row_root: Control, slot: int) -> void:
	if row_root.get_index() != slot:
		move_child(row_root, slot)


func _drop_stale_rows(seen: Dictionary) -> void:
	for key in _rows.keys():
		if not seen.has(key):
			_rows[key]["root"].queue_free()
			_rows.erase(key)

extends Control

@onready var grid_container: GridContainer = $CenterContainer/VBoxContainer/GridContainer
@onready var start_button: Button = $CenterContainer/VBoxContainer/StartButton

var map_option: OptionButton

func _ready() -> void:
	theme = GameResources.PIXEL_THEME

	start_button.pressed.connect(_on_start_pressed)
	
	var top_bar = HBoxContainer.new()
	top_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	top_bar.add_theme_constant_override("separation", 50)
	
	var back_btn = Button.new()
	back_btn.text = "<- Ana Menü"
	back_btn.custom_minimum_size = Vector2(200, 50)
	back_btn.add_theme_font_size_override("font_size", 24)
	back_btn.pressed.connect(func(): get_tree().change_scene_to_file(GameResources.MAIN_MENU_PATH))
	top_bar.add_child(back_btn)
	
	map_option = OptionButton.new()
	map_option.custom_minimum_size = Vector2(300, 50)
	map_option.add_theme_font_size_override("font_size", 24)
	map_option.add_item("Level 1 (Temel Harita)")
	map_option.add_item("Level 2 (Engelli Harita)")
	
	map_option.selected = 1 if Settings.selected_map_path == GameResources.LEVEL_2_PATH else 0

	top_bar.add_child(map_option)
	
	var vbox = $CenterContainer/VBoxContainer
	vbox.add_child(top_bar)
	vbox.move_child(top_bar, 0)
	vbox.add_theme_constant_override("separation", 30)

	populate_grid()

func populate_grid() -> void:
	# Temizle
	for child in grid_container.get_children():
		child.queue_free()
		
	var db = {}
	if get_node_or_null("/root/Global"):
		db = get_node("/root/Global").pokemon_db
	
	for i in range(Settings.selected_pokemons.size()):
		var pid = Settings.selected_pokemons[i]
		var t_name = pid
		if db.has(pid):
			t_name = str(db[pid]["name"]).capitalize()
			
		var btn = Button.new()
		btn.flat = true
		btn.custom_minimum_size = Vector2(120, 140)
		btn.pressed.connect(_on_pokemon_clicked.bind(pid, i, t_name))
		
		var vbox = VBoxContainer.new()
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		
		var ctrl = Control.new()
		ctrl.custom_minimum_size = Vector2(100, 100)
		ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		
		var sprite = AnimatedSprite2D.new()
		sprite.sprite_frames = GameResources.sprite_frames_for(pid)
		if sprite.sprite_frames:
			sprite.play("Idle_Down")
			
		sprite.position = Vector2(50, 50)
		sprite.scale = Vector2(2.0, 2.0)
		ctrl.add_child(sprite)
		
		vbox.add_child(ctrl)
		btn.add_child(vbox)
		
		var remove_btn = Button.new()
		remove_btn.text = "-"
		remove_btn.custom_minimum_size = Vector2(30, 30)
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.8, 0.2, 0.2)
		style.corner_radius_top_left = 15
		style.corner_radius_top_right = 15
		style.corner_radius_bottom_left = 15
		style.corner_radius_bottom_right = 15
		remove_btn.add_theme_stylebox_override("normal", style)
		remove_btn.add_theme_stylebox_override("hover", style)
		remove_btn.add_theme_stylebox_override("pressed", style)
		remove_btn.position = Vector2(90, -5)
		remove_btn.pressed.connect(_on_remove_clicked.bind(i))
		btn.add_child(remove_btn)
		
		grid_container.add_child(btn)
		
	if Settings.selected_pokemons.size() < Settings.MAX_ROSTER_SIZE:
		var add_btn = Button.new()
		add_btn.text = "+"
		add_btn.flat = true
		add_btn.add_theme_font_size_override("font_size", 48)
		add_btn.custom_minimum_size = Vector2(120, 140)
		add_btn.pressed.connect(_on_pokemon_clicked.bind("", -1, "Yeni Ekle"))
		grid_container.add_child(add_btn)

func _on_remove_clicked(index: int) -> void:
	if Settings.selected_pokemons.size() > Settings.MIN_ROSTER_SIZE:
		Settings.selected_pokemons.remove_at(index)
		populate_grid()

func _on_pokemon_clicked(pid: String, index: int, p_name: String) -> void:
	# Overlay
	var overlay = ColorRect.new()
	overlay.color = Color(0, 0, 0, 0.95)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 20)
	
	# Header with Close Button
	var header = HBoxContainer.new()
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	header.custom_minimum_size = Vector2(0, 80)
	
	var title = Label.new()
	title.text = "Pokemon Seçimi (" + p_name + " yerine)"
	title.add_theme_font_size_override("font_size", 32)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header.add_child(title)
	
	var close_btn = Button.new()
	close_btn.text = "KAPAT"
	close_btn.custom_minimum_size = Vector2(150, 60)
	close_btn.add_theme_font_size_override("font_size", 24)
	close_btn.pressed.connect(func(): overlay.queue_free())
	header.add_child(close_btn)
	
	vbox.add_child(header)
	
	# ScrollContainer for the grid
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var grid = HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 15)
	grid.add_theme_constant_override("v_separation", 15)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	var db = {}
	if get_node_or_null("/root/Global"):
		db = get_node("/root/Global").pokemon_db
		
	for i in range(1, 252):
		var target_pid = "%04d" % i
		var is_basic = true
		var t_name = "Pokemon"
		if db.has(target_pid):
			if db[target_pid].has("is_basic"):
				is_basic = db[target_pid]["is_basic"]
			if db[target_pid].has("name"):
				t_name = str(db[target_pid]["name"]).capitalize()
				
		if not is_basic:
			continue
			
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(120, 140)
		btn.flat = true
		btn.pressed.connect(_on_selection_made.bind(target_pid, index, overlay))
		
		var slot_vbox = VBoxContainer.new()
		slot_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		slot_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot_vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
		
		var ctrl = Control.new()
		ctrl.custom_minimum_size = Vector2(80, 80)
		ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		
		var icon_texture = GameResources.icon_for(target_pid)
		if icon_texture:
			var sprite = TextureRect.new()
			sprite.texture = icon_texture
			sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			sprite.set_anchors_preset(Control.PRESET_FULL_RECT)
			ctrl.add_child(sprite)
			
		var name_label = Label.new()
		name_label.text = t_name
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		
		slot_vbox.add_child(ctrl)
		slot_vbox.add_child(name_label)
		btn.add_child(slot_vbox)
		
		grid.add_child(btn)
		
	scroll.add_child(grid)
	vbox.add_child(scroll)
	
	overlay.add_child(vbox)
	add_child(overlay)

func _on_selection_made(new_pid: String, index: int, overlay: Node) -> void:
	if Settings.selected_pokemons.has(new_pid):
		return # Aynı pokemon zaten ekli
		
	if index == -1:
		Settings.selected_pokemons.append(new_pid)
	else:
		Settings.selected_pokemons[index] = new_pid
	overlay.queue_free()
	populate_grid()

func _on_start_pressed() -> void:
	if map_option:
		Settings.selected_map_path = GameResources.LEVEL_1_PATH if map_option.selected == 0 else GameResources.LEVEL_2_PATH
	# Roster and map are player choices — persist them so the next launch opens
	# on the same lineup instead of resetting to the default five.
	Settings.save_settings()

	_start_intro_phase()

var intro_timer: Timer
var intro_time_left: int = 0
var intro_countdown_label: Label
var intro_pokemon_container: Control
var intro_pokemon_index: int = 0
var intro_pokemon_timer: Timer
var intro_ui: Control
var skip_button: Button
var ready_ui: Control
var players_list: VBoxContainer
var ready_status_label: Label
## Latest roster from the server, kept so the ready screen can render it even if
## it arrives while the intro is still playing.
var latest_players: Array = []
## Latches so an ALL_READY arriving twice cannot start two countdowns.
var match_starting: bool = false

func _start_intro_phase() -> void:
	# Arayüzü gizle
	$CenterContainer/VBoxContainer.visible = false
	
	# Intro arayüzü oluştur
	intro_ui = VBoxContainer.new()
	intro_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	intro_ui.alignment = BoxContainer.ALIGNMENT_CENTER
	intro_ui.add_theme_constant_override("separation", 50)
	
	intro_countdown_label = Label.new()
	intro_countdown_label.add_theme_font_size_override("font_size", 28)
	intro_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intro_countdown_label.text = "BAHİSLER İÇİN KALAN SÜRE: 60"
	intro_ui.add_child(intro_countdown_label)
	
	intro_pokemon_container = VBoxContainer.new()
	intro_pokemon_container.alignment = BoxContainer.ALIGNMENT_CENTER
	intro_ui.add_child(intro_pokemon_container)

	add_child(intro_ui)
	_build_ready_screen()

	# Skips the showcase only — the match still waits on the ready screen.
	skip_button = Button.new()
	skip_button.text = "ATLA >>"
	skip_button.custom_minimum_size = Vector2(150, 50)
	skip_button.add_theme_font_size_override("font_size", 24)
	add_child(skip_button)
	skip_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	skip_button.offset_left = -170
	skip_button.offset_top = 20
	skip_button.offset_right = -20
	skip_button.offset_bottom = 70

	skip_button.pressed.connect(_show_ready_screen)

	var is_host = false
	if get_node_or_null("/root/Global"):
		is_host = get_node("/root/Global").is_multiplayer_host
		
	intro_time_left = max(6, Settings.selected_pokemons.size() * 6)
	
	if is_host:
		intro_countdown_label.text = "BAHİSLER İÇİN KALAN SÜRE: " + str(intro_time_left)
	else:
		intro_countdown_label.text = "SAVAŞA KALAN SÜRE: " + str(intro_time_left)
	
	# Sunucuya bağlan ve lobi bilgilerini gönder (sadece Host ise)
	if is_host and get_node_or_null("/root/NetworkManager"):
		var nm = get_node("/root/NetworkManager")
		nm.players_updated.connect(_on_players_updated)
		nm.all_ready.connect(_on_all_ready)
		nm.connect_to_server()
		
		# Sunucunun bağlanması biraz sürebileceği için ufak bir bekleme (veya sinyal)
		await get_tree().create_timer(1.0).timeout
		
		var db = get_node("/root/Global").pokemon_db
		var options = []
		for i in Settings.selected_pokemons.size():
			var pid: String = Settings.selected_pokemons[i]
			var p_name = pid
			var p_data = {}
			if db.has(pid):
				p_data = db[pid]
				p_name = str(p_data["name"]).capitalize()
			options.append({
				# Stable slot identity the server keys every market on. Must match
				# GameManager.alias_for_slot for the same roster index.
				"alias": GameManager.alias_for_slot(i),
				"id": pid,
				"name": p_name,
				"sprite_url": GameResources.icon_url_for(pid),
				"base_hp": p_data.get("base_hp", 50),
				"base_atk": p_data.get("base_atk", 50),
				"base_def": p_data.get("base_def", 50),
				"base_sp_atk": p_data.get("base_sp_atk", 50),
				"base_sp_def": p_data.get("base_sp_def", 50),
				"base_spd": p_data.get("base_spd", 50),
				"evolution_level": p_data.get("evolution_level", -1),
				# How far along its evolution line this form starts. The server
				# prices the "dies before completing its evolution" market from
				# the number of steps still ahead of it.
				"stage": p_data.get("stage", 1),
				"max_stages": p_data.get("max_stages", 1),
				"primary_type": p_data.get("primary_type", "normal")
			})
		nm.broadcast_lobby(options)
	
	# Ana Geri Sayım
	intro_timer = Timer.new()
	intro_timer.wait_time = 1.0
	intro_timer.autostart = true
	intro_timer.timeout.connect(_on_intro_tick)
	add_child(intro_timer)
	
	# Pokemon Tanıtım Döngüsü
	intro_pokemon_timer = Timer.new()
	intro_pokemon_timer.wait_time = 6.0 # Her 6 saniyede bir pokemon tanıtımı
	intro_pokemon_timer.autostart = true
	intro_pokemon_timer.timeout.connect(_show_next_intro_pokemon)
	add_child(intro_pokemon_timer)
	
	_show_next_intro_pokemon()

func _on_intro_tick() -> void:
	intro_time_left -= 1
	var is_host = false
	if get_node_or_null("/root/Global"): is_host = get_node("/root/Global").is_multiplayer_host
	
	if match_starting:
		return

	if intro_time_left > 0:
		if is_host:
			intro_countdown_label.text = "BAHİSLER İÇİN KALAN SÜRE: " + str(intro_time_left)
		else:
			intro_countdown_label.text = "SAVAŞA KALAN SÜRE: " + str(intro_time_left)
	else:
		_show_ready_screen()


## The showcase and the ready check are separate screens: the first is a reel
## you can sit through or skip, the second is where the match actually waits.
func _build_ready_screen() -> void:
	ready_ui = VBoxContainer.new()
	ready_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	ready_ui.alignment = BoxContainer.ALIGNMENT_CENTER
	ready_ui.add_theme_constant_override("separation", 24)
	ready_ui.visible = false

	var title := Label.new()
	title.text = "OYUNCULAR"
	title.add_theme_font_size_override("font_size", 36)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ready_ui.add_child(title)

	players_list = VBoxContainer.new()
	players_list.alignment = BoxContainer.ALIGNMENT_CENTER
	players_list.add_theme_constant_override("separation", 8)
	ready_ui.add_child(players_list)

	ready_status_label = Label.new()
	ready_status_label.add_theme_font_size_override("font_size", 24)
	ready_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ready_status_label.text = "Hazır sinyali bekleniyor..."
	ready_ui.add_child(ready_status_label)

	# Force start: one idle spectator must not be able to hold the lobby.
	var start_btn := Button.new()
	start_btn.text = "BAŞLAT"
	start_btn.custom_minimum_size = Vector2(220, 60)
	start_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	start_btn.add_theme_font_size_override("font_size", 28)
	start_btn.pressed.connect(_begin_match)
	ready_ui.add_child(start_btn)

	add_child(ready_ui)
	_render_players()


func _show_ready_screen() -> void:
	if intro_timer:
		intro_timer.stop()
	if intro_pokemon_timer:
		intro_pokemon_timer.stop()
	if is_instance_valid(intro_ui):
		intro_ui.visible = false
	# It only ever skipped the showcase, so it has nothing left to do here.
	if is_instance_valid(skip_button):
		skip_button.queue_free()
	if is_instance_valid(ready_ui):
		ready_ui.visible = true
	_render_players()
	_maybe_autostart()


func _on_players_updated(players: Array) -> void:
	latest_players = players
	_render_players()
	_maybe_autostart()


## Nobody to wait for, so do not park on a ready screen with no names on it.
## Only fires once the showcase is over — spectators normally join during it,
## and an empty lobby at the moment it opens is not an empty lobby.
func _maybe_autostart() -> void:
	if match_starting or not is_instance_valid(ready_ui) or not ready_ui.visible:
		return
	if latest_players.is_empty():
		_begin_match()


func _render_players() -> void:
	if not is_instance_valid(players_list):
		return

	for child in players_list.get_children():
		child.queue_free()

	if latest_players.is_empty():
		var empty := Label.new()
		empty.text = "Bağlanan oyuncu yok"
		empty.add_theme_font_size_override("font_size", 22)
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		players_list.add_child(empty)
		return

	var ready_count := 0
	for p in latest_players:
		var is_ready: bool = p.get("ready", false)
		if is_ready:
			ready_count += 1
		var row := Label.new()
		row.text = ("✅  " if is_ready else "❌  ") + str(p.get("username", "?"))
		row.add_theme_font_size_override("font_size", 26)
		row.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		players_list.add_child(row)

	if is_instance_valid(ready_status_label) and not match_starting:
		ready_status_label.text = "Hazır: %d / %d" % [ready_count, latest_players.size()]


func _on_all_ready() -> void:
	if match_starting:
		return
	match_starting = true
	# Readiness can land while the showcase is still playing; jump to the screen
	# that is actually counting down.
	_show_ready_screen()

	for i in range(3, 0, -1):
		ready_status_label.text = "HERKES HAZIR! %d" % i
		await get_tree().create_timer(1.0).timeout
		if not is_inside_tree():
			return
	_begin_match()


func _begin_match() -> void:
	# Reachable from the button while a ready-countdown is running, so latch here
	# too rather than only in _on_all_ready.
	if not is_inside_tree():
		return
	match_starting = true
	if is_instance_valid(ready_status_label):
		ready_status_label.text = "SAVAŞ BAŞLIYOR!"
	if intro_timer:
		intro_timer.stop()
	if intro_pokemon_timer:
		intro_pokemon_timer.stop()

	var nm := get_node_or_null("/root/NetworkManager")
	if nm and get_node_or_null("/root/Global") and get_node("/root/Global").is_multiplayer_host:
		nm.broadcast_match_start()
	get_tree().change_scene_to_file(GameResources.ARENA_PATH)

func _show_next_intro_pokemon() -> void:
	if Settings.selected_pokemons.is_empty(): return
	
	for child in intro_pokemon_container.get_children():
		child.queue_free()
		
	var pid = Settings.selected_pokemons[intro_pokemon_index % Settings.selected_pokemons.size()]
	intro_pokemon_index += 1
	
	var db = {}
	if get_node_or_null("/root/Global"): db = get_node("/root/Global").pokemon_db
	
	var p_name = pid
	var type1 = ""
	var type2 = ""
	var evolves_to_names = []
	if db.has(pid):
		p_name = str(db[pid].get("name", pid)).capitalize()
		type1 = str(db[pid].get("primary_type", "")).capitalize()
		type2 = str(db[pid].get("secondary_type", "")).capitalize()
		evolves_to_names = db[pid].get("evolves_to", [])
		
	var sprite = AnimatedSprite2D.new()
	sprite.sprite_frames = GameResources.sprite_frames_for(pid)
	if sprite.sprite_frames:
		sprite.play("Idle_Down")
	
	var ctrl = Control.new()
	ctrl.custom_minimum_size = Vector2(160, 160)
	ctrl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	sprite.position = Vector2(80, 80)
	sprite.scale = Vector2(3.5, 3.5)
	ctrl.add_child(sprite)
	intro_pokemon_container.add_child(ctrl)
	
	var name_lbl = Label.new()
	name_lbl.text = p_name
	name_lbl.add_theme_font_size_override("font_size", 32)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intro_pokemon_container.add_child(name_lbl)
	
	var types_lbl = Label.new()
	types_lbl.text = "Tip: " + type1 + ((" / " + type2) if type2 != "" else "")
	types_lbl.add_theme_font_size_override("font_size", 18)
	types_lbl.add_theme_color_override("font_color", Color.GRAY)
	types_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intro_pokemon_container.add_child(types_lbl)
	
	if evolves_to_names.size() > 0:
		var ev_spacer = Control.new()
		ev_spacer.custom_minimum_size = Vector2(0, 20)
		intro_pokemon_container.add_child(ev_spacer)
		
		var ev_title = Label.new()
		ev_title.text = "Evrim Ağacı:"
		ev_title.add_theme_font_size_override("font_size", 16)
		ev_title.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
		ev_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		intro_pokemon_container.add_child(ev_title)
		
		var initial_hbox = HBoxContainer.new()
		initial_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
		initial_hbox.add_theme_constant_override("separation", 30)
		intro_pokemon_container.add_child(initial_hbox)
		
		var visited = [pid] # Döngüleri engellemek ve kendini tekrar göstermemek için
		_build_evolution_tree_ui(db, evolves_to_names, intro_pokemon_container, initial_hbox, visited)

func _build_evolution_tree_ui(db: Dictionary, current_names: Array, parent_vbox: VBoxContainer, current_hbox: HBoxContainer, visited: Array = []) -> void:
	if current_names.size() == 0: return
	
	var next_names = []
	
	for p_name in current_names:
		var p_id = ""
		for k in db.keys():
			if str(db[k].get("name", "")).to_lower() == str(p_name).to_lower():
				p_id = k
				break
				
		if p_id != "" and not (p_id in visited):
			visited.append(p_id)
			
			var ev_vbox = VBoxContainer.new()
			ev_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
			
			var ev_tex = TextureRect.new()
			ev_tex.texture = GameResources.icon_for(p_id)
			ev_tex.custom_minimum_size = Vector2(75, 75)
			ev_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			ev_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			
			var ev_lbl = Label.new()
			ev_lbl.text = str(p_name).capitalize()
			ev_lbl.add_theme_font_size_override("font_size", 14)
			ev_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			
			ev_vbox.add_child(ev_tex)
			ev_vbox.add_child(ev_lbl)
			current_hbox.add_child(ev_vbox)
			
			var evs = db[p_id].get("evolves_to", [])
			for e in evs:
				if not (e in next_names):
					next_names.append(e)
					
	if next_names.size() > 0:
		if current_names.size() == 1:
			var arrow_lbl = Label.new()
			arrow_lbl.text = "→"
			arrow_lbl.add_theme_font_size_override("font_size", 24)
			arrow_lbl.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
			current_hbox.add_child(arrow_lbl)
			_build_evolution_tree_ui(db, next_names, parent_vbox, current_hbox, visited)
		else:
			var new_hbox = HBoxContainer.new()
			new_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
			new_hbox.add_theme_constant_override("separation", 30)
			parent_vbox.add_child(new_hbox)
			_build_evolution_tree_ui(db, next_names, parent_vbox, new_hbox, visited)

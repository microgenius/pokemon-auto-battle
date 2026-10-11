extends Control

@onready var map_option: OptionButton = $MapOption
@onready var start_button: Button = $VBoxContainer/StartButton
@onready var settings_button: Button = $VBoxContainer/SettingsButton

@onready var settings_panel: Panel = $SettingsPanel
@onready var close_settings_button: Button = $SettingsPanel/VBoxContainer/CloseSettings

@onready var res_option: OptionButton = $SettingsPanel/VBoxContainer/ResHBox/OptionButton

# SpinBoxes
@onready var hs_dir: HSlider = $SettingsPanel/VBoxContainer/DirHBox/HSlider
@onready var lbl_dir: Label = $SettingsPanel/VBoxContainer/DirHBox/ValueLabel

@onready var hs_atk: HSlider = $SettingsPanel/VBoxContainer/AtkHBox/HSlider
@onready var lbl_atk: Label = $SettingsPanel/VBoxContainer/AtkHBox/ValueLabel

@onready var hs_hp_mult: HSlider = $SettingsPanel/VBoxContainer/HPMultHBox/HSlider
@onready var lbl_hp_mult: Label = $SettingsPanel/VBoxContainer/HPMultHBox/ValueLabel

@onready var hs_pred: HSlider = $SettingsPanel/VBoxContainer/PredHBox/HSlider
@onready var lbl_pred: Label = $SettingsPanel/VBoxContainer/PredHBox/ValueLabel

@onready var hs_perf: HSlider = $SettingsPanel/VBoxContainer/PerfHBox/HSlider
@onready var lbl_perf: Label = $SettingsPanel/VBoxContainer/PerfHBox/ValueLabel

@onready var chk_dev_mode: CheckBox = $SettingsPanel/VBoxContainer/DevModeCheckBox

func _ready() -> void:
	self.theme = GameResources.PIXEL_THEME


	# Arka planı Texture olarak yükle
	var bg_tex = load("res://assets/sprites/menu_bg_hd.jpg")
	if bg_tex:
		var bg = TextureRect.new()
		bg.texture = bg_tex
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_SCALE
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.show_behind_parent = true
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg)
		move_child(bg, 0)
		
		# Yazıların okunabilir olması için yarı saydam siyah bir katman
		var overlay = ColorRect.new()
		overlay.color = Color(0, 0, 0, 0.35)
		overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
		overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(overlay)
		move_child(overlay, 1)
		
	var title = get_node_or_null("Title")
	if title:
		var tween = create_tween().set_loops()
		tween.tween_property(title, "modulate:a", 0.0, 0.8).set_trans(Tween.TRANS_SINE)
		tween.tween_property(title, "modulate:a", 1.0, 0.8).set_trans(Tween.TRANS_SINE)
		
	if start_button:
		var btn_tween1 = create_tween().set_loops()
		btn_tween1.tween_property(start_button, "modulate", Color(0.8, 0.5, 0.0, 0.85), 0.6).set_trans(Tween.TRANS_SINE)
		btn_tween1.tween_property(start_button, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.6).set_trans(Tween.TRANS_SINE)
		
	if settings_button:
		var set_tween = create_tween().set_loops()
		# Daha koyu gri tonları
		set_tween.tween_property(settings_button, "modulate", Color(0.4, 0.4, 0.4, 0.8), 0.8).set_trans(Tween.TRANS_SINE)
		set_tween.tween_property(settings_button, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.8).set_trans(Tween.TRANS_SINE)
		
	# Çözünürlük Ayarları — liste ve seçili öğe Settings'ten geliyor, pencere
	# boyutuna bakıp tahmin etmiyoruz.
	for label in Settings.RESOLUTION_LABELS:
		res_option.add_item(label)
	res_option.add_item(Settings.FULLSCREEN_LABEL)
	res_option.selected = Settings.resolution_index
	res_option.item_selected.connect(_on_resolution_selected)

	if map_option:
		map_option.visible = false
	# Başlat ve Ayarlar Butonları
	if start_button:
		start_button.pressed.connect(_on_start_pressed)
	if settings_button:
		settings_button.pressed.connect(_on_settings_pressed)
	close_settings_button.pressed.connect(_on_close_settings_pressed)
	
	# Ayarları HSlider'lara yükle ve Label'ları güncelle
	if get_node_or_null("/root/Settings"):
		hs_dir.value = Settings.prob_direction_change
		hs_atk.value = Settings.prob_attack_decision
		hs_hp_mult.value = Settings.arena_hp_multiplier
		hs_pred.value = Settings.prob_predictive_aim
		hs_perf.value = Settings.prob_perfect_aim
		chk_dev_mode.button_pressed = Settings.developer_mode
		
	# Slider değer değişimlerini bağla
	_connect_slider(hs_dir, lbl_dir)
	_connect_slider(hs_atk, lbl_atk)
	_connect_slider(hs_hp_mult, lbl_hp_mult)
	_connect_slider(hs_pred, lbl_pred)
	_connect_slider(hs_perf, lbl_perf)

func _connect_slider(slider: HSlider, label: Label) -> void:
	# Başlangıç değerini yaz
	label.text = str(slider.value)
	# Değer değiştikçe yazıyı güncelle
	slider.value_changed.connect(func(v: float): label.text = str(v))

func _on_settings_pressed() -> void:
	settings_panel.visible = true

func _on_resolution_selected(index: int) -> void:
	Settings.resolution_index = index
	Settings.apply_resolution()
	Settings.save_settings()

func _on_close_settings_pressed() -> void:
	# HSlider'lardaki değerleri Settings autoload'una kaydet ve diske yaz
	if get_node_or_null("/root/Settings"):
		Settings.prob_direction_change = float(hs_dir.value)
		Settings.prob_attack_decision = float(hs_atk.value)
		Settings.arena_hp_multiplier = float(hs_hp_mult.value)
		Settings.prob_predictive_aim = float(hs_pred.value)
		Settings.prob_perfect_aim = float(hs_perf.value)
		Settings.developer_mode = chk_dev_mode.button_pressed
		Settings.save_settings()

	settings_panel.visible = false

func _on_start_pressed() -> void:
	if get_node_or_null("/root/Global"):
		get_node("/root/Global").is_multiplayer_host = true
	get_tree().change_scene_to_file(GameResources.LOBBY_PATH)

extends SceneTree

func _init():
	var theme = Theme.new()
	var font = load("res://assets/fonts/PressStart2P-Regular.ttf")
	if font:
		theme.default_font = font
		theme.default_font_size = 16
	else:
		print("Could not load font!")
	
	var normal_style = StyleBoxFlat.new()
	normal_style.bg_color = Color(0, 0, 0, 0) # Şeffaf
	
	var hover_style = normal_style.duplicate()
	hover_style.bg_color = Color(0, 0, 0, 0)
	
	var pressed_style = normal_style.duplicate()
	pressed_style.bg_color = Color(0, 0, 0, 0)
	
	theme.set_stylebox("normal", "Button", normal_style)
	theme.set_stylebox("hover", "Button", hover_style)
	theme.set_stylebox("pressed", "Button", pressed_style)
	theme.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	
	# Font renklerini ayarla
	theme.set_color("font_color", "Button", Color("ffffff"))
	theme.set_color("font_hover_color", "Button", Color("ffd700"))
	theme.set_color("font_pressed_color", "Button", Color("ff0000"))
	
	var panel_style = StyleBoxFlat.new()
	panel_style.bg_color = Color("000000cc")
	panel_style.border_width_bottom = 4
	panel_style.border_width_left = 4
	panel_style.border_width_right = 4
	panel_style.border_width_top = 4
	panel_style.border_color = Color("ffffff")
	panel_style.anti_aliasing = false
	theme.set_stylebox("panel", "Panel", panel_style)
	theme.set_stylebox("panel", "PanelContainer", panel_style)
	
	var dir = DirAccess.open("res://")
	if not dir.dir_exists("assets/themes"):
		dir.make_dir_recursive("assets/themes")
		
	var err = ResourceSaver.save(theme, "res://assets/themes/pixel_theme.tres")
	if err == OK:
		print("Theme created successfully!")
	else:
		print("Error saving theme: ", err)
		
	quit()

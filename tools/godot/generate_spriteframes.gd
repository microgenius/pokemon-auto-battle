extends SceneTree

func _init():
	print("Starting SpriteFrames generation...")
	var ids = ["0001", "0002", "0003", "0004", "0005", "0006", "0007", "0008", "0009", "0063", "0064", "0065", "0092", "0093", "0094"]
	var anims_to_load = ["Walk", "Hop", "Idle"]
	
	for pid in ids:
		var xml_path = "res://assets/pokemon_sprites/" + pid + "/AnimData.xml"
		
		var file = FileAccess.open(xml_path, FileAccess.READ)
		if not file:
			print("Could not open XML: " + xml_path)
			continue
			
		var xml_content = file.get_as_text()
		file.close()
		
		var parser = XMLParser.new()
		parser.open(xml_path)
		
		var sprite_frames = SpriteFrames.new()
		sprite_frames.remove_animation("default")
		
		var current_anim_name = ""
		var frame_width = 0
		var frame_height = 0
		var durations = []
		var in_durations = false
		
		while parser.read() == OK:
			if parser.get_node_type() == XMLParser.NODE_ELEMENT:
				var node_name = parser.get_node_name()
				if node_name == "Anim":
					current_anim_name = ""
					frame_width = 0
					frame_height = 0
					durations = []
					in_durations = false
				elif node_name == "Name":
					parser.read()
					current_anim_name = parser.get_node_data()
				elif node_name == "FrameWidth":
					parser.read()
					frame_width = parser.get_node_data().to_int()
				elif node_name == "FrameHeight":
					parser.read()
					frame_height = parser.get_node_data().to_int()
				elif node_name == "Durations":
					in_durations = true
				elif node_name == "Duration" and in_durations:
					parser.read()
					durations.append(parser.get_node_data().to_int())
			elif parser.get_node_type() == XMLParser.NODE_ELEMENT_END:
				if parser.get_node_name() == "Durations":
					in_durations = false
				elif parser.get_node_name() == "Anim":
					if current_anim_name in anims_to_load:
						var tex_path = "res://assets/pokemon_sprites/" + pid + "/" + current_anim_name + "-Anim.png"
						if ResourceLoader.exists(tex_path):
							var tex = load(tex_path)
							if tex:
								sprite_frames.add_animation(current_anim_name)
								sprite_frames.set_animation_loop(current_anim_name, true)
								# PMD animations are typically 60fps, durations are in frames. 
								# Let's just set a default FPS for now, e.g., 10 fps
								sprite_frames.set_animation_speed(current_anim_name, 10.0)
								
								# Directions are usually Y axis. Let's just grab the first row (Down direction)
								# The XML tells us how many frames there are via the length of durations array.
								var num_frames = durations.size()
								for i in range(num_frames):
									var atlas = AtlasTexture.new()
									atlas.atlas = tex
									# row 0 (down), col i
									atlas.region = Rect2(i * frame_width, 0, frame_width, frame_height)
									sprite_frames.add_frame(current_anim_name, atlas)
								print("Added animation " + current_anim_name + " for " + pid + " with " + str(num_frames) + " frames.")
							else:
								print("Could not load texture: " + tex_path)
						else:
							print("Texture does not exist: " + tex_path)
							
		# Save the SpriteFrames resource
		var save_path = "res://assets/pokemon_sprites/" + pid + "/sprite_frames.tres"
		ResourceSaver.save(sprite_frames, save_path)
		print("Saved SpriteFrames for " + pid + " to " + save_path)

	print("Finished SpriteFrames generation.")
	quit()

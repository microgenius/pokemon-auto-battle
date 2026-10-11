# Run from anywhere: all asset paths below are relative to the project root.
import os as _os
_os.chdir(_os.path.join(_os.path.dirname(_os.path.abspath(__file__)), ".."))

import os
import xml.etree.ElementTree as ET

ids = ["0001", "0002", "0003", "0004", "0005", "0006", "0007", "0008", "0009", "0063", "0064", "0065", "0092", "0093", "0094"]
anims_to_load = ["Walk", "Hop", "Idle", "Attack"]
directions = {
    "Down": 0,
    "BottomRight": 1,
    "Right": 2,
    "TopRight": 3,
    "Up": 4,
    "TopLeft": 5,
    "Left": 6,
    "BottomLeft": 7
}

for pid in ids:
    xml_path = f"assets/pokemon_sprites/{pid}/AnimData.xml"
    if not os.path.exists(xml_path):
        continue
        
    tree = ET.parse(xml_path)
    root = tree.getroot()
    
    animations = []
    
    sub_resources = ""
    resource_section = "[resource]\nanimations = ["
    ext_resources = ""
    
    ext_idx = 1
    sub_idx = 1
    
    for anim_node in root.findall(".//Anim"):
        name = anim_node.find("Name").text
        if name not in anims_to_load:
            continue
            
        frame_width_elem = anim_node.find("FrameWidth")
        frame_height_elem = anim_node.find("FrameHeight")
        
        if frame_width_elem is None or frame_height_elem is None:
            continue
            
        frame_width = int(frame_width_elem.text)
        frame_height = int(frame_height_elem.text)
        durations = [int(d.text) for d in anim_node.findall(".//Duration")]
        
        # Add ext resource
        png_path = f"res://assets/pokemon_sprites/{pid}/{name}-Anim.png"
        ext_resources += f'[ext_resource type="Texture2D" path="{png_path}" id="{ext_idx}_tex"]\n'
        
        for dir_name, row in directions.items():
            frames_json = ""
            for i in range(len(durations)):
                sub_resources += f'[sub_resource type="AtlasTexture" id="AtlasTexture_{sub_idx}"]\n'
                sub_resources += f'atlas = ExtResource("{ext_idx}_tex")\n'
                sub_resources += f'region = Rect2({i * frame_width}, {row * frame_height}, {frame_width}, {frame_height})\n\n'
                
                frames_json += '{\n"duration": 1.0,\n'
                frames_json += f'"texture": SubResource("AtlasTexture_{sub_idx}")\n'
                frames_json += '}, '
                sub_idx += 1
                
            frames_json = frames_json.rstrip(", ")
            
            anim_str = '{\n"frames": [' + frames_json + '],\n'
            anim_str += '"loop": true,\n'
            anim_str += f'"name": &"{name}_{dir_name}",\n'
            anim_str += '"speed": 10.0\n}, '
            
            resource_section += anim_str
            
        ext_idx += 1
        
    resource_section = resource_section.rstrip(", ")
    resource_section += "]"
    
    # Write to .tres
    tres_path = f"assets/pokemon_sprites/{pid}/sprite_frames.tres"
    with open(tres_path, "w") as f:
        f.write(f'[gd_resource type="SpriteFrames" load_steps={sub_idx + ext_idx} format=3]\n\n')
        f.write(ext_resources + "\n")
        f.write(sub_resources)
        f.write(resource_section)
    print(f"Generated {tres_path}")

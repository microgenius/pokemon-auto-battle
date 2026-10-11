extends Node
## Autoload: static game data plus per-session state.
##
## Responsibility split with Settings.gd:
##   Global.gd   — the species database, attack table and type chart (loaded
##                 once, never mutated) and session state that must NOT persist
##                 across restarts.
##   Settings.gd — player-chosen configuration, saved to user://settings.cfg.
##
## Player-facing config (roster, map, tuning knobs, server address) lives in
## Settings. Do not add it here.

## True when this client is the match host driving the simulation. Session-only:
## deliberately not persisted, so a crashed host does not relaunch as host.
var is_multiplayer_host: bool = false

## pokemon_id ("0025") -> species record from pokemon_advanced_data.json
var pokemon_db: Dictionary = {}

var attacks_db: Dictionary = {
	"normal": [
		{"name": "Tackle", "power": 40, "is_special": false},
		{"name": "Swift", "power": 60, "is_special": true},
		{"name": "Hyper Beam", "power": 150, "is_special": true}
	],
	"fire": [
		{"name": "Ember", "power": 40, "is_special": true},
		{"name": "Fire Punch", "power": 75, "is_special": false},
		{"name": "Fire Blast", "power": 110, "is_special": true}
	],
	"water": [
		{"name": "Water Gun", "power": 40, "is_special": true},
		{"name": "Bubble Beam", "power": 65, "is_special": true},
		{"name": "Hydro Pump", "power": 110, "is_special": true}
	],
	"grass": [
		{"name": "Vine Whip", "power": 45, "is_special": false},
		{"name": "Razor Leaf", "power": 55, "is_special": false},
		{"name": "Solar Beam", "power": 120, "is_special": true}
	],
	"electric": [
		{"name": "Thunder Shock", "power": 40, "is_special": true},
		{"name": "Spark", "power": 65, "is_special": false},
		{"name": "Thunder", "power": 110, "is_special": true}
	],
	"ice": [
		{"name": "Powder Snow", "power": 40, "is_special": true},
		{"name": "Ice Punch", "power": 75, "is_special": false},
		{"name": "Blizzard", "power": 110, "is_special": true}
	],
	"fighting": [
		{"name": "Karate Chop", "power": 50, "is_special": false},
		{"name": "Submission", "power": 80, "is_special": false},
		{"name": "Dynamic Punch", "power": 100, "is_special": false}
	],
	"poison": [
		{"name": "Smog", "power": 30, "is_special": true},
		{"name": "Sludge Bomb", "power": 90, "is_special": true},
		{"name": "Gunk Shot", "power": 120, "is_special": false}
	],
	"ground": [
		{"name": "Mud-Slap", "power": 20, "is_special": true},
		{"name": "Dig", "power": 80, "is_special": false},
		{"name": "Earthquake", "power": 100, "is_special": false}
	],
	"flying": [
		{"name": "Peck", "power": 35, "is_special": false},
		{"name": "Wing Attack", "power": 60, "is_special": false},
		{"name": "Sky Attack", "power": 140, "is_special": false}
	],
	"psychic": [
		{"name": "Confusion", "power": 50, "is_special": true},
		{"name": "Psybeam", "power": 65, "is_special": true},
		{"name": "Psychic", "power": 90, "is_special": true}
	],
	"bug": [
		{"name": "Pin Missile", "power": 25, "is_special": false},
		{"name": "Bug Bite", "power": 60, "is_special": false},
		{"name": "Megahorn", "power": 120, "is_special": false}
	],
	"rock": [
		{"name": "Rock Throw", "power": 50, "is_special": false},
		{"name": "Rock Slide", "power": 75, "is_special": false},
		{"name": "Stone Edge", "power": 100, "is_special": false}
	],
	"ghost": [
		{"name": "Lick", "power": 30, "is_special": false},
		{"name": "Night Shade", "power": 60, "is_special": true},
		{"name": "Shadow Ball", "power": 80, "is_special": true}
	],
	"dragon": [
		{"name": "Dragon Rage", "power": 40, "is_special": true},
		{"name": "Dragon Breath", "power": 60, "is_special": true},
		{"name": "Outrage", "power": 120, "is_special": false}
	],
	"dark": [
		{"name": "Bite", "power": 60, "is_special": false},
		{"name": "Faint Attack", "power": 60, "is_special": false},
		{"name": "Crunch", "power": 80, "is_special": false}
	],
	"steel": [
		{"name": "Metal Claw", "power": 50, "is_special": false},
		{"name": "Steel Wing", "power": 70, "is_special": false},
		{"name": "Iron Tail", "power": 100, "is_special": false}
	]
}

var type_chart: Dictionary = {
	"normal": {"rock": 0.5, "ghost": 0.0, "steel": 0.5},
	"fire": {"fire": 0.5, "water": 0.5, "grass": 2.0, "ice": 2.0, "bug": 2.0, "rock": 0.5, "dragon": 0.5, "steel": 2.0},
	"water": {"fire": 2.0, "water": 0.5, "grass": 0.5, "ground": 2.0, "rock": 2.0, "dragon": 0.5},
	"grass": {"fire": 0.5, "water": 2.0, "grass": 0.5, "poison": 0.5, "ground": 2.0, "flying": 0.5, "bug": 0.5, "rock": 2.0, "dragon": 0.5, "steel": 0.5},
	"electric": {"water": 2.0, "grass": 0.5, "electric": 0.5, "ground": 0.0, "flying": 2.0, "dragon": 0.5},
	"ice": {"fire": 0.5, "water": 0.5, "grass": 2.0, "ice": 0.5, "ground": 2.0, "flying": 2.0, "dragon": 2.0, "steel": 0.5},
	"fighting": {"normal": 2.0, "ice": 2.0, "poison": 0.5, "flying": 0.5, "psychic": 0.5, "bug": 0.5, "rock": 2.0, "ghost": 0.0, "dark": 2.0, "steel": 2.0},
	"poison": {"grass": 2.0, "poison": 0.5, "ground": 0.5, "rock": 0.5, "ghost": 0.5, "steel": 0.0},
	"ground": {"fire": 2.0, "grass": 0.5, "electric": 2.0, "poison": 2.0, "flying": 0.0, "bug": 0.5, "rock": 2.0, "steel": 2.0},
	"flying": {"electric": 0.5, "grass": 2.0, "fighting": 2.0, "bug": 2.0, "rock": 0.5, "steel": 0.5},
	"psychic": {"fighting": 2.0, "poison": 2.0, "psychic": 0.5, "dark": 0.0, "steel": 0.5},
	"bug": {"fire": 0.5, "grass": 2.0, "fighting": 0.5, "poison": 0.5, "flying": 0.5, "psychic": 2.0, "ghost": 0.5, "dark": 2.0, "steel": 0.5},
	"rock": {"fire": 2.0, "ice": 2.0, "fighting": 0.5, "ground": 0.5, "flying": 2.0, "bug": 2.0, "steel": 0.5},
	"ghost": {"normal": 0.0, "psychic": 2.0, "ghost": 2.0, "dark": 0.5},
	"dragon": {"dragon": 2.0, "steel": 0.5},
	"dark": {"fighting": 0.5, "psychic": 2.0, "ghost": 2.0, "dark": 0.5},
	"steel": {"fire": 0.5, "water": 0.5, "electric": 0.5, "ice": 2.0, "rock": 2.0, "steel": 0.5}
}

func _ready() -> void:
	load_pokemon_data()

func load_pokemon_data() -> void:
	var file = FileAccess.open("res://assets/pokemon_advanced_data.json", FileAccess.READ)
	if file:
		var content = file.get_as_text()
		var json = JSON.new()
		var error = json.parse(content)
		if error == OK:
			var data_array = json.data
			for item in data_array:
				var pid_str = "%04d" % int(item["id"])
				pokemon_db[pid_str] = item
		else:
			print("JSON Parse Error in pokemon_advanced_data: ", json.get_error_message())

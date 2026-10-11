extends Node2D
class_name Pokeball

signal pokemon_ready(spawn_position: Vector2)

@onready var timer: Timer = $IncubationTimer

func _ready() -> void:
	# Rastgele bir kuluçka süresi (örneğin 2-4 saniye)
	var incubation_time = randf_range(2.0, 4.0)
	timer.wait_time = incubation_time
	timer.start()

func _on_incubation_timer_timeout() -> void:
	# Süre doldu, pokemonu spawn etmesi için sinyal gönder
	pokemon_ready.emit(global_position)
	# Kendini yok et
	queue_free()

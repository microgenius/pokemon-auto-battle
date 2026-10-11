extends Node2D

@onready var particles: CPUParticles2D = $CPUParticles2D
@onready var timer: Timer = $Timer

func _ready() -> void:
	particles.color = Color(randf_range(0.5, 1.0), randf_range(0.5, 1.0), randf_range(0.5, 1.0))
	particles.emitting = true
	timer.start()

func _on_timer_timeout() -> void:
	queue_free()

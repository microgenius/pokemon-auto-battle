extends CharacterBody2D
class_name AttackProjectile

@export var attack_color: Color = Color.WHITE
@export var speed: float = 200.0
@export var damage: float = 20.0
@export var max_bounces: int = 3
@export var bounce_lifetime: float = 0.5

@onready var sprite: Sprite2D = $Sprite2D

var target: Node2D = null
var shooter: Node2D = null

var bounce_count: int = 0
var bounce_timer: float = 0.0
var is_bouncing: bool = false
var initial_lifetime: float = 0.0

var predicted_target_pos: Vector2 = Vector2.INF
var is_sharp_eye_shot: bool = false
var attack_name: String = "Saldırı"
var attack_type: String = "normal"
var is_special: bool = false
var attack_power: float = 40.0

# Animasyon
var anim_time: float = 0.0
var trail_positions: Array = []

# Tip renkleri
var type_colors: Dictionary = {
	"normal": [Color(0.9, 0.9, 0.85), Color(0.7, 0.7, 0.65)],
	"fire": [Color(1.0, 0.6, 0.1), Color(1.0, 0.2, 0.0)],
	"water": [Color(0.3, 0.6, 1.0), Color(0.1, 0.3, 0.9)],
	"grass": [Color(0.3, 0.9, 0.3), Color(0.1, 0.6, 0.1)],
	"electric": [Color(1.0, 0.95, 0.2), Color(1.0, 0.8, 0.0)],
	"ice": [Color(0.6, 0.9, 1.0), Color(0.3, 0.7, 0.95)],
	"fighting": [Color(0.85, 0.35, 0.2), Color(0.6, 0.15, 0.1)],
	"poison": [Color(0.7, 0.2, 0.8), Color(0.5, 0.1, 0.6)],
	"ground": [Color(0.8, 0.6, 0.3), Color(0.6, 0.4, 0.2)],
	"flying": [Color(0.6, 0.7, 1.0), Color(0.4, 0.5, 0.85)],
	"psychic": [Color(1.0, 0.4, 0.7), Color(0.8, 0.2, 0.5)],
	"bug": [Color(0.6, 0.8, 0.2), Color(0.4, 0.6, 0.1)],
	"rock": [Color(0.7, 0.6, 0.4), Color(0.5, 0.4, 0.25)],
	"ghost": [Color(0.5, 0.3, 0.7), Color(0.3, 0.1, 0.5)],
	"dragon": [Color(0.4, 0.3, 0.9), Color(0.6, 0.2, 0.8)],
	"dark": [Color(0.35, 0.25, 0.2), Color(0.15, 0.1, 0.1)],
	"steel": [Color(0.75, 0.75, 0.8), Color(0.5, 0.5, 0.6)]
}

func _ready() -> void:
	# Sprite'ı gizle, biz _draw ile çizeceğiz
	if sprite:
		sprite.visible = false
	
	if is_instance_valid(shooter):
		add_collision_exception_with(shooter)
	
	if is_instance_valid(target):
		if is_sharp_eye_shot:
			speed = 900.0
			
		var aim_pos = target.global_position
		if predicted_target_pos != Vector2.INF:
			aim_pos = predicted_target_pos
			
		var direction = global_position.direction_to(aim_pos)
		velocity = direction * speed
		rotation = direction.angle()
		
		var distance = global_position.distance_to(aim_pos)
		initial_lifetime = (distance + 200.0) / speed
	else:
		queue_free()

func _physics_process(delta: float) -> void:
	anim_time += delta
	
	# İz pozisyonlarını kaydet
	trail_positions.push_front(global_position)
	if trail_positions.size() > 6:
		trail_positions.pop_back()
	
	if is_bouncing:
		bounce_timer -= delta
		if bounce_timer <= 0:
			queue_free()
			return
	else:
		initial_lifetime -= delta
		if initial_lifetime <= 0:
			queue_free()
			return
			
	var collision = move_and_collide(velocity * delta)
	
	if collision:
		var collider = collision.get_collider()
		
		if collider.has_method("take_damage") and collider != shooter:
			# A shielded target eats the shot whole: no damage, and no credit for
			# a hit that never landed.
			if collider.has_method("is_shielded") and collider.is_shielded():
				_spawn_shield_impact(collision.get_position())
				queue_free()
				return

			var valid_shooter = shooter if is_instance_valid(shooter) else null
			if valid_shooter:
				valid_shooter.successful_hits += 1
				if is_sharp_eye_shot:
					valid_shooter.total_criticals += 1
				if is_instance_valid(valid_shooter.game_manager):
					valid_shooter.game_manager.register_first_hit(valid_shooter, collider)
			collider.take_damage(damage, valid_shooter, attack_name, attack_type, is_special, is_sharp_eye_shot)
			
			if is_sharp_eye_shot and is_instance_valid(shooter):
				FloatingText.spawn(get_tree().current_scene, shooter.global_position, "SHARP EYE", Color.GOLD)

			queue_free()
		else:
			if bounce_count < max_bounces:
				bounce_count += 1
				velocity = velocity.bounce(collision.get_normal())
				rotation = velocity.angle()
				is_bouncing = true
				bounce_timer = bounce_lifetime
			else:
				queue_free()
	
	queue_redraw()

func get_proj_scale() -> float:
	# Saldırı gücüne göre mermi boyutu (power 20-150 arası)
	return clamp(attack_power / 60.0, 0.6, 2.5)

func get_colors() -> Array:
	if type_colors.has(attack_type):
		return type_colors[attack_type]
	return [Color.WHITE, Color.GRAY]

func _draw() -> void:
	var s = get_proj_scale()
	var colors = get_colors()
	var c1 = colors[0]  # Ana renk
	var c2 = colors[1]  # Koyu/ikincil renk
	var pulse = sin(anim_time * 12.0) * 0.15
	
	# Arkadaki iz (trail) çizimi - lokal koordinatlara çevir
	for i in range(trail_positions.size()):
		var trail_pos = trail_positions[i]
		var local_trail = (trail_pos - global_position).rotated(-rotation)
		var alpha = 0.3 - (float(i) / trail_positions.size()) * 0.3
		var trail_size = s * 3.0 * (1.0 - float(i) / trail_positions.size())
		var trail_color = Color(c1.r, c1.g, c1.b, alpha)
		draw_circle(local_trail, trail_size, trail_color)
	
	match attack_type:
		"fire":
			_draw_fire(s, c1, c2, pulse)
		"water":
			_draw_water(s, c1, c2, pulse)
		"grass":
			_draw_grass(s, c1, c2, pulse)
		"electric":
			_draw_electric(s, c1, c2, pulse)
		"ice":
			_draw_ice(s, c1, c2, pulse)
		"fighting":
			_draw_fighting(s, c1, c2, pulse)
		"poison":
			_draw_poison(s, c1, c2, pulse)
		"ground":
			_draw_ground(s, c1, c2, pulse)
		"flying":
			_draw_flying(s, c1, c2, pulse)
		"psychic":
			_draw_psychic(s, c1, c2, pulse)
		"bug":
			_draw_bug(s, c1, c2, pulse)
		"rock":
			_draw_rock(s, c1, c2, pulse)
		"ghost":
			_draw_ghost(s, c1, c2, pulse)
		"dragon":
			_draw_dragon(s, c1, c2, pulse)
		"dark":
			_draw_dark(s, c1, c2, pulse)
		"steel":
			_draw_steel(s, c1, c2, pulse)
		_:
			_draw_normal(s, c1, c2, pulse)

# ===== TİP BAZLI ÇİZİMLER =====

func _draw_fire(s: float, c1: Color, c2: Color, pulse: float) -> void:
	# Ateş topu - titreşen alevler
	var base_r = 5.0 * s
	draw_circle(Vector2.ZERO, base_r + 2.0 + pulse * 3.0, Color(c2, 0.4))
	draw_circle(Vector2.ZERO, base_r, c2)
	draw_circle(Vector2.ZERO, base_r * 0.7, c1)
	draw_circle(Vector2.ZERO, base_r * 0.35, Color(1.0, 1.0, 0.5))
	# Küçük alev parçacıkları
	for i in range(3):
		var angle = anim_time * 5.0 + i * TAU / 3.0
		var flicker = Vector2(cos(angle) * base_r * 0.8, sin(angle) * base_r * 0.8)
		draw_circle(flicker, 2.0 * s, Color(c1, 0.6))

func _draw_water(s: float, c1: Color, c2: Color, pulse: float) -> void:
	# Su damlası / dalga
	var base_r = 5.0 * s
	# Dış halka
	draw_circle(Vector2.ZERO, base_r + 1.0, Color(c2, 0.5))
	# Ana damla
	var points: PackedVector2Array = []
	for i in range(12):
		var angle = float(i) / 12.0 * TAU
		var r = base_r * (1.0 + sin(angle * 2.0 + anim_time * 6.0) * 0.2)
		points.append(Vector2(cos(angle) * r, sin(angle) * r))
	draw_colored_polygon(points, c1)
	draw_circle(Vector2.ZERO, base_r * 0.4, Color(0.7, 0.9, 1.0, 0.8))

func _draw_grass(s: float, c1: Color, c2: Color, pulse: float) -> void:
	# Yaprak şekli
	var base_r = 6.0 * s
	# Yaprak gövdesi
	var leaf_points: PackedVector2Array = [
		Vector2(-base_r, 0),
		Vector2(-base_r * 0.3, -base_r * 0.5),
		Vector2(base_r, 0),
		Vector2(-base_r * 0.3, base_r * 0.5)
	]
	draw_colored_polygon(leaf_points, c1)
	# Orta damar
	draw_line(Vector2(-base_r * 0.8, 0), Vector2(base_r * 0.6, 0), c2, 1.5)
	# Yaprak ucu parıltı
	draw_circle(Vector2(base_r * 0.7, 0), 2.0 * s, Color(0.8, 1.0, 0.5, 0.6 + pulse))

func _draw_electric(s: float, c1: Color, c2: Color, pulse: float) -> void:
	# Şimşek / Yıldırım
	var base_r = 6.0 * s
	# Parlak çekirdek
	draw_circle(Vector2.ZERO, base_r * 0.5, Color(1.0, 1.0, 0.8, 0.8))
	# Zigzag şimşekler
	for i in range(4):
		var angle = anim_time * 8.0 + i * TAU / 4.0
		var end_x = cos(angle) * base_r
		var end_y = sin(angle) * base_r
		var mid_x = end_x * 0.5 + sin(anim_time * 15.0 + i) * 3.0
		var mid_y = end_y * 0.5 + cos(anim_time * 15.0 + i) * 3.0
		draw_line(Vector2.ZERO, Vector2(mid_x, mid_y), c1, 2.0 * s)
		draw_line(Vector2(mid_x, mid_y), Vector2(end_x, end_y), c2, 1.5 * s)
	# Merkez parıltı
	draw_circle(Vector2.ZERO, 3.0 * s + pulse * 2.0, c1)

func _draw_ice(s: float, c1: Color, c2: Color, pulse: float) -> void:
	# Buz kristali / Kar tanesi
	var base_r = 5.0 * s
	# 6 kollu kristal
	for i in range(6):
		var angle = float(i) / 6.0 * TAU + anim_time * 1.5
		var end = Vector2(cos(angle) * base_r, sin(angle) * base_r)
		draw_line(Vector2.ZERO, end, c1, 2.0 * s)
		# Küçük çapraz dallar
		var mid = end * 0.6
		var perp = Vector2(-sin(angle), cos(angle)) * base_r * 0.3
		draw_line(mid, mid + perp, c2, 1.0 * s)
		draw_line(mid, mid - perp, c2, 1.0 * s)
	# Merkez parıltı
	draw_circle(Vector2.ZERO, 2.5 * s, Color(0.9, 0.95, 1.0, 0.7 + pulse))

func _draw_fighting(s: float, c1: Color, c2: Color, pulse: float) -> void:
	# Yumruk / El şekli
	var base_r = 6.0 * s
	# Ana yumruk (oval)
	var fist_points: PackedVector2Array = []
	for i in range(16):
		var angle = float(i) / 16.0 * TAU
		var rx = base_r * 0.9
		var ry = base_r * 0.7
		fist_points.append(Vector2(cos(angle) * rx, sin(angle) * ry))
	draw_colored_polygon(fist_points, c1)
	# Parmak boğumları
	draw_circle(Vector2(base_r * 0.3, -base_r * 0.35), 2.0 * s, c2)
	draw_circle(Vector2(base_r * 0.0, -base_r * 0.4), 2.0 * s, c2)
	draw_circle(Vector2(-base_r * 0.3, -base_r * 0.35), 2.0 * s, c2)
	# Darbe dalgası
	draw_arc(Vector2(base_r * 0.5, 0), base_r * 0.6 + pulse * 4.0, -PI/3, PI/3, 8, Color(1.0, 0.9, 0.6, 0.5), 1.5 * s)

func _draw_poison(s: float, c1: Color, c2: Color, pulse: float) -> void:
	# Zehir damlası - kabarcıklı
	var base_r = 5.0 * s
	# Ana küre
	draw_circle(Vector2.ZERO, base_r + pulse * 2.0, c2)
	draw_circle(Vector2.ZERO, base_r * 0.75, c1)
	# Zehir kabarcıkları
	for i in range(4):
		var angle = anim_time * 3.0 + i * TAU / 4.0
		var dist = base_r * 0.6
		var bub_pos = Vector2(cos(angle) * dist, sin(angle) * dist)
		draw_circle(bub_pos, 1.5 * s, Color(c1.r, c1.g, c1.b, 0.5))
	# Duman efekti
	draw_circle(Vector2(-base_r * 0.5, -base_r * 0.3), 2.0 * s, Color(c2, 0.3))

func _draw_ground(s: float, c1: Color, c2: Color, pulse: float) -> void:
	# Toprak / Kaya parçası
	var base_r = 5.0 * s
	# Düzensiz kaya şekli
	var rock_points: PackedVector2Array = [
		Vector2(-base_r, -base_r * 0.3),
		Vector2(-base_r * 0.4, -base_r * 0.8),
		Vector2(base_r * 0.5, -base_r * 0.7),
		Vector2(base_r, -base_r * 0.1),
		Vector2(base_r * 0.6, base_r * 0.6),
		Vector2(-base_r * 0.2, base_r * 0.7),
		Vector2(-base_r * 0.8, base_r * 0.3)
	]
	draw_colored_polygon(rock_points, c1)
	# Çatlak çizgileri
	draw_line(Vector2(-base_r * 0.3, -base_r * 0.2), Vector2(base_r * 0.2, base_r * 0.3), c2, 1.0)
	# Toz bulutu
	draw_circle(Vector2(-base_r * 0.8, 0), 2.5 * s, Color(c1, 0.3))

func _draw_flying(s: float, c1: Color, c2: Color, pulse: float) -> void:
	# Rüzgar bıçağı / Hava dalgası
	var base_r = 6.0 * s
	# Kavisli rüzgar çizgileri
	for i in range(3):
		var offset_y = (i - 1) * base_r * 0.5
		var wave = sin(anim_time * 8.0 + i * 1.5) * 2.0
		draw_line(
			Vector2(-base_r, offset_y + wave),
			Vector2(base_r, offset_y - wave),
			Color(c1, 0.7 - i * 0.15), 2.0 * s
		)
	# Merkez hava akımı
	draw_circle(Vector2.ZERO, 3.0 * s, Color(c1, 0.5 + pulse))

func _draw_psychic(s: float, c1: Color, c2: Color, pulse: float) -> void:
	# Psişik enerji küresi - dönen halkalar
	var base_r = 5.0 * s
	# Dış enerji halkası
	draw_arc(Vector2.ZERO, base_r + 2.0, anim_time * 4.0, anim_time * 4.0 + PI * 1.5, 16, Color(c2, 0.4), 1.5 * s)
	# İç halka (ters yönde döner)
	draw_arc(Vector2.ZERO, base_r * 0.6, -anim_time * 6.0, -anim_time * 6.0 + PI, 12, Color(c1, 0.6), 2.0 * s)
	# Merkez parıltı
	draw_circle(Vector2.ZERO, base_r * 0.4 + pulse * 2.0, c1)
	draw_circle(Vector2.ZERO, base_r * 0.2, Color(1.0, 0.8, 1.0, 0.8))

func _draw_bug(s: float, c1: Color, c2: Color, pulse: float) -> void:
	# Böcek iğnesi / Kıskaç
	var base_r = 5.0 * s
	# İğne gövdesi
	var stinger: PackedVector2Array = [
		Vector2(-base_r, -base_r * 0.3),
		Vector2(base_r, 0),
		Vector2(-base_r, base_r * 0.3)
	]
	draw_colored_polygon(stinger, c1)
	# İğne ucu
	draw_circle(Vector2(base_r * 0.8, 0), 1.5 * s, Color(0.9, 1.0, 0.3))
	# Kanat parıltısı
	draw_circle(Vector2(-base_r * 0.3, -base_r * 0.4), 2.0 * s, Color(c1, 0.4 + pulse))
	draw_circle(Vector2(-base_r * 0.3, base_r * 0.4), 2.0 * s, Color(c1, 0.4 + pulse))

func _draw_rock(s: float, c1: Color, c2: Color, pulse: float) -> void:
	# Kaya parçası - köşeli
	var base_r = 5.5 * s
	# Ana kaya
	var rock: PackedVector2Array = [
		Vector2(-base_r * 0.6, -base_r * 0.8),
		Vector2(base_r * 0.4, -base_r * 0.7),
		Vector2(base_r * 0.9, -base_r * 0.1),
		Vector2(base_r * 0.5, base_r * 0.7),
		Vector2(-base_r * 0.5, base_r * 0.6),
		Vector2(-base_r * 0.9, base_r * 0.1)
	]
	draw_colored_polygon(rock, c2)
	# Parlak yüzey
	var highlight: PackedVector2Array = [
		Vector2(-base_r * 0.4, -base_r * 0.6),
		Vector2(base_r * 0.2, -base_r * 0.5),
		Vector2(base_r * 0.1, base_r * 0.1),
		Vector2(-base_r * 0.5, base_r * 0.1)
	]
	draw_colored_polygon(highlight, c1)

func _draw_ghost(s: float, c1: Color, c2: Color, pulse: float) -> void:
	# Hayalet alevi - titreşen mor ateş
	var base_r = 5.0 * s
	# Dış gölge (yarı saydam)
	draw_circle(Vector2.ZERO, base_r + 3.0 + pulse * 4.0, Color(c2, 0.2))
	# Ana küre (yarı saydam)
	draw_circle(Vector2.ZERO, base_r, Color(c1, 0.7))
	# İç ışık
	draw_circle(Vector2.ZERO, base_r * 0.5, Color(0.8, 0.6, 1.0, 0.6 + pulse))
	# Hayalet kuyruk
	for i in range(3):
		var angle = anim_time * 4.0 + i * TAU / 3.0
		var wisp = Vector2(cos(angle) * base_r * 1.2, sin(angle) * base_r * 1.2)
		draw_circle(wisp, 1.5 * s, Color(c1, 0.3))

func _draw_dragon(s: float, c1: Color, c2: Color, pulse: float) -> void:
	# Ejderha alevi - mavi/mor spiral ateş
	var base_r = 6.0 * s
	# Spiral alev
	for i in range(8):
		var t = float(i) / 8.0
		var angle = t * TAU + anim_time * 6.0
		var r = base_r * t
		var pos = Vector2(cos(angle) * r * 0.5, sin(angle) * r * 0.5)
		var size = (1.0 - t * 0.5) * 3.0 * s
		draw_circle(pos, size, Color(c1.lerp(c2, t), 0.8 - t * 0.3))
	# Merkez
	draw_circle(Vector2.ZERO, 3.0 * s, Color(0.7, 0.5, 1.0, 0.9))
	draw_circle(Vector2.ZERO, 1.5 * s, Color(1.0, 0.8, 1.0))

func _draw_dark(s: float, c1: Color, c2: Color, pulse: float) -> void:
	# Karanlık enerji - siyah küre
	var base_r = 5.0 * s
	# Dış karanlık aura
	draw_circle(Vector2.ZERO, base_r + 2.0 + pulse * 3.0, Color(0.0, 0.0, 0.0, 0.3))
	# Ana küre
	draw_circle(Vector2.ZERO, base_r, c2)
	draw_circle(Vector2.ZERO, base_r * 0.6, c1)
	# Kırmızı göz efekti
	draw_circle(Vector2(0, 0), 2.0 * s, Color(0.8, 0.1, 0.1, 0.6 + pulse))

func _draw_steel(s: float, c1: Color, c2: Color, pulse: float) -> void:
	# Metal parça - dönen çelik yıldız
	var base_r = 5.0 * s
	var rot = anim_time * 4.0
	# Yıldız şekli (4 köşeli)
	var star: PackedVector2Array = []
	for i in range(8):
		var angle = float(i) / 8.0 * TAU + rot
		var r = base_r if i % 2 == 0 else base_r * 0.45
		star.append(Vector2(cos(angle) * r, sin(angle) * r))
	draw_colored_polygon(star, c1)
	# Metal parıltı
	draw_circle(Vector2.ZERO, base_r * 0.3, Color(0.95, 0.95, 1.0, 0.7 + pulse))

func _draw_normal(s: float, c1: Color, c2: Color, pulse: float) -> void:
	# Normal enerji küresi
	var base_r = 4.5 * s
	draw_circle(Vector2.ZERO, base_r + pulse * 2.0, Color(c2, 0.4))
	draw_circle(Vector2.ZERO, base_r, c1)
	draw_circle(Vector2.ZERO, base_r * 0.5, Color(1.0, 1.0, 1.0, 0.6))


## A small flash where a shot broke against an evolution bubble, so absorbing a
## hit reads as an event rather than the projectile just vanishing.
func _spawn_shield_impact(at: Vector2) -> void:
	if not is_inside_tree():
		return
	FloatingText.spawn(get_tree().current_scene, at, "BLOK", Color(0.55, 0.85, 1.0), -10.0)

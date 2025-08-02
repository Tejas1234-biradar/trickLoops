extends Node2D

# Fixed paths for your scene structure
@onready var camera = get_node("../Player/Camera2D")  # Camera is child of Player
@onready var dash_particles = $DashParticles
@onready var perfect_particles = $PerfectLandingParticles
@onready var glow = $SavedMoveGlow

var shake_intensity: float = 0.0
var shake_duration: float = 0.0
var original_camera_position: Vector2

# Enhanced zoom system variables
var base_zoom: Vector2 = Vector2(1.0, 1.0)
var speed_zoom: Vector2 = Vector2(1.0, 1.0)
var trick_zoom: Vector2 = Vector2(1.0, 1.0)
var final_zoom: Vector2 = Vector2(1.0, 1.0)

@export var speed_zoom_smoothing: float = 2.0
@export var trick_zoom_smoothing: float = 8.0
@export var final_zoom_smoothing: float = 5.0

# Speed-based zoom settings
var max_speed_zoom_out: float = 0.25
var speed_threshold: float = 200.0
var max_speed_for_zoom: float = 800.0

# Trick zoom settings
var is_trick_zooming: bool = false
var trick_zoom_tween: Tween

var player_node: Node2D

# Screen blur effects
var blur_canvas_layer: CanvasLayer
var blur_color_rect: ColorRect

# Simplified particle following system
var is_dashing: bool = false

func _ready():
	# Get player node
	player_node = get_node("../Player")
	
	# Connect to player signals with error checking
	if player_node.has_signal("Perfect_Landing"):
		player_node.connect("Perfect_Landing", Callable(self, "_on_perfect_landing"))
	if player_node.has_signal("Good_Landing"):
		player_node.connect("Good_Landing", Callable(self, "_on_good_landing"))
	if player_node.has_signal("did_trick"):
		player_node.connect("did_trick", Callable(self, "_on_did_trick"))
	if player_node.has_signal("chain_complete"):
		player_node.connect("chain_complete", Callable(self, "_on_chain_complete"))
	if player_node.has_signal("move_saved"):
		player_node.connect("move_saved", Callable(self, "_on_move_saved"))
	if player_node.has_signal("dash_start"):
		player_node.connect("dash_start", Callable(self, "_on_dash_start"))
	if player_node.has_signal("dash_end"):
		player_node.connect("dash_end", Callable(self, "_on_dash_end"))
	
	# Store the original camera position and zoom
	if camera:
		original_camera_position = camera.position
		base_zoom = camera.zoom
		speed_zoom = base_zoom
		trick_zoom = base_zoom
		final_zoom = base_zoom
	
	# Setup simplified particle effects
	setup_particle_effects()
	setup_blur_system()

func _process(delta):
	# Handle camera shake
	if shake_duration > 0:
		shake_duration -= delta
		if camera:
			var offset = Vector2(
				randf_range(-shake_intensity, shake_intensity),
				randf_range(-shake_intensity, shake_intensity)
			)
			camera.position = original_camera_position + offset
	else:
		if camera:
			camera.position = original_camera_position
	
	# Handle smooth zoom system
	if camera and player_node:
		update_smooth_zoom_system(delta)
	
	# Make dash particles follow player smoothly
	if player_node and is_dashing and dash_particles:
		dash_particles.global_position = player_node.global_position

func update_smooth_zoom_system(delta):
	update_speed_zoom(delta)
	
	var target_zoom = Vector2(
		speed_zoom.x * trick_zoom.x,
		speed_zoom.y * trick_zoom.y
	)
	
	final_zoom = final_zoom.lerp(target_zoom, final_zoom_smoothing * delta)
	camera.zoom = camera.zoom.lerp(final_zoom, final_zoom_smoothing * delta)

func update_speed_zoom(delta):
	var target_speed_zoom = base_zoom
	
	var velocity = Vector2.ZERO
	if player_node.has_method("get_velocity"):
		velocity = player_node.get_velocity()
	elif "velocity" in player_node:
		velocity = player_node.velocity
	
	var speed = velocity.length()
	
	if speed > speed_threshold:
		var speed_factor = (speed - speed_threshold) / (max_speed_for_zoom - speed_threshold)
		speed_factor = clamp(speed_factor, 0.0, 1.0)
		speed_factor = ease_out_cubic(speed_factor)
		var zoom_out_factor = 1.0 - (max_speed_zoom_out * speed_factor)
		target_speed_zoom = base_zoom * zoom_out_factor
	
	speed_zoom = speed_zoom.lerp(target_speed_zoom, speed_zoom_smoothing * delta)

func ease_out_cubic(x: float) -> float:
	return 1.0 - pow(1.0 - x, 3.0)

func smooth_trick_zoom_effect(zoom_intensity: float = 0.2, zoom_in_duration: float = 0.15, zoom_out_duration: float = 0.4):
	if trick_zoom_tween:
		trick_zoom_tween.kill()
	
	is_trick_zooming = true
	var zoom_in_value = base_zoom * (1.0 + zoom_intensity)
	var zoom_out_value = base_zoom
	
	trick_zoom_tween = get_tree().create_tween()
	trick_zoom_tween.set_ease(Tween.EASE_OUT)
	trick_zoom_tween.set_trans(Tween.TRANS_CUBIC)
	
	trick_zoom_tween.tween_method(
		func(zoom): trick_zoom = zoom, 
		trick_zoom, 
		zoom_in_value, 
		zoom_in_duration
	)
	
	trick_zoom_tween.tween_method(
		func(zoom): trick_zoom = zoom, 
		zoom_in_value, 
		zoom_out_value, 
		zoom_out_duration
	).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	trick_zoom_tween.tween_callback(func(): is_trick_zooming = false)

func camera_shake(intensity: float, duration: float = 0.5):
	shake_intensity = intensity
	shake_duration = duration

func setup_particle_effects():
	# Clean, simple dash particles
	if dash_particles:
		dash_particles.color = Color(0.4, 0.8, 1.0, 1.0)  # Nice blue
		dash_particles.amount = 50  # Much more reasonable amount
		dash_particles.lifetime = 0.8  # Shorter lifetime
		dash_particles.scale_amount_min = 0.3
		dash_particles.scale_amount_max = 0.8
		dash_particles.initial_velocity_min = 30.0
		dash_particles.initial_velocity_max = 80.0
		dash_particles.spread = 25.0  # Tighter spread
		dash_particles.direction = Vector2(-1, 0)
		dash_particles.angular_velocity_min = -90.0
		dash_particles.angular_velocity_max = 90.0
		print("Dash particles configured - clean and simple")
	
	# Simple perfect landing particles
	if perfect_particles:
		perfect_particles.color = Color(1.0, 0.9, 0.3, 1.0)  # Golden
		perfect_particles.amount = 300  # Much fewer particles
		perfect_particles.lifetime = 1.5
		perfect_particles.scale_amount_min = 0.4
		perfect_particles.scale_amount_max = 2.0
		perfect_particles.initial_velocity_min = 40.0
		perfect_particles.initial_velocity_max = 100.0
		perfect_particles.spread = 180.0  # Half circle burst
		perfect_particles.direction = Vector2(0, -1)
		perfect_particles.gravity = Vector2(0, 98)
		print("Perfect particles configured - simple and clean")

func setup_blur_system():
	blur_canvas_layer = CanvasLayer.new()
	blur_canvas_layer.layer = 100
	get_tree().current_scene.add_child.call_deferred(blur_canvas_layer)
	
	blur_color_rect = ColorRect.new()
	blur_color_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	blur_color_rect.color = Color.TRANSPARENT
	blur_color_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	blur_canvas_layer.add_child(blur_color_rect)
	blur_color_rect.visible = false

func screen_blur_effect(intensity: float, duration: float, tint_color: Color = Color.TRANSPARENT):
	if not blur_color_rect:
		return
	
	blur_color_rect.visible = true
	var effect_color = tint_color
	effect_color.a = intensity * 0.3  # Subtle effect
	
	blur_color_rect.color = Color.TRANSPARENT
	
	var tween = get_tree().create_tween()
	tween.tween_property(blur_color_rect, "color", effect_color, duration * 0.3)
	tween.tween_property(blur_color_rect, "color", Color.TRANSPARENT, duration * 0.7)
	tween.tween_callback(func(): blur_color_rect.visible = false)

func _on_dash_start():
	print("Dash start - particles will follow player")
	is_dashing = true
	
	if dash_particles:
		dash_particles.emitting = true
	
	camera_shake(2.0)
	smooth_trick_zoom_effect(0.1, 0.1, 0.3)
	screen_blur_effect(0.5, 0.4, Color(0.3, 0.7, 1.0, 0.2))

func _on_dash_end():
	print("Dash end - stopping particles")
	is_dashing = false
	if dash_particles:
		dash_particles.emitting = false

func _on_perfect_landing():
	print("Perfect landing!")
	if player_node and perfect_particles:
		perfect_particles.global_position = player_node.global_position
		perfect_particles.restart()
	camera_shake(2.0)
	smooth_trick_zoom_effect(0.08, 0.08, 0.25)
	screen_blur_effect(0.4, 0.3, Color(1.0, 0.8, 0.2, 0.3))

func _on_good_landing():
	print("Good landing!")
	camera_shake(1.2)
	if perfect_particles and player_node:
		perfect_particles.global_position = player_node.global_position
		var original_amount = perfect_particles.amount
		perfect_particles.amount = 15  # Even fewer for good landing
		perfect_particles.restart()
		get_tree().create_timer(1.0).timeout.connect(func(): 
			if perfect_particles:
				perfect_particles.amount = original_amount
		)
	screen_blur_effect(0.2, 0.2, Color(0.8, 0.8, 0.8, 0.1))

func _on_move_saved():
	print("Move saved!")
	if glow and player_node:
		glow.visible = true
		glow.global_position = player_node.global_position
		glow.modulate = Color(1.0, 1.0, 0.5, 1.0)
		glow.scale = Vector2(1.2, 1.2)
		
		var tween = get_tree().create_tween()
		tween.parallel().tween_property(glow, "modulate:a", 0.0, 0.6)
		tween.parallel().tween_property(glow, "scale", Vector2(0.8, 0.8), 0.6)
		tween.tween_callback(Callable(glow, "hide"))
	
	screen_blur_effect(0.3, 0.4, Color(1.0, 1.0, 0.5, 0.15))

func _on_did_trick(trick_type = ""):
	print("Trick performed: ", trick_type)
	camera_shake(1.5)
	smooth_trick_zoom_effect(0.12, 0.1, 0.3)
	if perfect_particles and player_node:
		perfect_particles.global_position = player_node.global_position
		perfect_particles.restart()
	screen_blur_effect(0.4, 0.4, Color(0.8, 0.4, 1.0, 0.2))

func _on_chain_complete():
	print("Chain complete!")
	camera_shake(2.5)
	smooth_trick_zoom_effect(0.18, 0.12, 0.4)
	
	if perfect_particles and player_node:
		perfect_particles.global_position = player_node.global_position
		var original_amount = perfect_particles.amount
		perfect_particles.amount = 60  # More but not crazy
		perfect_particles.restart()
		get_tree().create_timer(1.0).timeout.connect(func(): 
			if perfect_particles:
				perfect_particles.amount = original_amount
		)
	
	screen_blur_effect(0.6, 0.5, Color(1.0, 0.5, 0.8, 0.3))

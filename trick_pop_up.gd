# Simplified TrickPopup.gd - More reliable for Godot 4.4
extends Control

@onready var trick_label = $VBoxContainer/TrickLabel
@onready var score_label = $VBoxContainer/ScoreLabel

# Popup settings
var popup_duration = 2.0
var fade_time = 0.3
var float_distance = 60

# Colors for different trick types
var trick_colors = {
	"backflip": Color.CYAN,
	"frontflip": Color.MAGENTA,
	"double_jump": Color.YELLOW,
	"air_dash": Color.ORANGE,
	"chain_combo": Color.GOLD
}

func _ready():
	# Start invisible
	modulate.a = 0.0
	visible = false

func show_trick_popup(trick_name: String, points: int):
	"""Display a trick popup with name and score"""
	
	# Set the text
	trick_label.text = format_trick_name(trick_name)
	score_label.text = "+%d" % points
	
	# Set color based on trick type
	var trick_color = trick_colors.get(trick_name, Color.WHITE)
	trick_label.modulate = trick_color
	score_label.modulate = Color.YELLOW
	
	# Position popup near player
	position_popup_near_player()
	
	# Show and animate
	visible = true
	animate_popup_simple()

func format_trick_name(trick_name: String) -> String:
	"""Format trick name for display"""
	match trick_name:
		"backflip":
			return "BACKFLIP"
		"frontflip":
			return "FRONTFLIP"
		"double_jump":
			return "DOUBLE JUMP"
		"air_dash":
			return "AIR DASH"
		"chain_combo":
			return "COMBO!"
		_:
			return trick_name.to_upper()

func position_popup_near_player():
	"""Position popup near player"""
	var player = get_tree().get_first_node_in_group("player")
	if player:
		var viewport_size = get_viewport().get_visible_rect().size
		var player_screen_pos = player.get_global_transform_with_canvas().origin
		
		# Add some randomization to position
		var random_offset_x = randf_range(-50, 50)
		var random_offset_y = randf_range(-120, -80)
		
		# Position popup above player
		position = Vector2(
			player_screen_pos.x - size.x / 2 + random_offset_x,
			player_screen_pos.y + random_offset_y
		)
		
		# Keep popup within screen bounds
		position.x = clamp(position.x, 20, viewport_size.x - size.x - 20)
		position.y = clamp(position.y, 20, viewport_size.y - size.y - 20)

func animate_popup_simple():
	"""Simple but effective popup animation"""
	
	# Store positions
	var start_pos = position
	var end_pos = start_pos + Vector2(0, -float_distance)
	
	# Set initial scale
	scale = Vector2(0.8, 0.8)
	
	# Create sequential tweens (more reliable than parallel)
	var tween = create_tween()
	
	# Fade in and scale up
	tween.parallel().tween_property(self, "modulate:a", 1.0, fade_time)
	tween.parallel().tween_property(self, "scale", Vector2(1.0, 1.0), fade_time)
	tween.parallel().tween_property(self, "position", end_pos, popup_duration)
	
	# Wait for display time
	tween.tween_interval(popup_duration - fade_time * 2)
	
	# Fade out
	tween.parallel().tween_property(self, "modulate:a", 0.0, fade_time)
	tween.parallel().tween_property(self, "scale", Vector2(1.1, 1.1), fade_time)
	
	# Clean up when done
	await tween.finished
	queue_free()

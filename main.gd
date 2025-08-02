extends Node2D
@onready var player = $Player
@onready var anim_player = $Player/AnimationPlayer
@onready var start_ui = $StartOverlay
@onready var kill_screen = $KillScreen
@onready var instructions_label = $InstructionsLabel 
@onready var distanceLabel = $UI/distance
@onready var scoreLabel = $UI/Score
@onready var move_save_ui = $UI/MovedSaveUI  # Reference to your move save UI scene
@onready var trick_system = $Player/TrickSystem
@onready var background_music=$BackgroundMusic  # Reference to the trick system

# Trick popup system
var trick_popup_scene = preload("res://trick_pop_up.tscn")  # Adjust path as needed
var current_score = 0
var game_active = false  # Track if game is currently active

func _ready():
	player.visible = false
	player.set_physics_process(false)  # Disable player control initially
	instructions_label.visible = false  # Hide instructions on title screen
	distanceLabel.visible = false
	scoreLabel.visible = false
	game_active = false
	background_music.play()
	
	# Add player to a group for easy reference
	player.add_to_group("player")
	
	# Connect kill screen buttons
	kill_screen.retry_requested.connect(_on_retry)
	#kill_screen.main_menu_requested.connect(_on_main_menu)  # Add this connection
	
	# Connect to the trick system signals
	if trick_system:
		trick_system.move_saved.connect(_on_move_saved)
		trick_system.trick_completed.connect(_on_trick_completed)
		trick_system.chain_completed.connect(_on_chain_completed)

func start_game():
	player.global_position = Vector2(-100, -200)
	player.visible = true
	game_active = true
	#anim_player.play("intro")
	#await anim_player.animation_finished
	player.set_physics_process(true)
	instructions_label.visible = true
	distanceLabel.visible = true
	scoreLabel.visible = true  # Show instructions when game starts
	
	# Hide kill screen if it's showing
	kill_screen.hide()
	
	# Reset score
	current_score = 0
	update_score_display()

func game_over():
	"""Called when the game ends - stops the game and shows kill screen"""
	game_active = false
	player.set_physics_process(false)  # Stop player movement
	kill_screen.show_kill_screen()

func _on_retry():
	"""Called when retry button is pressed"""
	# Reset player state without automatically starting
	reset_game_state()
	# Start the game again
	start_game()

func _on_main_menu():
	"""Called when main menu button is pressed"""
	# Reset everything and go back to main menu
	reset_game_state()
	player.visible = false
	instructions_label.visible = false
	distanceLabel.visible = false
	scoreLabel.visible = false
	start_ui.show()  # Show the start overlay again
	kill_screen.hide()

func reset_game_state():
	"""Reset all game state without starting the game"""
	# Reset player state
	player.global_position = Vector2(100, 300)
	player.velocity = Vector2.ZERO
	player.rotation_degrees = 0  # Reset player rotation
	player.target_rotation = 0
	player.distance_difficulty_spike = 0
	player.total_score = 0
	player.current_distance_score = 0
	player.distance_travelled = 0.0
	player.start_x = player.global_position.x  # Update start position
	
	player.was_on_floor_last_frame = false
	player.terrain_boost_cooldown_timer = 0.0  # Reset terrain boost cooldown
	
	# Reset jump system
	player.jumps_remaining = 2
	player.can_double_jump = true
	
	# Reset dash system
	player.is_dashing = false
	player.dash_timer = 0.0
	player.dash_cooldown_timer = 0.0
	player.base_velocity_x = 0.0
	
	# Reset trick system
	if trick_system:
		trick_system.reset_trick_system()
	
	# Reset terrain generation
	if player.terrain_generator and player.terrain_generator.has_method("reset_terrain"):
		player.terrain_generator.reset_terrain()
	else:
		print("Warning: TerrainGenerator not found or doesn't have reset_terrain method!")
	
	# Reset score
	current_score = 0
	update_score_display()
	
	game_active = false

func _on_move_saved(move_name: String, slot: int):
	"""Called when a move is saved - triggers the appropriate slot animation"""
	print("Move saved: %s in slot %d" % [move_name, slot])
	
	# Get the animation player from the move save UI
	#var move_ui_anim_player = move_save_ui.get_node("AnimationPlayer")
	#
	#if move_ui_anim_player:
		## Play the animation for the corresponding slot
		#var animation_name = "slot_%d" % slot
		#print("Playing animation: %s" % animation_name)
		#move_ui_anim_player.play(animation_name)
	#else:
		#print("Error: AnimationPlayer not found in MovedSaveUI!")

func _on_trick_completed(trick_name: String, points: int):
	"""Called when a trick is completed - shows popup and updates score"""
	if not game_active:
		return  # Don't process tricks if game isn't active
		
	print("Trick completed: %s for %d points" % [trick_name, points])
	
	# Add points to score
	current_score += points
	update_score_display()
	
	# Show trick popup
	show_trick_popup(trick_name, points)

func _on_chain_completed(chain: Array, bonus_points: int):
	"""Called when a chain combo is completed"""
	if not game_active:
		return  # Don't process chains if game isn't active
		
	print("Chain completed: %s for %d bonus points" % [str(chain), bonus_points])
	
	# Add bonus points to score
	current_score += bonus_points
	update_score_display()
	
	# Show special chain popup
	show_trick_popup("chain_combo", bonus_points)

func show_trick_popup(trick_name: String, points: int):
	"""Create and show a trick popup"""
	
	# Create popup instance (Godot 4)
	var popup = trick_popup_scene.instantiate()
	
	# Add to UI layer (so it appears above everything)
	$UI.add_child(popup)
	
	# Show the popup
	popup.show_trick_popup(trick_name, points)
	
	# Optional: Add sound effect here
	# AudioManager.play_sound("trick_complete")

func update_score_display():
	"""Update the score label"""
	if scoreLabel:
		scoreLabel.text = "Score: %d" % current_score

# Optional: Add method to get current score for other systems
func get_current_score() -> int:
	return current_score

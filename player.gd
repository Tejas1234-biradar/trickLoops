extends CharacterBody2D

# === CONSTANTS ===
const SPEED = 100
const JUMP_VELOCITY = -600
const DOUBLE_JUMP_VELOCITY = -500  # Slightly weaker than regular jump
const GRAVITY = 1200
const TILT_SPEED = 340  # Degrees per second for player rotation
const HARD_SPEED_LIMIT = 400
const DISTANCE_SCORE_MULTIPLIER = 0.01
const BOOST = 1000
const LANDING_ANGLE_TOLERANCE = 100.0  # Stricter tolerance for landing alignment
const DASH_SPEED = 800
const DASH_DURATION = 0.3
const DASH_COOLDOWN = 1.0

# === TERRAIN FOLLOWING CONSTANTS ===
const TERRAIN_BOOST_VELOCITY = -300  # Upward boost when hitting upward slopes
const TERRAIN_BOOST_ANGLE_MIN = 5.0  # Minimum slope angle (degrees) to trigger boost
const TERRAIN_BOOST_ANGLE_MAX = 60.0  # Maximum slope angle (degrees) for boost
const TERRAIN_BOOST_COOLDOWN = 0.5   # Prevent multiple boosts in quick succession

signal Perfect_Landing
signal Good_Landing
signal did_trick
signal dash_start
signal move_saved
signal dash_end
signal chain_complete
signal hit_obstacle

var total_score = 0
var current_distance_score = 0

# === STATE ===
var airborne_time = 0.0
var distance_travelled = 0.0
var start_x = 0.0
var distance_difficulty_spike = 0.0
var is_dashing = false
var dash_timer = 0.0
var dash_cooldown_timer = 0.0
var base_velocity_x = 0.0
var terrain_boost_cooldown_timer = 0.0  # New cooldown for terrain boosts
# === SCARF ===

# === SLEIGH REFERENCE ===
var sleigh: Node2D
var target_rotation = 0.0  # Target rotation for player alignment
var was_on_floor_last_frame = false

# === DOUBLE JUMP SYSTEM ===
var jumps_remaining = 2
var can_double_jump = true
# === SOUND ====
@onready var trick_sound=$TrickCompleteSound
@onready var jump_sound=$JumpSound
@onready var land_sound=$LandSound
@onready var dash_sound=$dashSound
@onready var death_sound=$DeathSound
# === TERRAIN REFERENCE ===
var terrain_generator: Node2D

# === TRICK SYSTEM REFERENCE ===
var trick_system: Node2D

func _ready():
	start_x = global_position.x
	
	# Get sleigh reference (for visual indicator)
	sleigh = get_node_or_null("CollisionShape2D/Sleigh")
	if not sleigh:
		print("Warning: Sleigh node not found! Make sure it's named 'Sleigh'")
		return
	
	# Get trick system reference
	trick_system = get_node_or_null("TrickSystem")
	if not trick_system:
		print("Warning: TrickSystem node not found!")
	else:
		# Connect trick system signals
		trick_system.trick_completed.connect(_on_trick_completed)
		trick_system.chain_completed.connect(_on_chain_completed)
		trick_system.move_saved.connect(_on_move_saved)
	
	# Find the terrain generator (adjust path as needed)
	terrain_generator = get_node_or_null("../PlatformSpawner")
	if not terrain_generator:
		# Try alternative paths
		terrain_generator = get_node_or_null("/root/Main/PlatfromSpawner")
	
	if not terrain_generator:
		print("Warning: Could not find TerrainGenerator node!")
	$Scarf/scarfAnimator.play("scarf")

func _physics_process(delta):
	if not sleigh:
		return
	
	# DASH TIMER LOGIC - Fixed
	if dash_timer > 0:
		dash_timer -= delta
		if dash_timer <= 0:  # Only call end_dash when timer reaches 0
			end_dash()
	
	if dash_cooldown_timer > 0:
		dash_cooldown_timer -= delta
	
	# TERRAIN BOOST COOLDOWN
	if terrain_boost_cooldown_timer > 0:
		terrain_boost_cooldown_timer -= delta
		
	# --- GRAVITY APPLICATION ---
	if not is_on_floor():
		velocity.y += GRAVITY * delta
		airborne_time += delta
	else:
		# Landing logic
		if not was_on_floor_last_frame:
			# Just landed - check sleigh alignment (CRITICAL!)
			if not check_landing_alignment():
				game_fail()
				return
			# Notify trick system
			if trick_system:
				trick_system.on_landed()
		
		airborne_time = 0.0
		jumps_remaining = 2  # Reset jumps when landing
		can_double_jump = true
		
		# Align player with ground when on floor
		align_player_with_ground()
	
	was_on_floor_last_frame = is_on_floor()
	
	# --- JUMP INPUT ---
	var jump_input = false
	if trick_system:
		jump_input = trick_system.is_action_just_pressed_custom("jump")
	else:
		jump_input = Input.is_action_just_pressed("jump")
	
	if jump_input:
		# Check if we should consume charges (false during replay for free jumps)
		var should_consume = not trick_system or trick_system.should_consume_charges()
		
		if is_on_floor():
			if not should_consume or jumps_remaining > 0:
				velocity.y = JUMP_VELOCITY
				jump_sound.play()
				if should_consume:
					jumps_remaining -= 1
				# Notify trick system
				if trick_system:
					trick_system.on_jump_started()
		elif not is_on_floor():
			if not should_consume or (can_double_jump and jumps_remaining > 0):
				velocity.y = DOUBLE_JUMP_VELOCITY
				jump_sound.play()
				if should_consume:
					jumps_remaining -= 1
					can_double_jump = false
				# Notify trick system (always notify, even during replay)
				if trick_system:
					trick_system.on_double_jump_performed()
	
	# --- AIRBORNE PLAYER TILT CONTROL AND AIR DASH ---
	if not is_on_floor():
		var tilt_left_input = false
		var tilt_right_input = false
		var air_dash_input = false
		
		if trick_system:
			tilt_left_input = trick_system.is_action_pressed_custom("tilt_left")
			tilt_right_input = trick_system.is_action_pressed_custom("tilt_right")
			air_dash_input = trick_system.is_action_just_pressed_custom("air_dash")
		else:
			tilt_left_input = Input.is_action_pressed("tilt_left")
			tilt_right_input = Input.is_action_pressed("tilt_right")
			air_dash_input = Input.is_action_just_pressed("air_dash")
		
		# Only allow tilt control when not dashing
		if not is_dashing:
			if tilt_left_input:
				rotation_degrees -= TILT_SPEED * delta
			elif tilt_right_input:
				rotation_degrees += TILT_SPEED * delta
		
		# Air dash logic with free charges during replay
		if air_dash_input and not is_dashing:
			# Check if we should consume charges (false during replay for free dashes)
			var should_consume = not trick_system or trick_system.should_consume_charges()
			
			if not should_consume or dash_cooldown_timer <= 0:
				start_dash()
				# Only set cooldown if we're consuming charges (not during replay)
				if should_consume:
					dash_cooldown_timer = DASH_COOLDOWN
				# Notify trick system about air dash
				if trick_system:
					trick_system.on_air_dash_performed()
	
	# --- MOVE CONSTANTLY RIGHT ---
	if not is_dashing:
		velocity.x = SPEED + distance_difficulty_spike
	# If dashing, velocity.x is already set by start_dash()
	
	# --- MOVE AND HANDLE TERRAIN FOLLOWING ---
	move_and_slide()
	
	# --- ENHANCED COLLISION HANDLING FOR TERRAIN FOLLOWING ---
	handle_terrain_collisions()
	
	# --- DISTANCE TRACKING ---
	distance_travelled = int(global_position.x - start_x)
	var meters = int(distance_travelled / 10)
	
	# Update the label (assuming you have a UI label for distance)
	var distance_label = get_node_or_null("/root/Main/UI/distance")
	if distance_label:
		distance_label.text = "Distance: %dm" % meters
	
	var new_distance_score = meters * DISTANCE_SCORE_MULTIPLIER
	if new_distance_score > current_distance_score:
		var diff = new_distance_score - current_distance_score
		total_score += diff
		current_distance_score = new_distance_score
	
	# Update Score Label
	var score_label = get_node_or_null("/root/Main/UI/Score")
	if score_label:
		score_label.text = "Score: %d" % total_score
	
	# Difficulty increase trigger - don't interfere with dash
	if meters > 5 and velocity.x < HARD_SPEED_LIMIT and not is_dashing:
		distance_difficulty_spike += 1

func handle_terrain_collisions():
	"""Enhanced collision handling specifically for terrain following"""
	for i in range(get_slide_collision_count()):
		var collision = get_slide_collision(i)
		var collider = collision.get_collider()
		var collision_normal = collision.get_normal()
		
		# Handle obstacles
		if collider.is_in_group("obstacle"):
			print("Hit obstacle! Resetting position...")
			emit_signal("hit_obstacle")
			game_fail()
			return
		
		# Handle terrain/platform collisions
		if collider.is_in_group("terrain") or collider.is_in_group("platform"):
			
			# Calculate the angle of the surface we hit
			var surface_angle_rad = atan2(-collision_normal.x, collision_normal.y)
			var surface_angle_deg = rad_to_deg(surface_angle_rad)
			
			# Normalize angle to 0-360 range
			if surface_angle_deg < 0:
				surface_angle_deg += 360
			
			# Check if this is an upward slope that should give us a boost
			var is_upward_slope = surface_angle_deg > TERRAIN_BOOST_ANGLE_MIN and surface_angle_deg < TERRAIN_BOOST_ANGLE_MAX
			
			# Additional checks for terrain boost
			var moving_into_slope = velocity.x > 0 and collision_normal.x < 0  # Moving right into leftward-facing normal
			var can_boost = terrain_boost_cooldown_timer <= 0
			var not_falling_too_fast = velocity.y > -200  # Don't boost if falling very fast
			
			if is_upward_slope and moving_into_slope and can_boost and not_falling_too_fast:
				print("Terrain boost triggered! Surface angle: %.1f degrees" % surface_angle_deg)
				
				# Apply upward boost - stronger for steeper slopes
				var boost_strength = lerp(0.5, 1.0, (surface_angle_deg - TERRAIN_BOOST_ANGLE_MIN) / (TERRAIN_BOOST_ANGLE_MAX - TERRAIN_BOOST_ANGLE_MIN))
				velocity.y = TERRAIN_BOOST_VELOCITY * boost_strength
				
				# Set cooldown to prevent multiple boosts
				terrain_boost_cooldown_timer = TERRAIN_BOOST_COOLDOWN
				
				# Optional: Add some forward momentum too
				if not is_dashing:
					velocity.x += 50 * boost_strength
				
				print("Applied terrain boost: y_velocity = %.1f" % velocity.y)
			
			# Handle other collision responses
			if collision_normal.y < -0.5:  # Hit from below (ceiling)
				if velocity.y < 0:
					velocity.y = 0
			elif abs(collision_normal.x) > 0.5 and not is_dashing:  # Hit from side
				velocity.x = min(velocity.x, 0)

func align_player_with_ground():
	"""Align player with ground slope when on floor"""
	if not is_on_floor():
		return
	
	# Get the floor normal from collision
	var floor_normal = get_floor_normal()
	
	# Calculate the angle of the slope
	# Floor normal points up from the surface, so we need to get the surface angle
	var slope_angle = atan2(floor_normal.x, floor_normal.y) * 180.0 / PI
	
	# Set player target rotation
	target_rotation = slope_angle
	
	# Smoothly rotate player to match ground angle
	var angle_diff = target_rotation - rotation_degrees
	
	# Normalize angle difference
	while angle_diff > 180:
		angle_diff -= 360
	while angle_diff < -180:
		angle_diff += 360
	
	# Smooth rotation towards target
	var rotation_speed = 720.0  # Fast alignment when on ground
	if abs(angle_diff) > 1.0:  # Only rotate if difference is significant
		var rotation_step = rotation_speed * get_physics_process_delta_time()
		if abs(angle_diff) < rotation_step:
			rotation_degrees = target_rotation
		else:
			#rotation_degrees += sign(angle_diff) * rotation_step
			pass

func check_landing_alignment() -> bool:
	"""Check if player is properly aligned when landing - returns false if bad landing"""
	if not is_on_floor():
		return true
	
	# Get the floor normal
	var floor_normal = get_floor_normal()
	var slope_angle = atan2(floor_normal.x, floor_normal.y) * 180.0 / PI
	
	# Calculate angle difference between player and slope
	var player_angle = rotation_degrees
	var angle_diff = abs(player_angle - slope_angle)
	
	# Normalize angle difference to 0-180 range
	while angle_diff > 180:
		angle_diff = 360 - angle_diff
	
	# Check if landing is within tolerance
	if angle_diff < LANDING_ANGLE_TOLERANCE:
		return false
	else:
		print("Good landing! Within tolerance.")
		#land_sound.play()
		# Add bonus points for perfect landings
		if angle_diff < 10.0:  # Perfect landing bonus
			total_score += 10
			print("Perfect landing bonus: +10 points!")
			emit_signal("Perfect_Landing")
		elif angle_diff < 15.0:  # Good landing bonus
			total_score += 5
			print("Good landing bonus: +5 points!")
			emit_signal("Good_Landing")
		return true

func game_fail():
	print("GAME OVER - Player died...")
	death_sound.play()
	# Just call the main scene's game_over method
	# This will stop the game and show the kill screen
	get_parent().game_over()
# === TRICK SYSTEM SIGNAL HANDLERS ===
func _on_trick_completed(trick_name: String, points: int):
	"""Handle trick completion from trick system"""
	total_score += points
	emit_signal("did_trick")
	trick_sound.play()
	print("Trick completed: %s (+%d points)" % [trick_name, points])

func _on_chain_completed(chain: Array, bonus_points: int):
	"""Handle chain completion from trick system"""
	total_score += bonus_points
	emit_signal("chain_complete")
	print("Chain completed: %s (+%d points)" % [chain, bonus_points])

func _on_move_saved(move_name: String, slot: int):
	"""Handle move saved"""
	emit_signal("move_saved")
	print("Move saved to slot %d: %s" % [slot, move_name])

# === DASH FUNCTIONS ===
func start_dash():
	print("Starting dash!")
	dash_sound.play()
	is_dashing = true
	dash_timer = DASH_DURATION
	
	# Store the current base velocity
	base_velocity_x = SPEED + distance_difficulty_spike
	
	# Set dash velocity
	velocity.x = DASH_SPEED
	emit_signal("dash_start")
	print("Dash velocity set to: %d" % velocity.x)

func end_dash():
	print("Ending dash!")
	is_dashing = false
	
	# Return to normal speed but keep some momentum
	velocity.x = max(base_velocity_x, velocity.x * 0.3)  # Keep 30% of dash speed
	emit_signal("dash_end")
	print("Post-dash velocity: %d" % velocity.x)

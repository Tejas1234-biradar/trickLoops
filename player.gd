extends CharacterBody2D
# === CONSTANTS ===
const SPEED = 100
const JUMP_VELOCITY = -800
const DOUBLE_JUMP_VELOCITY = -600  # Slightly weaker than regular jump
const GRAVITY = 1200
const TILT_SPEED = 340  # Degrees per second for player rotation
const HARD_SPEED_LIMIT = 400
const DISTANCE_SCORE_MULTIPLIER = 0.01
const LANDING_ANGLE_TOLERANCE = 100.0  # Stricter tolerance for landing alignment

var total_score = 0
var current_distance_score = 0

# === STATE ===
var airborne_time = 0.0
var distance_travelled = 0.0
var start_x = 0.0
var distance_difficulty_spike = 0.0

# === SLEIGH REFERENCE ===
var sleigh: Node2D
var target_rotation = 0.0  # Target rotation for player alignment
var was_on_floor_last_frame = false

# === DOUBLE JUMP SYSTEM ===
var jumps_remaining = 2
var can_double_jump = true

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

func _physics_process(delta):
	if not sleigh:
		return
	
	# --- GRAVITY APPLICATION ---
	if not is_on_floor():
		velocity.y += GRAVITY * delta
		airborne_time += delta
	else:
		# Landing logic
		if not was_on_floor_last_frame:
			# Just landed - check sleigh alignment (CRITICAL!)
			if not check_landing_alignment():
				#game_fail()
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
		if is_on_floor() and jumps_remaining > 0:
			velocity.y = JUMP_VELOCITY
			jumps_remaining -= 1
			# Notify trick system
			if trick_system:
				trick_system.on_jump_started()
		elif not is_on_floor() and can_double_jump and jumps_remaining > 0:
			velocity.y = DOUBLE_JUMP_VELOCITY
			jumps_remaining -= 1
			can_double_jump = false
			# Notify trick system
			if trick_system:
				trick_system.on_double_jump_performed()
	
	# --- AIRBORNE PLAYER TILT CONTROL ---
	if not is_on_floor():
		var tilt_left_input = false
		var tilt_right_input = false
		
		if trick_system:
			tilt_left_input = trick_system.is_action_pressed_custom("tilt_left")
			tilt_right_input = trick_system.is_action_pressed_custom("tilt_right")
		else:
			tilt_left_input = Input.is_action_pressed("tilt_left")
			tilt_right_input = Input.is_action_pressed("tilt_right")
		
		if tilt_left_input:
			rotation_degrees -= TILT_SPEED * delta
		elif tilt_right_input:
			rotation_degrees += TILT_SPEED * delta
	
	# --- MOVE CONSTANTLY RIGHT ---
	velocity.x = SPEED + distance_difficulty_spike
	
	# --- MOVE ---
	move_and_slide()
	
	# --- COLLISION HANDLING ---
	# Check for collisions after movement
	for i in range(get_slide_collision_count()):
		var collision = get_slide_collision(i)
		var collider = collision.get_collider()
		
		if collider.is_in_group("obstacle"):
			print("Hit obstacle! Resetting position...")
			game_fail()
			return
		
		# Additional collision checks for terrain/platforms
		if collider.is_in_group("terrain") or collider.is_in_group("platform"):
			# Ensure proper collision response
			var collision_normal = collision.get_normal()
			
			# If hitting from below or side, handle appropriately
			if collision_normal.y < -0.5:  # Hit from below
				# Stop upward movement when hitting ceiling
				if velocity.y < 0:
					velocity.y = 0
			elif abs(collision_normal.x) > 0.5:  # Hit from side
				# Stop horizontal movement when hitting walls
				velocity.x = min(velocity.x, 0)
	
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
	
	# Difficulty increase trigger
	if meters > 5 and velocity.x < HARD_SPEED_LIMIT:
		distance_difficulty_spike += 1

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
		print("CRASH! Bad landing! Angle difference: %.1f degrees (tolerance: %.1f)" % [angle_diff, LANDING_ANGLE_TOLERANCE])
		return false
	else:
		print("Good landing! Within tolerance.")
		# Add bonus points for perfect landings
		if angle_diff < 10.0:  # Perfect landing bonus
			total_score += 10
			print("Perfect landing bonus: +10 points!")
		elif angle_diff < 15.0:  # Good landing bonus
			total_score += 5
			print("Good landing bonus: +5 points!")
		return true

func game_fail():
	print("GAME OVER - Resetting...")
	
	# Reset player state
	global_position = Vector2(100, 300)
	velocity = Vector2.ZERO
	rotation_degrees = 0  # Reset player rotation
	target_rotation = 0
	distance_difficulty_spike = 0
	total_score = 0
	current_distance_score = 0
	distance_travelled = 0.0
	start_x = global_position.x  # Update start position
	
	was_on_floor_last_frame = false
	
	# Reset jump system
	jumps_remaining = 2
	can_double_jump = true
	
	# Reset trick system
	if trick_system:
		trick_system.reset_trick_system()
	
	# Reset terrain generation
	if terrain_generator and terrain_generator.has_method("reset_terrain"):
		terrain_generator.reset_terrain()
	else:
		print("Warning: TerrainGenerator not found or doesn't have reset_terrain method!")

# === TRICK SYSTEM SIGNAL HANDLERS ===
func _on_trick_completed(trick_name: String, points: int):
	"""Handle trick completion from trick system"""
	total_score += points
	print("Trick completed: %s (+%d points)" % [trick_name, points])

func _on_chain_completed(chain: Array, bonus_points: int):
	"""Handle chain completion from trick system"""
	total_score += bonus_points
	print("Chain completed: %s (+%d points)" % [chain, bonus_points])

func _on_move_saved(move_name: String, slot: int):
	"""Handle move being saved"""
	print("Move saved to slot %d: %s" % [slot, move_name])

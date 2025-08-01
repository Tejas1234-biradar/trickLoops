extends Node2D

class_name TrickSystem

# === TRICK CONSTANTS ===
const TRICK_POINTS = {
	"backflip": 100,
	"frontflip": 100,
	"double_jump": 50,
	"air_dash":75,
}

# === PLAYER REFERENCE ===
var player: CharacterBody2D
var sleigh: Node2D

# === FLIP TRACKING ===
var flip_completed = false  # Prevents multiple flip detections
var player_rotation_at_jump = 0.0  # Track PLAYER rotation when jump started

# === INPUT RECORDING SYSTEM ===
var is_recording = false
var recorded_inputs = []
var recording_start_time = 0.0

# Current input recording structure:
# {
#   "timestamp": float, # millisecond precision from start of recording
#   "action": string, # "jump", "tilt_left_start", "tilt_left_end", "tilt_right_start", "tilt_right_end"
#   "position": Vector2, # player position when input happened
#   "rotation": float # player rotation when input happened
# }

# === INPUT PLAYBACK SYSTEM ===
var is_replaying = false
var replay_inputs = []
var replay_start_time = 0.0
var replay_index = 0

# === INPUT SIMULATION ===
var simulated_actions = {}  # Track which actions are currently "pressed" during replay

# === INPUT STATE TRACKING (for physics process) ===
var jump_pressed_this_frame = false
var tilt_left_pressed_this_frame = false
var tilt_right_pressed_this_frame = false
var tilt_left_released_this_frame = false
var tilt_right_released_this_frame = false
var air_dash_released_this_frame=false

# === MOVE SYSTEM ===
var unlocked_move_1 = null
var saved_moves = []

# === CHAINING SYSTEM ===
var is_recording_chain = false
var current_chain = []
var chain_start_time = 0.0
var chain_timeout = 5.0  # 5 seconds to complete a chain

# === SIGNALS ===
signal trick_completed(trick_name: String, points: int)
signal chain_completed(chain: Array, bonus_points: int)
signal move_saved(move_name: String, slot: int)

func _ready():
	# Get player reference (parent should be the CharacterBody2D)
	player = get_parent() as CharacterBody2D
	if not player:
		print("Error: TrickSystem must be child of CharacterBody2D!")
		return
	
	# Get sleigh reference
	sleigh = player.get_node_or_null("CollisionShape2D/Sleigh")
	if not sleigh:
		print("Warning: Sleigh node not found! Make sure it's named 'Sleigh'")
	
	# Initialize simulated actions
	simulated_actions = {
		"jump": false,
		"tilt_left": false,
		"tilt_right": false
	}

func _physics_process(delta):
	if not player:
		return
	
	# --- RECORD INPUTS IN PHYSICS PROCESS (more reliable) ---
	if is_recording and not is_replaying:
		record_physics_inputs()
	
	# --- INPUT PLAYBACK SYSTEM ---
	if is_replaying:
		handle_input_playback(delta)
	
	# --- IMPROVED FLIP DETECTION USING PLAYER ROTATION ---
	if not player.is_on_floor() and not flip_completed:
		# Check if player has completed a full rotation (360 degrees from jump start)
		var player_rotation_diff = player.rotation_degrees - player_rotation_at_jump
		
		# Normalize rotation difference to handle wrap-around
		while player_rotation_diff > 180:
			player_rotation_diff -= 360
		while player_rotation_diff < -180:
			player_rotation_diff += 360
		
		# Detect completed flips (need at least 300 degrees of rotation)
		if abs(player_rotation_diff) >= 300:
			var move_name = ""
			if player_rotation_diff > 0:
				print("You completed a backflip!")
				move_name = "backflip"
			else:
				print("You completed a frontflip!")
				move_name = "frontflip"
			
			# Stop recording if we were recording this trick
			if is_recording:
				stop_recording()
			
			complete_trick(move_name)
			print("Flip completed at player rotation: ", player.rotation_degrees)
	
	# --- CHAIN TIMEOUT CHECK ---
	if is_recording_chain and get_current_time_ms() - chain_start_time > chain_timeout * 1000:
		print("Chain recording timed out!")
		stop_chain_recording()
	
	# Reset frame input flags
	jump_pressed_this_frame = false
	tilt_left_pressed_this_frame = false
	tilt_right_pressed_this_frame = false
	tilt_left_released_this_frame = false
	tilt_right_released_this_frame = false

func _input(event):
	if not player:
		return
	
	# Track input states for physics process (only if not replaying)
	if not is_replaying:
		if Input.is_action_just_pressed("jump"):
			jump_pressed_this_frame = true
		if Input.is_action_just_pressed("tilt_left"):
			tilt_left_pressed_this_frame = true
		if Input.is_action_just_released("tilt_left"):
			tilt_left_released_this_frame = true
		if Input.is_action_just_pressed("tilt_right"):
			tilt_right_pressed_this_frame = true
		if Input.is_action_just_released("tilt_right"):
			tilt_right_released_this_frame = true
	
	# Don't process manual inputs during replay
	if is_replaying:
		return
	
	# --- SAVE MOVE INPUT ---
	if Input.is_action_just_pressed("save_loop") and unlocked_move_1 != null:
		# Save the recorded input sequence along with the move name
		var move_data = {
			"name": unlocked_move_1,
			"inputs": recorded_inputs.duplicate(),
			"score": TRICK_POINTS.get(unlocked_move_1, 0)
		}
		saved_moves.append(move_data)
		print("Saved move %d: %s with %d inputs (Score: %d)" % [saved_moves.size(), unlocked_move_1, recorded_inputs.size(), move_data.score])
		move_saved.emit(unlocked_move_1, saved_moves.size())
		unlocked_move_1 = null
		recorded_inputs.clear()
	
	# --- CHAINING INPUT ---
	if Input.is_action_just_pressed("chaining"):
		if not is_recording_chain:
			start_chain_recording()
		else:
			finish_chain_recording()
	
	# --- PLAY SAVED MOVES ---
	for i in range(1, 5):
		if Input.is_action_just_pressed("play_loop_%d" % i):
			if i <= saved_moves.size() and player.is_on_floor():
				var move_data = saved_moves[i - 1]
				replay_move(move_data, i)

# === CUSTOM INPUT SYSTEM FOR REPLAY ===
func is_action_just_pressed_custom(action: String) -> bool:
	"""Custom input check that considers both real input and simulated input during replay"""
	if is_replaying:
		# During replay, only check simulated actions
		return simulated_actions.get(action + "_just_pressed", false)
	else:
		# During normal play, use regular input
		return Input.is_action_just_pressed(action)

func is_action_pressed_custom(action: String) -> bool:
	"""Custom input check that considers both real input and simulated input during replay"""
	if is_replaying:
		# During replay, only check simulated actions
		return simulated_actions.get(action, false)
	else:
		# During normal play, use regular input
		return Input.is_action_pressed(action)

func get_current_time_ms() -> float:
	"""Get current time in milliseconds with high precision"""
	return Time.get_ticks_msec()

func record_physics_inputs():
	"""Record input events with millisecond precision in physics process"""
	var current_time = get_current_time_ms() - recording_start_time
	
	# Record jump (more reliable in physics process)
	if jump_pressed_this_frame:
		recorded_inputs.append({
			"timestamp": current_time,
			"action": "jump",
			"position": player.global_position,
			"rotation": player.rotation_degrees
		})
		print("Recorded: jump at %.1fms" % current_time)
	
	# Record tilt controls
	if tilt_left_pressed_this_frame:
		recorded_inputs.append({
			"timestamp": current_time,
			"action": "tilt_left_start",
			"position": player.global_position,
			"rotation": player.rotation_degrees
		})
		print("Recorded: tilt_left_start at %.1fms" % current_time)
	
	if tilt_left_released_this_frame:
		recorded_inputs.append({
			"timestamp": current_time,
			"action": "tilt_left_end",
			"position": player.global_position,
			"rotation": player.rotation_degrees
		})
		print("Recorded: tilt_left_end at %.1fms" % current_time)
	
	if tilt_right_pressed_this_frame:
		recorded_inputs.append({
			"timestamp": current_time,
			"action": "tilt_right_start",
			"position": player.global_position,
			"rotation": player.rotation_degrees
		})
		print("Recorded: tilt_right_start at %.1fms" % current_time)
	
	if tilt_right_released_this_frame:
		recorded_inputs.append({
			"timestamp": current_time,
			"action": "tilt_right_end",
			"position": player.global_position,
			"rotation": player.rotation_degrees
		})
		print("Recorded: tilt_right_end at %.1fms" % current_time)

func handle_input_playback(delta: float):
	"""Handle playback of recorded inputs by simulating input actions"""
	var current_playback_time = get_current_time_ms() - replay_start_time
	
	# Reset just_pressed flags each frame
	simulated_actions["jump_just_pressed"] = false
	
	# Check if we should execute the next input
	while replay_index < replay_inputs.size():
		var input_data = replay_inputs[replay_index]
		
		if current_playback_time >= input_data.timestamp:
			# Execute this input by setting simulated action states
			simulate_input_action(input_data)
			replay_index += 1
		else:
			break
	
	# Check if playback is finished
	if replay_index >= replay_inputs.size() and replay_inputs.size() > 0:
		var last_timestamp = replay_inputs[-1].timestamp
		if current_playback_time > last_timestamp + 500:  # 500ms buffer
			stop_replay()

func simulate_input_action(input_data):
	"""Simulate an input action by setting the appropriate flags"""
	print("Simulating: %s at %.1fms" % [input_data.action, input_data.timestamp])
	
	match input_data.action:
		"jump":
			# Set just_pressed flag for one frame
			simulated_actions["jump_just_pressed"] = true
			print("Simulated jump input")
		
		"tilt_left_start":
			simulated_actions["tilt_left"] = true
			print("Simulated tilt_left start")
		
		"tilt_left_end":
			simulated_actions["tilt_left"] = false
			print("Simulated tilt_left end")
		
		"tilt_right_start":
			simulated_actions["tilt_right"] = true
			print("Simulated tilt_right start")
		
		"tilt_right_end":
			simulated_actions["tilt_right"] = false
			print("Simulated tilt_right end")

func start_recording():
	"""Start recording inputs"""
	is_recording = true
	recorded_inputs.clear()
	recording_start_time = get_current_time_ms()
	print("Started recording inputs...")

func stop_recording():
	"""Stop recording inputs"""
	is_recording = false
	print("Stopped recording. Captured %d inputs" % recorded_inputs.size())

func replay_move(move_data, slot_number: int):
	"""Replay a saved move with exact input timing"""
	if not player or is_replaying:
		return
	
	print("Replaying move %d: %s (Score: %d)" % [slot_number, move_data.name, move_data.get("score", 0)])
	
	# Set up replay
	replay_inputs = move_data.inputs.duplicate()
	replay_start_time = get_current_time_ms()
	replay_index = 0
	is_replaying = true
	
	# Reset all simulated actions
	simulated_actions = {
		"jump": false,
		"jump_just_pressed": false,
		"tilt_left": false,
		"tilt_right": false
	}

func stop_replay():
	"""Stop input playback"""
	is_replaying = false
	replay_inputs.clear()
	replay_index = 0
	
	# Reset all simulated actions
	simulated_actions = {
		"jump": false,
		"jump_just_pressed": false,
		"tilt_left": false,
		"tilt_right": false
	}
	print("Replay finished!")

func on_jump_started():
	"""Called by player when jump starts"""
	if player:
		player_rotation_at_jump = player.rotation_degrees
		print("Jump started - Recording player rotation: %.1f" % player_rotation_at_jump)
		
		# Start recording when jump begins (but not during replay)
		if not is_recording and not is_replaying:
			start_recording()

func on_double_jump_performed():
	"""Called by player when double jump is performed"""
	if not is_replaying:  # Only detect manual double jumps
		complete_trick("double_jump")
		print("Double jump performed!")

func on_landed():
	"""Called by player when landing"""
	flip_completed = false  # Reset flip detection when landing
	
	# Stop recording on landing if we were recording
	if is_recording:
		stop_recording()

func complete_trick(trick_name: String):
	"""Complete a trick and handle scoring"""
	unlocked_move_1 = trick_name
	flip_completed = true  # Prevent multiple detections
	
	# Add to chain if recording
	if is_recording_chain:
		current_chain.append(trick_name)
		print("Added to chain: ", trick_name, " | Current chain: ", current_chain)
	
	# Emit signal with trick points
	if TRICK_POINTS.has(trick_name):
		trick_completed.emit(trick_name, TRICK_POINTS[trick_name])

func start_chain_recording():
	"""Start recording a trick chain"""
	is_recording_chain = true
	current_chain.clear()
	chain_start_time = get_current_time_ms()
	print("Started recording chain! Perform: frontflip -> backflip -> double_jump")

func finish_chain_recording():
	"""Finish recording the current chain"""
	print("Finished recording chain: ", current_chain)
	
	# Check if the chain matches the target sequence
	var target_sequence = ["frontflip", "backflip", "double_jump"]
	if arrays_equal(current_chain, target_sequence):
		var chain_data = {
			"name": "chain_combo",
			"inputs": recorded_inputs.duplicate(),
			"score": 500
		}
		saved_moves.append(chain_data)
		print("Perfect chain completed! Saved as combo move at slot %d (Score: 500)" % saved_moves.size())
		chain_completed.emit(current_chain.duplicate(), 500)
		move_saved.emit("chain_combo", saved_moves.size())
	else:
		print("Chain doesn't match target sequence. Required: ", target_sequence)
	
	stop_chain_recording()

func stop_chain_recording():
	"""Stop chain recording"""
	is_recording_chain = false
	current_chain.clear()

func arrays_equal(arr1: Array, arr2: Array) -> bool:
	"""Check if two arrays are equal"""
	if arr1.size() != arr2.size():
		return false
	for i in range(arr1.size()):
		if arr1[i] != arr2[i]:
			return false
	return true

func reset_trick_system():
	"""Reset all trick system state"""
	saved_moves.clear()
	unlocked_move_1 = null
	flip_completed = false
	player_rotation_at_jump = 0.0
	
	# Reset recording system
	is_recording = false
	recorded_inputs.clear()
	recording_start_time = 0.0
	
	# Reset playback system
	stop_replay()
	
	# Stop chain recording if active
	if is_recording_chain:
		stop_chain_recording()
	
	print("Trick system reset!")  

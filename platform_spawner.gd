extends Node2D

# Only valley scene needed now
@export var valley_scene: PackedScene
@export var player: Node2D
@export var segment_length := 600
@export var preload_segments := 5

var spawned_segments = []
var last_spawn_x = 0
var last_end_position := Vector2.ZERO

@export var starting_valley: Node2D
@export var segment_overlap := 50

# New properties for downhill progression and variety
@export var downhill_rate := 30  # How much to descend per segment
@export var max_downhill_variation := 20  # Random variation in descent
@export var current_elevation := 0  # Track overall descent
@export var difficulty_progression := 0.1  # How much harder each segment gets

# Valley type distribution weights
var valley_type_weights = {
	0: 25,  # SMOOTH - common at start
	1: 15,  # JAGGED
	2: 10,  # STEEP_DROP
	3: 20,  # GENTLE_SLOPE
	4: 10,  # DOUBLE_DIP
	5: 3,   # CLIFF_FACE - rare but exciting
	6: 15   # BUMPY
}

# Reference to the obstacle spawner
var obstacle_spawner: ObstacleSpawner

# Mountain layer colors for depth effect (only used for background layers)


func _ready():
	# Find or create obstacle spawner
	obstacle_spawner = get_node_or_null("ObstacleSpawner")
	if not obstacle_spawner:
		print("Warning: No ObstacleSpawner child node found!")
	else:
		obstacle_spawner.initialize(player)
	
	# Initialize from the manually placed starting valley
	initialize_starting_position()

func initialize_starting_position():
	if starting_valley:
		# Look for an end marker on the starting valley
		var end_marker = starting_valley.get_node_or_null("EndMarker")
		if end_marker:
			last_end_position = end_marker.global_position
			last_spawn_x = end_marker.global_position.x
			current_elevation = end_marker.global_position.y
		else:
			# Fallback: try to get end position from Path2D
			var path2d = starting_valley.get_node_or_null("Path2D")
			if path2d:
				var curve = path2d.curve
				var curve_end = curve.sample_baked(curve.get_baked_length())
				last_end_position = starting_valley.global_position + path2d.position + curve_end
				last_spawn_x = last_end_position.x
				current_elevation = last_end_position.y
			else:
				print("Warning: No EndMarker or Path2D found on starting valley!")
				last_end_position = starting_valley.global_position + Vector2(segment_length, 0)
				last_spawn_x = last_end_position.x
				current_elevation = starting_valley.global_position.y
	else:
		print("Warning: No starting_valley assigned!")
		last_end_position = Vector2.ZERO
		last_spawn_x = 0
		current_elevation = 0

func _process(delta):
	# Only start spawning when player gets close to the end of the starting platform
	if player.global_position.x + (segment_length) > last_spawn_x:
		spawn_segment()
		cleanup_old_segments()
	
	# Clean up old obstacles
	if obstacle_spawner:
		obstacle_spawner.cleanup_old_obstacles(player.global_position)

func spawn_segment():
	var seg = valley_scene.instantiate()
	
	# Configure the valley BEFORE adding it to the scene tree
	# This ensures configuration happens before _ready() is called
	configure_valley_segment(seg)
	
	# Apply the mountain styling (using Godot's gradient texture)
	apply_mountain_styling(seg)
	
	# Now add it to the scene tree, which will trigger _ready() with our configuration
	add_child(seg)
	
	# Get positions from the Path2D curve after configuration
	var path2d = seg.get_node("Path2D")
	var curve = path2d.curve
	
	# Calculate start and end positions from the curve
	var curve_start = curve.sample_baked(0.0) if curve else Vector2.ZERO
	var curve_end = curve.sample_baked(curve.get_baked_length()) if curve else Vector2(segment_length, 0)
	
	# Position the segment so it starts at last_end_position
	seg.global_position = last_end_position - Vector2(segment_overlap, 0)
	
	# Update last_end_position and last_spawn_x for next spawn
	last_end_position = seg.global_position + path2d.position + curve_end - Vector2(segment_overlap, 0)
	last_spawn_x = last_end_position.x
	
	spawned_segments.append(seg)
	
	# Enhanced smooth transition between segments
	smooth_segment_transition(seg)
	
	# Spawn obstacles using the dedicated spawner
	if obstacle_spawner:
		obstacle_spawner.spawn_obstacles_on_segment(seg)
	
	# Update difficulty for next segment
	update_difficulty_progression()

func configure_valley_segment(segment):
	var path2d = segment.get_node("Path2D")
	if not path2d:
		print("Warning: Valley segment has no Path2D child!")
		return
	
	# Calculate descent for this segment
	var base_descent = downhill_rate
	var variation = randf_range(-max_downhill_variation, max_downhill_variation)
	var total_descent = base_descent + variation
	
	# Set start height to current elevation
	path2d.start_height = 0  # Relative to segment position
	
	# Set end height to create downhill progression
	path2d.end_height = total_descent
	current_elevation += total_descent
	
	# Choose valley type based on weighted probability and difficulty
	var valley_type = choose_valley_type()
	path2d.valley_type = valley_type
	
	# Adjust chaos and steepness based on progression
	path2d.chaos_factor = 0.2 + (difficulty_progression * 0.3)
	path2d.steepness = 0.3 + (difficulty_progression * 0.2)
	path2d.downhill_slope = total_descent
	path2d.smoothness = 1 + randf_range(-0.2, 0.3)  # Add some variation to smoothness
	
	# Vary segment dimensions for more chaos
	path2d.width = segment_length + randf_range(-100, 200)
	path2d.depth = 100 + randf_range(-30, 80) + (difficulty_progression * 50)

func apply_mountain_styling(segment):
	var path2d = segment.get_node("Path2D")
	if not path2d:
		return
	
	# Find existing polygon - don't create if it doesn't exist
	var polygon = path2d.get_node_or_null("Polygon2D")
	if polygon:
		# DON'T override the existing color - preserve what's already set
		# Only add blending material for seamless transitions
		setup_blending_material(polygon)
	
	# Create background mountain layers for depth
	var depth_factor = min(spawned_segments.size() * 0.1, 1.0)
	create_background_layers(path2d, depth_factor)

func setup_blending_material(polygon: Polygon2D):
	var material = CanvasItemMaterial.new()
	material.blend_mode = CanvasItemMaterial.BLEND_MODE_MIX
	
	# Add subtle transparency at edges for seamless blending
	material.light_mode = CanvasItemMaterial.LIGHT_MODE_NORMAL
	polygon.material = material

func create_background_layers(path2d: Node2D, depth_factor: float):
	# Create multiple background mountain silhouettes for depth
	var layer_count = min(3, int(spawned_segments.size() * 0.2) + 1)
	
	for i in range(layer_count):
		var layer_depth = (i + 1) * 0.3 + depth_factor
		
		# Create background layer polygon
		var bg_polygon = Polygon2D.new()
		bg_polygon.name = "BackgroundLayer" + str(i)
		bg_polygon.z_index = -10 - i  # Behind main terrain
		
		
		# Scale and position for parallax effect
		var scale_factor = 1.0 - (layer_depth * 0.2)
		bg_polygon.scale = Vector2(scale_factor, scale_factor)
		bg_polygon.position = Vector2(0, -50 * (i + 1))  # Offset upward
		
		path2d.add_child(bg_polygon)

func choose_valley_type() -> int:
	# Adjust weights based on difficulty progression
	var adjusted_weights = valley_type_weights.duplicate()
	
	# As difficulty increases, reduce smooth valleys and increase challenging ones
	var difficulty_factor = min(difficulty_progression, 1.0)
	adjusted_weights[0] = max(5, 25 - (difficulty_factor * 15))  # SMOOTH decreases
	adjusted_weights[1] += difficulty_factor * 10  # JAGGED increases
	adjusted_weights[2] += difficulty_factor * 15  # STEEP_DROP increases
	adjusted_weights[5] += difficulty_factor * 10  # CLIFF_FACE increases
	
	# Calculate total weight
	var total_weight = 0
	for weight in adjusted_weights.values():
		total_weight += weight
	
	# Random selection based on weights
	var random_value = randf() * total_weight
	var current_weight = 0
	
	for valley_type in adjusted_weights.keys():
		current_weight += adjusted_weights[valley_type]
		if random_value <= current_weight:
			return valley_type
	
	return 0  # Default to SMOOTH if something goes wrong

func update_difficulty_progression():
	difficulty_progression += 0.02  # Gradually increase difficulty
	difficulty_progression = min(difficulty_progression, 2.0)  # Cap at 2x difficulty
	
	# Occasionally add variety by adjusting downhill rate
	if randf() < 0.1:  # 10% chance
		downhill_rate += randf_range(-5, 10)
		downhill_rate = max(20, min(downhill_rate, 60))  # Keep within reasonable bounds

func smooth_segment_transition(new_segment):
	# Enhanced blending between segments
	if spawned_segments.size() > 1:
		var prev_segment = spawned_segments[spawned_segments.size() - 2]
		blend_segments_seamlessly(prev_segment, new_segment)

func blend_segments_seamlessly(prev_segment, new_segment):
	var prev_path = prev_segment.get_node_or_null("Path2D")
	var new_path = new_segment.get_node_or_null("Path2D")
	
	if not prev_path or not new_path:
		return
	
	var prev_polygon = prev_path.get_node_or_null("Polygon2D")
	var new_polygon = new_path.get_node_or_null("Polygon2D")
	
	if not prev_polygon or not new_polygon:
		return
	
	# DON'T override existing colors - let the polygons keep their original colors
	# Only create transition zones if needed
	create_transition_zone(prev_segment, new_segment)

func create_transition_zone(prev_segment, new_segment):
	# Get the existing polygon colors for blending
	var prev_path = prev_segment.get_node_or_null("Path2D")
	var new_path = new_segment.get_node_or_null("Path2D")
	
	if not prev_path or not new_path:
		return
	
	var prev_polygon = prev_path.get_node_or_null("Polygon2D")
	var new_polygon = new_path.get_node_or_null("Polygon2D")
	
	if not prev_polygon or not new_polygon:
		return
	
	# Create a blending polygon in the overlap zone using existing colors
	var transition_polygon = Polygon2D.new()
	transition_polygon.name = "TransitionBlend"
	transition_polygon.z_index = -1  # Behind main terrain but in front of background
	
	# Blend between the two existing colors
	var blend_color = prev_polygon.color.lerp(new_polygon.color, 0.5)
	transition_polygon.color = Color(blend_color.r, blend_color.g, blend_color.b, 0.3)  # Semi-transparent
	
	# Position in overlap area
	transition_polygon.position = Vector2(-segment_overlap/2, 0)
	
	# Add to new segment
	new_path.add_child(transition_polygon)

func cleanup_old_segments():
	for seg in spawned_segments:
		if seg.global_position.x + segment_length < player.global_position.x - segment_length:
			seg.queue_free()
			spawned_segments.erase(seg)

func reset_terrain():
	print("Resetting terrain generation...")
	
	# Clear all spawned segments
	for seg in spawned_segments:
		if is_instance_valid(seg):
			seg.queue_free()
	spawned_segments.clear()
	
	# Clear all obstacles
	if obstacle_spawner:
		obstacle_spawner.clear_all_obstacles()
		# Reset obstacle spawner state
		obstacle_spawner.last_checkpoint = 0
		obstacle_spawner.max_obstacles = 1
	
	# Reset progression variables
	current_elevation = 0
	difficulty_progression = 0.1
	downhill_rate = 30
	
	# Reset terrain generation position to starting valley
	initialize_starting_position()
	
	print("Terrain reset complete. Ready to generate from beginning.")

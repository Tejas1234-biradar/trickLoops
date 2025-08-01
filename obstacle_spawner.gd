extends Node2D
class_name ObstacleSpawner

@export var obstacle_scene: PackedScene
@export var min_spacing := 80.0  # Minimum distance between obstacles
@export var surface_offset := 10.0  # How far above surface to place obstacles
@export var edge_buffer := 50.0  # Stay away from segment edges
@export var max_slope_angle := 45.0  # Maximum slope in degrees to spawn on

var player: Node2D
var last_checkpoint := 0
var max_obstacles := 1
var spawned_obstacles: Array[Node2D] = []

func initialize(player_ref: Node2D):
	player = player_ref

func spawn_obstacles_on_segment(segment: Node2D):
	if not obstacle_scene:
		print("No obstacle scene assigned!")
		return
	
	
	
	# Update obstacle count based on player progress
	update_obstacle_difficulty()
	
	# Look for Path2D in the segment - try multiple paths
	var path2d = segment.get_node_or_null("Path2D")
	if not path2d:
		print("No Path2D found in segment! Available children:")
		
		return
	
	
	
	# Try to find collision polygon - check multiple possible locations
	var collision_poly = null
	var possible_paths = [
		"StaticBody2D/CollisionPolygon2D",
		"CollisionPolygon2D", 
		"StaticBody2D/CollisionShape2D",
		"CollisionShape2D"
	]
	
	for path in possible_paths:
		collision_poly = path2d.get_node_or_null(path)
		if collision_poly:
			print("Found collision at: ", path)
			break
	
	if not collision_poly:
		print("No collision polygon found! Path2D children:")
		
		
		# Fallback: try to use the Path2D curve directly
		
		spawn_obstacles_using_curve(segment, path2d)
		return
	
	# Get polygon points
	var poly = null
	if collision_poly.has_method("get_polygon"):
		poly = collision_poly.get_polygon()
	elif collision_poly.has_method("get_shape") and collision_poly.get_shape():
		var shape = collision_poly.get_shape()
		if shape is RectangleShape2D:
			var rect = shape as RectangleShape2D
			var size = rect.size
			poly = PackedVector2Array([
				Vector2(-size.x/2, -size.y/2),
				Vector2(size.x/2, -size.y/2),
				Vector2(size.x/2, size.y/2),
				Vector2(-size.x/2, size.y/2)
			])
		elif shape.has_method("get_points"):
			poly = shape.get_points()
	
	if not poly or poly.size() < 2:
		print("Invalid polygon! Size: ", poly.size() if poly else 0)
		# Fallback method
		spawn_obstacles_using_curve(segment, path2d)
		return
	
	print("Polygon points: ", poly.size())
	
	# Find valid spawn positions
	var spawn_positions = find_valid_spawn_positions(poly, path2d)
	
	
	if spawn_positions.size() == 0:
		print("No valid spawn positions found!")
		return
	
	# Randomly select positions to spawn obstacles
	var obstacle_count = min(randi_range(1, max_obstacles), spawn_positions.size())
	spawn_positions.shuffle()
	
	print("Spawning ", obstacle_count, " obstacles")
	
	for i in range(obstacle_count):
		spawn_obstacle_at_position(spawn_positions[i], path2d)
	


# Fallback method using Path2D curve directly
func spawn_obstacles_using_curve(segment: Node2D, path2d: Node2D):
	print("Using curve fallback method")
	
	if not path2d.curve:
		print("No curve found in Path2D!")
		return
	
	var curve = path2d.curve
	var curve_length = curve.get_baked_length()
	
	if curve_length <= 0:
		print("Curve has no length!")
		return
	
	var obstacle_count = randi_range(1, max_obstacles)
	print("Spawning ", obstacle_count, " obstacles using curve")
	
	for i in range(obstacle_count):
		# Pick a random position along the curve
		var t = randf_range(0.2, 0.8)  # Stay away from edges
		var curve_pos = curve.sample_baked(t * curve_length)
		
		# Create obstacle
		var obs = obstacle_scene.instantiate()
		obs.global_position = path2d.global_position + curve_pos + Vector2(0, -surface_offset)
		
		# Add to obstacle group
		if not obs.is_in_group("obstacle"):
			obs.add_to_group("obstacle")
		
		# Add to scene
		get_tree().current_scene.add_child(obs)
		spawned_obstacles.append(obs)
		
		print("Spawned obstacle at: ", obs.global_position)

func update_obstacle_difficulty():
	if not player:
		return
		
	var player_dist = int(player.global_position.x / 10)
	if player_dist - last_checkpoint >= 100:
		max_obstacles = min(max_obstacles + 1, 4)  # Cap at 4 obstacles per segment
		last_checkpoint = player_dist

func find_valid_spawn_positions(polygon: PackedVector2Array, path2d: Node2D) -> Array[Dictionary]:
	var valid_positions: Array[Dictionary] = []
	
	# Find the bounds of the polygon
	var min_x = polygon[0].x
	var max_x = polygon[0].x
	var min_y = polygon[0].y
	var max_y = polygon[0].y
	
	for point in polygon:
		min_x = min(min_x, point.x)
		max_x = max(max_x, point.x)
		min_y = min(min_y, point.y)
		max_y = max(max_y, point.y)
	
	
	# Sample positions across the segment width
	var sample_step = 20.0
	var current_x = min_x + edge_buffer
	var tested_positions = 0
	var valid_surface_found = 0
	var valid_slope_found = 0
	var valid_spacing_found = 0
	
	while current_x <= max_x - edge_buffer:
		tested_positions += 1
		var surface_data = get_surface_data_at_x(polygon, current_x)
		
		if surface_data.valid:
			valid_surface_found += 1
			
			# Check if slope is acceptable
			var slope_degrees = abs(rad_to_deg(surface_data.slope_angle))
			if slope_degrees <= max_slope_angle:
				valid_slope_found += 1
				
				# Check spacing from existing positions
				if is_position_valid_spacing(current_x, valid_positions):
					valid_spacing_found += 1
					valid_positions.append({
						"x": current_x,
						"y": surface_data.y,
						"slope": surface_data.slope_angle,
						"world_pos": path2d.global_position + Vector2(current_x, surface_data.y - surface_offset)
					})
				
		
		current_x += sample_step
	
	
	
	return valid_positions

func get_surface_data_at_x(polygon: PackedVector2Array, target_x: float) -> Dictionary:
	var surface_y = INF
	var best_slope = 0.0
	var found_valid = false
	
	# Simple approach: find the topmost point at this X coordinate
	for i in range(polygon.size()):
		var p1 = polygon[i]
		var p2 = polygon[(i + 1) % polygon.size()]
		
		# Check if the X coordinate is within this edge's X range
		var min_x = min(p1.x, p2.x)
		var max_x = max(p1.x, p2.x)
		
		if target_x >= min_x and target_x <= max_x:
			# Calculate Y at target_x using linear interpolation
			var t = 0.0
			if abs(p2.x - p1.x) > 0.001:
				t = (target_x - p1.x) / (p2.x - p1.x)
			var y_at_x = p1.y + t * (p2.y - p1.y)
			
			# Simply take the highest point (lowest Y value)
			if y_at_x < surface_y:
				surface_y = y_at_x
				var edge_vector = p2 - p1
				best_slope = edge_vector.angle()
				found_valid = true
	
	return {
		"valid": found_valid,
		"y": surface_y if found_valid else 0.0,
		"slope_angle": best_slope
	}

func is_top_surface_edge(polygon: PackedVector2Array, edge_index: int, y_pos: float) -> bool:
	# Calculate polygon center Y
	var poly_center_y = 0.0
	for point in polygon:
		poly_center_y += point.y
	poly_center_y /= polygon.size()
	
	# Must be above center
	if y_pos >= poly_center_y:
		return false
	
	var p1 = polygon[edge_index]
	var p2 = polygon[(edge_index + 1) % polygon.size()]
	var edge_vector = p2 - p1
	
	# Check if edge is mostly horizontal (part of ground surface)
	var is_mostly_horizontal = abs(edge_vector.x) > abs(edge_vector.y) * 2
	
	# Check if edge is facing upward (normal points up)
	var edge_normal = Vector2(-edge_vector.y, edge_vector.x).normalized()
	var faces_up = edge_normal.y < -0.5  # Normal pointing upward
	
	return is_mostly_horizontal and faces_up

func is_position_valid_spacing(x_pos: float, existing_positions: Array[Dictionary]) -> bool:
	for pos_data in existing_positions:
		if abs(x_pos - pos_data.x) < min_spacing:
			return false
	return true

func spawn_obstacle_at_position(position_data: Dictionary, path2d: Node2D):
	var obs = obstacle_scene.instantiate()
	
	# Set position
	obs.global_position = position_data.world_pos
	
	# Set rotation to match slope
	obs.rotation = position_data.slope
	
	# Add to obstacle group if not already in it
	if not obs.is_in_group("obstacle"):
		obs.add_to_group("obstacle")
	
	# Add to scene
	get_tree().current_scene.add_child(obs)
	spawned_obstacles.append(obs)

func cleanup_old_obstacles(player_position: Vector2, cleanup_distance: float = 1200.0):
	var obstacles_to_remove: Array[Node2D] = []
	
	for obstacle in spawned_obstacles:
		if not is_instance_valid(obstacle):
			obstacles_to_remove.append(obstacle)
			continue
			
		if obstacle.global_position.x < player_position.x - cleanup_distance:
			obstacles_to_remove.append(obstacle)
			obstacle.queue_free()
	
	# Remove from tracking array
	for obstacle in obstacles_to_remove:
		spawned_obstacles.erase(obstacle)

func get_obstacle_count() -> int:
	return spawned_obstacles.size()

func clear_all_obstacles():
	for obstacle in spawned_obstacles:
		if is_instance_valid(obstacle):
			obstacle.queue_free()
	spawned_obstacles.clear()

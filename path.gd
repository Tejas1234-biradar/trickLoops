extends Path2D

@export var width := 512
@export var depth := 100
@export var steepness := 0.3
@export var start_height := 0
@export var end_height := 0

# New properties for variety and downhill
@export var valley_type := ValleyType.SMOOTH  # Can be set by spawner
@export var chaos_factor := 0.3  # How much randomness to add
@export var downhill_slope := 20  # How much lower the end should be
@export var smoothness := 0.5  # Controls how smooth the curves are (0.0 = sharp, 1.0 = very smooth)

enum ValleyType {
	SMOOTH,
	JAGGED,
	STEEP_DROP,
	GENTLE_SLOPE,
	DOUBLE_DIP,
	CLIFF_FACE,
	BUMPY
}

func _ready():
	# Add some randomness to make each valley unique
	randomize_properties()
	
	var curve = Curve2D.new()
	
	# Apply downhill progression
	end_height = start_height + downhill_slope
	
	# Generate valley based on type
	match valley_type:
		ValleyType.SMOOTH:
			generate_smooth_valley(curve)
		ValleyType.JAGGED:
			generate_jagged_valley(curve)
		ValleyType.STEEP_DROP:
			generate_steep_drop_valley(curve)
		ValleyType.GENTLE_SLOPE:
			generate_gentle_slope_valley(curve)
		ValleyType.DOUBLE_DIP:
			generate_double_dip_valley(curve)
		ValleyType.CLIFF_FACE:
			generate_cliff_face_valley(curve)
		ValleyType.BUMPY:
			generate_bumpy_valley(curve)
	
	self.curve = curve
	
	# Create smooth tessellation
	var points = curve.tessellate(12, 1.0)  # More points for smoother curves
	
	# Convert to polygon
	var poly_points = []
	for point in points:
		poly_points.append(point)
	
	# Close the polygon shape with ground
	poly_points.append(Vector2(width, 1000))
	poly_points.append(Vector2(0, 1000))
	
	# Update visuals and collision
	$Polygon2D.polygon = poly_points
	$StaticBody2D/CollisionPolygon2D.polygon = poly_points
	
	# Position markers programmatically
	call_deferred("position_markers")

func randomize_properties():
	# Add some randomness to base properties
	width += randf_range(-50, 100)
	depth += randf_range(-20, 40)
	steepness += randf_range(-0.1, 0.2)
	chaos_factor = randf_range(0.1, 0.5)

func generate_smooth_valley(curve: Curve2D):
	# Your original smooth valley with some chaos and improved smoothness
	var chaos = chaos_factor * 20
	var smooth_factor = smoothness * width * 0.15  # Tangent length based on smoothness
	
	curve.add_point(Vector2(0, start_height), Vector2(0, 0), Vector2(smooth_factor, depth * 0.1))
	curve.add_point(
		Vector2(width * 0.2 + randf_range(-chaos, chaos), depth * steepness * 0.5 + randf_range(-chaos/2, chaos/2)), 
		Vector2(-smooth_factor * 0.7, -depth * 0.1), 
		Vector2(smooth_factor * 0.7, depth * 0.1)
	)
	curve.add_point(
		Vector2(width * 0.5 + randf_range(-chaos, chaos), depth + randf_range(-chaos/3, chaos/3)), 
		Vector2(-smooth_factor * 1.2, 0), 
		Vector2(smooth_factor * 1.2, 0)
	)
	curve.add_point(
		Vector2(width * 0.8 + randf_range(-chaos, chaos), depth * steepness * 0.5 + randf_range(-chaos/2, chaos/2)), 
		Vector2(-smooth_factor * 0.7, -depth * 0.1), 
		Vector2(smooth_factor * 0.7, depth * 0.1)
	)
	curve.add_point(Vector2(width, end_height), Vector2(-smooth_factor, -depth * 0.1), Vector2(0, 0))

func generate_jagged_valley(curve: Curve2D):
	# Sharp, angular valley with many points but still respecting smoothness
	var smooth_factor = smoothness * 30  # Reduced smoothing for jagged effect
	
	curve.add_point(Vector2(0, start_height), Vector2(0, 0), Vector2(smooth_factor, 0))
	
	var num_points = randi_range(6, 10)
	for i in range(1, num_points):
		var x = (float(i) / num_points) * width
		var base_y = sin(PI * float(i) / num_points) * depth
		var chaos_y = randf_range(-depth * 0.3, depth * 0.3)
		var y = base_y + chaos_y
		
		# Controlled tangent smoothing based on smoothness
		var tangent_strength = smooth_factor * (0.5 + randf_range(-0.2, 0.2))
		curve.add_point(Vector2(x, y), Vector2(-tangent_strength, randf_range(-10, 10)), Vector2(tangent_strength, randf_range(-10, 10)))
	
	curve.add_point(Vector2(width, end_height), Vector2(-smooth_factor, 0), Vector2(0, 0))

func generate_steep_drop_valley(curve: Curve2D):
	# Sudden steep drop with smooth transitions
	var smooth_factor = smoothness * width * 0.1
	
	curve.add_point(Vector2(0, start_height), Vector2(0, 0), Vector2(smooth_factor, 0))
	curve.add_point(Vector2(width * 0.1, start_height + randf_range(-10, 10)), Vector2(-smooth_factor * 0.5, 0), Vector2(smooth_factor * 0.5, 0))
	curve.add_point(Vector2(width * 0.3, depth * 1.2), Vector2(-smooth_factor * 0.8, -depth * smoothness * 0.5), Vector2(smooth_factor * 1.2, depth * smoothness * 0.3))
	curve.add_point(Vector2(width * 0.7, depth * 0.8 + randf_range(-20, 20)), Vector2(-smooth_factor * 1.2, 0), Vector2(smooth_factor * 0.8, 0))
	curve.add_point(Vector2(width, end_height), Vector2(-smooth_factor, 0), Vector2(0, 0))

func generate_gentle_slope_valley(curve: Curve2D):
	# Gradual downward slope with smooth curves
	var smooth_factor = smoothness * width * 0.12
	
	curve.add_point(Vector2(0, start_height), Vector2(0, 0), Vector2(smooth_factor, 0))
	curve.add_point(Vector2(width * 0.25, depth * 0.3 + randf_range(-15, 15)), Vector2(-smooth_factor * 0.8, 0), Vector2(smooth_factor * 0.8, 0))
	curve.add_point(Vector2(width * 0.5, depth * 0.6 + randf_range(-15, 15)), Vector2(-smooth_factor * 1.0, 0), Vector2(smooth_factor * 1.0, 0))
	curve.add_point(Vector2(width * 0.75, depth * 0.4 + randf_range(-15, 15)), Vector2(-smooth_factor * 0.8, 0), Vector2(smooth_factor * 0.8, 0))
	curve.add_point(Vector2(width, end_height), Vector2(-smooth_factor, 0), Vector2(0, 0))

func generate_double_dip_valley(curve: Curve2D):
	# Two valley dips with smooth transitions
	var smooth_factor = smoothness * width * 0.08
	
	curve.add_point(Vector2(0, start_height), Vector2(0, 0), Vector2(smooth_factor, 0))
	curve.add_point(Vector2(width * 0.2, depth * 0.7), Vector2(-smooth_factor * 1.2, 0), Vector2(smooth_factor * 1.2, 0))
	curve.add_point(Vector2(width * 0.4, depth * 0.3 + randf_range(-10, 10)), Vector2(-smooth_factor * 0.8, 0), Vector2(smooth_factor * 0.8, 0))
	curve.add_point(Vector2(width * 0.6, depth * 0.8), Vector2(-smooth_factor * 1.2, 0), Vector2(smooth_factor * 1.2, 0))
	curve.add_point(Vector2(width * 0.8, depth * 0.2 + randf_range(-10, 10)), Vector2(-smooth_factor * 0.8, 0), Vector2(smooth_factor * 0.8, 0))
	curve.add_point(Vector2(width, end_height), Vector2(-smooth_factor, 0), Vector2(0, 0))

func generate_cliff_face_valley(curve: Curve2D):
	# Nearly vertical drops but with controlled smoothness
	var smooth_factor = smoothness * width * 0.05  # Less smoothing for cliff effect
	
	curve.add_point(Vector2(0, start_height), Vector2(0, 0), Vector2(smooth_factor, 0))
	curve.add_point(Vector2(width * 0.15, start_height + randf_range(-5, 5)), Vector2(-smooth_factor * 0.5, 0), Vector2(smooth_factor * 0.5, 0))
	curve.add_point(Vector2(width * 0.2, depth * 1.3), Vector2(0, -depth * smoothness * 0.3), Vector2(0, depth * smoothness * 0.5))
	curve.add_point(Vector2(width * 0.8, depth * 1.1 + randf_range(-30, 30)), Vector2(-smooth_factor * 2.0, 0), Vector2(smooth_factor * 1.5, 0))
	curve.add_point(Vector2(width * 0.85, end_height + randf_range(-5, 5)), Vector2(-smooth_factor * 0.5, 0), Vector2(smooth_factor * 0.5, 0))
	curve.add_point(Vector2(width, end_height), Vector2(-smooth_factor, 0), Vector2(0, 0))

func generate_bumpy_valley(curve: Curve2D):
	# Lots of small bumps and variations with smooth connections
	var smooth_factor = smoothness * 25  # Moderate smoothing for bumpy effect
	
	curve.add_point(Vector2(0, start_height), Vector2(0, 0), Vector2(smooth_factor, 0))
	
	var num_bumps = randi_range(8, 15)
	for i in range(1, num_bumps):
		var x = (float(i) / num_bumps) * width
		var base_y = sin(PI * 2 * float(i) / num_bumps) * depth * 0.3 + depth * 0.6
		var bump_y = randf_range(-depth * 0.2, depth * 0.2)
		var y = base_y + bump_y
		
		# Vary tangent strength for bumpy effect
		var tangent_strength = smooth_factor * randf_range(0.5, 1.2)
		var tangent_y_variation = randf_range(-smooth_factor * 0.3, smooth_factor * 0.3)
		curve.add_point(Vector2(x, y), Vector2(-tangent_strength, tangent_y_variation), Vector2(tangent_strength, -tangent_y_variation))
	
	curve.add_point(Vector2(width, end_height), Vector2(-smooth_factor, 0), Vector2(0, 0))

func position_markers():
	# Get the valley parent node
	var valley_parent = get_parent()
	
	# Get or create the markers as children of the valley
	var start_marker = valley_parent.get_node_or_null("StartMarker")
	var end_marker = valley_parent.get_node_or_null("EndMarker")
	
	# If markers don't exist, create them
	if not start_marker:
		start_marker = Marker2D.new()
		start_marker.name = "StartMarker"
		valley_parent.add_child(start_marker)
	
	if not end_marker:
		end_marker = Marker2D.new()
		end_marker.name = "EndMarker"
		valley_parent.add_child(end_marker)
	
	# Position markers at the curve start and end points
	var curve_start = curve.sample_baked(0.0)
	var curve_end = curve.sample_baked(curve.get_baked_length())
	
	# Convert Path2D local positions to Valley local positions
	start_marker.position = position + curve_start
	end_marker.position = position + curve_end

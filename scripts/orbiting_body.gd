extends CharacterBody2D
## Physics-based orbit controller using Godot's built-in physics engine
## The orbiting body is controlled via arrow key thrust
## The central body exerts gravity on the orbiting body

@export var thrust_force: float = 300.0  # Force applied by thrust input (reduced from 100.0)
@export var gravitational_constant: float = 500000.0  # Gravitational constant (much stronger)
@export var base_sphere_of_influence: float = 350.0  # Base radius of gravitational influence (reduced from 500)
@export var proximity_gravity_boost: float = 3.0  # Extra gravity multiplier at close range (1.0 = no boost)
@export var proximity_threshold: float = 150.0  # Distance at which proximity boost starts
@export var show_sphere_of_influence: bool = true  # Draw the sphere of influence
@export var mass: float = 50.0  # Mass of this body (increased from 10.0)
@export var show_velocity_vector: bool = true  # Draw velocity vector
@export var bounce_coefficient: float = 0.8  # How much velocity is retained after bounce (0-1)
@export var body_radius: float = 15.0  # Radius of the body for collision detection
@export var viewport_width: float = 5000.0  # Width of play area (match ColorRect width)
@export var viewport_height: float = 5000.0  # Height of play area (match ColorRect height)
@export var show_orbit_trail: bool = true  # Draw the orbit trail
@export var orbit_trail_color: Color = Color.BLUE  # Color of the orbit trail
@export var trail_max_points: int = 500  # Maximum points to store for trail
@export var use_escape_velocity_thrust: bool = false  # Scale thrust to achieve escape velocity (disabled for controlled movement)
@export var thrust_angle_rotation_speed: float = 180.0  # Degrees per second for rotating thrust direction
@export var show_thrust_indicator: bool = true  # Draw arrow showing thrust direction
@export var show_trajectory: bool = true  # Draw predicted trajectory
@export var trajectory_prediction_time: float = 5.0  # How far into the future to predict (seconds)
@export var trajectory_points: int = 60  # Number of points to calculate for trajectory
@export var trajectory_color: Color = Color(1.0, 1.0, 0.0, 0.7)  # Yellow with some transparency

var central_bodies: Array = []  # Array of all gravitational bodies
var orbit_trail: PackedVector2Array = []  # Stores positions along the orbit
var trail_update_counter: int = 0  # Counter to sample every N frames
var thrust_angle: float = 0.0  # Current thrust direction angle in degrees
var gravity_debug_printed: bool = false  # Flag to print gravity debug info only once
var predicted_trajectory: PackedVector2Array = []  # Stores predicted future positions


func _ready() -> void:
	# Get references to all nodes with central_body script attached
	var root = get_tree().root
	
	# First, try to find nodes that have the central_body.gd script
	central_bodies = _find_all_nodes_with_script(root, "central_body")
	
	if central_bodies.is_empty():
		print("No nodes with central_body.gd script found, trying by name 'CentralBody'...")
		central_bodies = _find_all_nodes_by_name(root, "CentralBody")
	
	if central_bodies.is_empty():
		print("Still no match, trying 'Earth'...")
		central_bodies = _find_all_nodes_by_name(root, "Earth")
	
	if central_bodies.is_empty():
		print("ERROR: No gravitational bodies found in scene!")
		print("Full scene tree:")
		_print_scene_tree(root, 0)
	else:
		print("✓ Orbiting body initialized with %d gravitational bodies" % central_bodies.size())
		for i in range(central_bodies.size()):
			var body = central_bodies[i]
			print("  [%d] %s (type: %s) at %v" % [i + 1, body.name, body.get_class(), body.global_position])
			# Try to access mass - it should be an export variable
			if body.has_meta("mass"):
				print("      └─ mass (meta): %.1f" % body.get_meta("mass"))
			elif body.get("mass") != null:
				print("      └─ mass: %.1f" % body.get("mass"))
			else:
				print("      └─ mass: UNABLE TO ACCESS")
		print("Controls:")
		print("  Arrow keys LEFT/RIGHT - Rotate thrust direction")
		print("  Space - Apply thrust")
		print("  W - Increase gravity")
		print("  S - Decrease gravity")


func _find_all_nodes_with_script(node: Node, script_name: String) -> Array:
	## Recursively find all nodes that have a script matching the given name
	var result: Array = []
	
	# Check if this node has a script and matches the name
	if node.get_script() != null:
		var script_filename = node.get_script().resource_path.get_file().trim_suffix(".gd")
		if script_filename == script_name:
			result.append(node)
	
	# Recursively check children
	for child in node.get_children():
		result.append_array(_find_all_nodes_with_script(child, script_name))
	
	return result


func _find_all_nodes_by_name(node: Node, node_name: String) -> Array:
	## Recursively find all nodes with a specific name
	var result: Array = []
	
	if node.name == node_name:
		result.append(node)
	
	# Recursively check children
	for child in node.get_children():
		result.append_array(_find_all_nodes_by_name(child, node_name))
	
	return result


func _print_scene_tree(node: Node, indent: int = 0) -> void:
	## Print the scene tree for debugging
	var indent_str = ""
	for _i in range(indent):
		indent_str += "  "
	print("%s- %s" % [indent_str, node.name])
	for child in node.get_children():
		_print_scene_tree(child, indent + 1)


func _physics_process(delta: float) -> void:
	# Handle thrust input
	handle_thrust_input(delta)
	
	# Apply gravity from all central bodies
	apply_gravity_from_all_bodies(delta)
	
	# Rotate ship to face thrust direction
	# The sprite points UP by default, but thrust_angle 0 = RIGHT (cos/sin convention)
	# So we subtract 90 degrees to align the sprite with the thrust vector
	rotation = deg_to_rad(thrust_angle - 90)
	
	# Move the body using velocity
	move_and_slide()
	
	# Handle bouncing off screen edges
	handle_screen_bounce()
	
	# Update orbit trail
	update_orbit_trail()
	
	# Calculate predicted trajectory
	calculate_trajectory()
	
	# Queue redraw for debug visualization
	queue_redraw()


func handle_thrust_input(delta: float) -> void:
	# Handle thrust angle rotation with left/right arrows
	if Input.is_action_pressed("ui_left"):
		thrust_angle += thrust_angle_rotation_speed * delta
	if Input.is_action_pressed("ui_right"):
		thrust_angle -= thrust_angle_rotation_speed * delta
	
	# Normalize angle to 0-360 range
	while thrust_angle < 0:
		thrust_angle += 360
	while thrust_angle >= 360:
		thrust_angle -= 360
	
	# Apply thrust only when Space is pressed
	if Input.is_action_pressed("ui_select"):
		# Convert angle to radians
		var thrust_angle_rad = deg_to_rad(thrust_angle)
		
		# Calculate thrust direction (inverted - thrust pushes opposite to where arrow points)
		var thrust_direction = Vector2(
			-cos(thrust_angle_rad),
			-sin(thrust_angle_rad)
		)
		
		# Determine the effective thrust force
		var effective_thrust = thrust_force
		if use_escape_velocity_thrust:
			effective_thrust = calculate_escape_velocity_thrust()
		
		# Apply thrust
		velocity += (thrust_direction * effective_thrust) * delta


func calculate_sphere_of_influence() -> float:
	# Sphere of influence increases with gravitational constant
	# Formula: SOI = base * sqrt(G_current / G_base)
	var base_gravity = 100000.0  # Reference gravity value
	var gravity_ratio = gravitational_constant / base_gravity
	return base_sphere_of_influence * sqrt(gravity_ratio)


func calculate_escape_velocity_thrust() -> float:
	# Calculate the required thrust to achieve escape velocity
	# When multiple bodies, use the closest one
	
	if central_bodies.is_empty():
		return thrust_force
	
	# Find closest body
	var closest_body = null
	var closest_distance = INF
	
	for body in central_bodies:
		var dist = (body.global_position - global_position).length()
		if dist < closest_distance:
			closest_distance = dist
			closest_body = body
	
	if closest_body == null or closest_distance < 1.0:
		return thrust_force
	
	# Calculate escape velocity at current distance to closest body
	var escape_velocity = sqrt((2.0 * gravitational_constant * closest_body.mass) / closest_distance)
	
	# Calculate the thrust needed to reach escape velocity from current velocity
	# Scaled so it takes about 5 seconds to reach escape velocity from rest
	var required_acceleration = escape_velocity / 5.0
	
	# Convert acceleration to thrust force: F = m * a
	return required_acceleration * mass


func calculate_current_escape_velocity() -> float:
	# Get the escape velocity at current position (closest body)
	if central_bodies.is_empty():
		return 0.0
	
	# Find closest body
	var closest_body = null
	var closest_distance = INF
	
	for body in central_bodies:
		var dist = (body.global_position - global_position).length()
		if dist < closest_distance:
			closest_distance = dist
			closest_body = body
	
	if closest_body == null or closest_distance < 1.0:
		return 0.0
	
	return sqrt((2.0 * gravitational_constant * closest_body.mass) / closest_distance)


func apply_gravity_from_all_bodies(delta: float) -> void:
	# Apply gravity from all central bodies
	if not gravity_debug_printed:
		print("DEBUG: apply_gravity_from_all_bodies called. Bodies count: %d" % central_bodies.size())
	
	if central_bodies.is_empty():
		if not gravity_debug_printed:
			print("DEBUG: No central bodies found in gravity function!")
			gravity_debug_printed = true
		return
	
	if not gravity_debug_printed:
		print("DEBUG: Found %d central bodies, applying gravity" % central_bodies.size())
		for body in central_bodies:
			print("  - %s: mass=%.1f, pos=%v" % [body.name, body.mass, body.global_position])
		gravity_debug_printed = true
	
	for body in central_bodies:
		if body == null:
			continue
			
		var direction_to_center = body.global_position - global_position
		var distance = direction_to_center.length()
		
		# Calculate current sphere of influence
		var soi = calculate_sphere_of_influence()
		
		# Only apply gravity if within sphere of influence
		if distance > 1.0 and distance <= soi:
			# Calculate gravitational acceleration: a = G * M / r^2
			var gravitational_acceleration = (gravitational_constant * body.mass) / (distance * distance)
			
			# Apply proximity boost - gravity gets stronger as you get closer
			if distance < proximity_threshold:
				# Smoothly interpolate boost from 1.0 at threshold to proximity_gravity_boost at distance 0
				var proximity_factor = 1.0 - (distance / proximity_threshold)
				var boost = 1.0 + (proximity_gravity_boost - 1.0) * proximity_factor
				gravitational_acceleration *= boost
			
			# Apply acceleration toward this body
			var gravity_acceleration = direction_to_center.normalized() * gravitational_acceleration
			velocity += gravity_acceleration * delta


func calculate_trajectory() -> void:
	# Calculate predicted trajectory by simulating future movement
	predicted_trajectory.clear()
	
	if not show_trajectory:
		return
	
	# Start from current state
	var sim_pos = global_position
	var sim_vel = velocity
	var time_step = trajectory_prediction_time / trajectory_points
	
	# Add starting point
	predicted_trajectory.append(sim_pos)
	
	# Simulate future positions
	for i in range(trajectory_points):
		# Apply gravity from all bodies
		for body in central_bodies:
			if body == null:
				continue
			
			var direction_to_center = body.global_position - sim_pos
			var distance = direction_to_center.length()
			var soi = calculate_sphere_of_influence()
			
			if distance > 1.0 and distance <= soi:
				var gravitational_acceleration = (gravitational_constant * body.mass) / (distance * distance)
				
				# Apply proximity boost
				if distance < proximity_threshold:
					var proximity_factor = 1.0 - (distance / proximity_threshold)
					var boost = 1.0 + (proximity_gravity_boost - 1.0) * proximity_factor
					gravitational_acceleration *= boost
				
				var gravity_dir = direction_to_center.normalized()
				sim_vel += gravity_dir * gravitational_acceleration * time_step
		
		# Update position
		sim_pos += sim_vel * time_step
		
		# Handle boundary bounces in simulation
		if sim_pos.x < body_radius:
			sim_pos.x = body_radius
			sim_vel.x = abs(sim_vel.x) * bounce_coefficient
		elif sim_pos.x > viewport_width - body_radius:
			sim_pos.x = viewport_width - body_radius
			sim_vel.x = -abs(sim_vel.x) * bounce_coefficient
		
		if sim_pos.y < body_radius:
			sim_pos.y = body_radius
			sim_vel.y = abs(sim_vel.y) * bounce_coefficient
		elif sim_pos.y > viewport_height - body_radius:
			sim_pos.y = viewport_height - body_radius
			sim_vel.y = -abs(sim_vel.y) * bounce_coefficient
		
		# Store predicted position
		predicted_trajectory.append(sim_pos)


func handle_screen_bounce() -> void:
	# Check left and right boundaries
	if global_position.x - body_radius < 0:
		global_position.x = body_radius
		velocity.x = abs(velocity.x) * bounce_coefficient
		print("Bounced off left wall")
	elif global_position.x + body_radius > viewport_width:
		global_position.x = viewport_width - body_radius
		velocity.x = -abs(velocity.x) * bounce_coefficient
		print("Bounced off right wall")
	
	# Check top and bottom boundaries
	if global_position.y - body_radius < 0:
		global_position.y = body_radius
		velocity.y = abs(velocity.y) * bounce_coefficient
		print("Bounced off top wall")
	elif global_position.y + body_radius > viewport_height:
		global_position.y = viewport_height - body_radius
		velocity.y = -abs(velocity.y) * bounce_coefficient
		print("Bounced off bottom wall")


func update_orbit_trail() -> void:
	# Update trail every few frames to reduce memory usage
	trail_update_counter += 1
	
	# Only add point every 2 frames
	if trail_update_counter >= 2:
		trail_update_counter = 0
		
		# Add current global position to trail
		orbit_trail.append(global_position)
		
		# Keep trail size limited
		if orbit_trail.size() > trail_max_points:
			orbit_trail.remove_at(0)


func _draw() -> void:
	# Draw predicted trajectory as dotted line
	if show_trajectory and predicted_trajectory.size() > 1:
		var dot_length = 8.0  # Length of each dot
		var gap_length = 12.0  # Gap between dots
		
		for i in range(predicted_trajectory.size() - 1):
			# Convert from global to local coordinates
			var start_global = predicted_trajectory[i]
			var end_global = predicted_trajectory[i + 1]
			var start_local = to_local(start_global)
			var end_local = to_local(end_global)
			
			# Calculate segment properties
			var segment = end_local - start_local
			var segment_length = segment.length()
			var segment_dir = segment.normalized()
			
			# Draw dotted segment
			var current_pos = 0.0
			var is_dot = true
			
			while current_pos < segment_length:
				var next_pos: float
				if is_dot:
					next_pos = min(current_pos + dot_length, segment_length)
					var p1 = start_local + segment_dir * current_pos
					var p2 = start_local + segment_dir * next_pos
					# Fade color based on distance into prediction
					var fade = 1.0 - (float(i) / predicted_trajectory.size()) * 0.7
					var faded_color = Color(trajectory_color.r, trajectory_color.g, trajectory_color.b, trajectory_color.a * fade)
					draw_line(p1, p2, faded_color, 2.0)
					current_pos = next_pos + gap_length
				else:
					current_pos += gap_length
				is_dot = not is_dot
	
	# Draw thrust direction indicator arrow (inverted - points opposite to ship facing)
	# Arrow shows the direction the ship will accelerate (opposite to where nose points)
	if show_thrust_indicator:
		var arrow_length = 60.0
		# Arrow points DOWN in local space (opposite to sprite's forward direction)
		# This matches the inverted thrust vector
		var arrow_end = Vector2(0, arrow_length)  # DOWN in local space (positive Y)
		
		# Draw main arrow line
		var arrow_color = Color.GREEN if Input.is_action_pressed("ui_select") else Color.GRAY
		draw_line(Vector2.ZERO, arrow_end, arrow_color, 3.0)
		
		# Draw arrowhead pointing down in local space
		var arrow_head_size = 10.0
		var head1 = arrow_end + Vector2(-arrow_head_size * 0.5, -arrow_head_size)
		var head2 = arrow_end + Vector2(arrow_head_size * 0.5, -arrow_head_size)
		
		draw_line(arrow_end, head1, arrow_color, 3.0)
		draw_line(arrow_end, head2, arrow_color, 3.0)
	
	if show_velocity_vector and velocity.length() > 0:
		# Draw velocity vector
		draw_line(Vector2.ZERO, velocity.normalized() * 50, Color.RED, 2.0)

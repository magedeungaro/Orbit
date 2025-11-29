extends CharacterBody2D
## Physics-based orbit controller using Godot's built-in physics engine
## The orbiting body is controlled via arrow key thrust
## The central body exerts gravity on the orbiting body

@export var thrust_force: float = 5.0  # Force applied by thrust input (reduced from 100.0)
@export var gravitational_constant: float = 500000.0  # Gravitational constant (much stronger)
@export var gravity_adjustment_rate: float = 5000.0  # How much gravity changes per keystroke
@export var base_sphere_of_influence: float = 500.0  # Base radius of gravitational influence
@export var show_sphere_of_influence: bool = true  # Draw the sphere of influence
@export var mass: float = 50.0  # Mass of this body (increased from 10.0)
@export var show_velocity_vector: bool = true  # Draw velocity vector
@export var bounce_coefficient: float = 0.8  # How much velocity is retained after bounce (0-1)
@export var body_radius: float = 15.0  # Radius of the body for collision detection
@export var viewport_width: float = 3000.0  # Width of play area (match ColorRect width)
@export var viewport_height: float = 2000.0  # Height of play area (match ColorRect height)
@export var show_orbit_trail: bool = true  # Draw the orbit trail
@export var orbit_trail_color: Color = Color.BLUE  # Color of the orbit trail
@export var trail_max_points: int = 500  # Maximum points to store for trail
@export var use_escape_velocity_thrust: bool = false  # Scale thrust to achieve escape velocity (disabled for controlled movement)
@export var thrust_angle_rotation_speed: float = 180.0  # Degrees per second for rotating thrust direction
@export var show_thrust_indicator: bool = true  # Draw arrow showing thrust direction
@export var show_trajectory: bool = false  # Draw predicted trajectory (disabled)
@export var trajectory_prediction_time: float = 3.0  # How far into the future to predict (seconds)
@export var trajectory_points: int = 30  # Number of points to calculate for trajectory

var central_bodies: Array = []  # Array of all gravitational bodies
var orbit_trail: PackedVector2Array = []  # Stores positions along the orbit
var trail_update_counter: int = 0  # Counter to sample every N frames
var thrust_angle: float = 0.0  # Current thrust direction angle in degrees
var gravity_debug_printed: bool = false  # Flag to print gravity debug info only once


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
	
	# Handle gravity control input
	handle_gravity_input()
	
	# Apply gravity from all central bodies
	apply_gravity_from_all_bodies(delta)
	
	# Move the body using velocity
	move_and_slide()
	
	# Handle bouncing off screen edges
	handle_screen_bounce()
	
	# Update orbit trail
	update_orbit_trail()
	
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
		
		# Calculate thrust direction
		var thrust_direction = Vector2(
			cos(thrust_angle_rad),
			sin(thrust_angle_rad)
		)
		
		# Determine the effective thrust force
		var effective_thrust = thrust_force
		if use_escape_velocity_thrust:
			effective_thrust = calculate_escape_velocity_thrust()
		
		# Apply thrust
		velocity += (thrust_direction * effective_thrust) * delta


func handle_gravity_input() -> void:
	# Increase gravity with W key
	if Input.is_key_pressed(KEY_W):
		gravitational_constant += gravity_adjustment_rate * get_physics_process_delta_time()
		print("Gravity increased to: %.0f" % gravitational_constant)
	
	# Decrease gravity with S key
	if Input.is_key_pressed(KEY_S):
		gravitational_constant = max(0, gravitational_constant - gravity_adjustment_rate * get_physics_process_delta_time())
		print("Gravity decreased to: %.0f" % gravitational_constant)


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
			
			# Apply acceleration toward this body
			var gravity_acceleration = direction_to_center.normalized() * gravitational_acceleration
			velocity += gravity_acceleration * delta


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
	# Draw thrust direction indicator arrow
	if show_thrust_indicator:
		var thrust_angle_rad = deg_to_rad(thrust_angle)
		var arrow_length = 60.0
		var arrow_end = Vector2(
			cos(thrust_angle_rad) * arrow_length,
			sin(thrust_angle_rad) * arrow_length
		)
		
		# Draw main arrow line
		var arrow_color = Color.GREEN if Input.is_action_pressed("ui_select") else Color.GRAY
		draw_line(Vector2.ZERO, arrow_end, arrow_color, 3.0)
		
		# Draw arrowhead
		var arrow_head_size = 10.0
		var arrow_head_angle1 = thrust_angle_rad + deg_to_rad(150)
		var arrow_head_angle2 = thrust_angle_rad - deg_to_rad(150)
		
		var head1 = arrow_end + Vector2(cos(arrow_head_angle1) * arrow_head_size, sin(arrow_head_angle1) * arrow_head_size)
		var head2 = arrow_end + Vector2(cos(arrow_head_angle2) * arrow_head_size, sin(arrow_head_angle2) * arrow_head_size)
		
		draw_line(arrow_end, head1, arrow_color, 3.0)
		draw_line(arrow_end, head2, arrow_color, 3.0)
	
	if show_velocity_vector and velocity.length() > 0:
		# Draw velocity vector
		draw_line(Vector2.ZERO, velocity.normalized() * 50, Color.RED, 2.0)
		
		# Draw velocity magnitude text
		var speed_text = "Speed: %.1f" % velocity.length()
		
		# Get or create speed label
		var speed_label: Label
		if not has_node("SpeedLabel"):
			speed_label = Label.new()
			speed_label.name = "SpeedLabel"
			add_child(speed_label)
		else:
			speed_label = get_node("SpeedLabel")
		
		speed_label.text = speed_text
		speed_label.position = Vector2(10, -30)
		speed_label.add_theme_font_size_override("font_size", 12)
		speed_label.add_theme_color_override("font_color", Color.BLACK)
	
	# Display gravity info
	var soi = calculate_sphere_of_influence()
	var escape_vel = calculate_current_escape_velocity()
	var current_speed = velocity.length()
	var escape_percentage = (current_speed / escape_vel * 100.0) if escape_vel > 0 else 0.0
	var gravity_text = "Gravity: %.0f | SOI: %.0f\nEscape V: %.1f (%.0f%%)\nThrust Angle: %.0f°\n(LEFT/RIGHT to rotate, SPACE to thrust)" % [gravitational_constant, soi, escape_vel, escape_percentage, thrust_angle]
	var gravity_label: Label
	if not has_node("GravityLabel"):
		gravity_label = Label.new()
		gravity_label.name = "GravityLabel"
		add_child(gravity_label)
	else:
		gravity_label = get_node("GravityLabel")
	
	gravity_label.text = gravity_text
	gravity_label.position = Vector2(10, -80)
	gravity_label.add_theme_font_size_override("font_size", 12)
	gravity_label.add_theme_color_override("font_color", Color.BLACK)

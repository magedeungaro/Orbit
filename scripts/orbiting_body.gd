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
@export var bounce_coefficient: float = 0.8  # How much velocity is retained after bounce (0-1)
@export var body_radius: float = 15.0  # Radius of the body for collision detection
@export var boundary_left: float = -5000.0  # Left boundary of play area
@export var boundary_top: float = -5000.0  # Top boundary of play area
@export var boundary_right: float = 25000.0  # Right boundary of play area
@export var boundary_bottom: float = 25000.0  # Bottom boundary of play area
@export var show_orbit_trail: bool = true  # Draw the orbit trail
@export var orbit_trail_color: Color = Color.MAGENTA # Color of the orbit trail
@export var trail_max_points: int = 500  # Maximum points to store for trail
@export var use_escape_velocity_thrust: bool = false  # Scale thrust to achieve escape velocity (disabled for controlled movement)
@export var thrust_angle_rotation_speed: float = 180.0  # Degrees per second for rotating thrust direction
@export var show_trajectory: bool = true  # Draw predicted trajectory
@export var trajectory_prediction_time: float = 15.0  # How far into the future to predict (seconds)
@export var trajectory_points: int = 100  # Number of points to calculate for trajectory
@export var trajectory_color: Color = Color.YELLOW  # Bright yellow with some transparency

# Fuel system
@export var max_fuel: float = 1000.0  # Maximum fuel capacity (in delta-v units)
@export var fuel_consumption_rate: float = 50.0  # Fuel consumed per second of thrust
var current_fuel: float = 1000.0  # Current fuel level

var central_bodies: Array = []  # Array of all gravitational bodies
var orbit_trail: PackedVector2Array = []  # Stores positions along the orbit
var trail_update_counter: int = 0  # Counter to sample every N frames
var thrust_angle: float = 0.0  # Current thrust direction angle in degrees
var gravity_debug_printed: bool = false  # Flag to print gravity debug info only once
var predicted_trajectory: PackedVector2Array = []  # Stores predicted future positions

# Orbit stability tracking for win condition
var target_body: Node2D = null  # The target planet (Earth3)
var time_in_stable_orbit: float = 0.0  # Time spent in stable orbit
var orbit_distance_samples: Array[float] = []  # Recent distance samples for stability check
var last_orbit_angle: float = 0.0  # For tracking orbital progress
var total_orbit_angle: float = 0.0  # Total angle traveled around target
@export var stable_orbit_time_required: float = 10.0  # Seconds needed in stable orbit to win
@export var orbit_stability_threshold: float = 50.0  # Max distance variance for stable orbit

# Explosion state
var is_exploding: bool = false
var explosion_time: float = 0.0
@export var explosion_duration: float = 1.0  # How long the explosion lasts
@export var planet_collision_radius: float = 30.0  # Distance at which ship collides with planet

signal ship_exploded  # Signal emitted when ship explodes


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
			# Find Earth3 as the target planet
			if body.name == "Earth3":
				target_body = body
				print("      └─ ★ TARGET PLANET")
		print("Controls:")
		print("  Arrow keys LEFT/RIGHT - Rotate thrust direction")
		print("  Space - Apply thrust")
	
	if target_body != null:
		print("✓ Target planet set: %s" % target_body.name)
	else:
		print("WARNING: No target planet (Earth3) found!")


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
	# If exploding, only update explosion animation
	if is_exploding:
		update_explosion(delta)
		queue_redraw()
		return
	
	# Check for collision with planets
	check_planet_collision()
	
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
	
	# Check orbit stability for win condition
	check_orbit_stability(delta)
	
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
	
	# Apply thrust only when Space is pressed AND we have fuel
	var is_thrusting = Input.is_action_pressed("ui_select") and current_fuel > 0
	
	# Show/hide engine sprite based on thrust state
	if has_node("EngineAnimatedSprite"):
		get_node("EngineAnimatedSprite").visible = is_thrusting
	
	if is_thrusting:
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
		
		# Consume fuel
		var fuel_used = fuel_consumption_rate * delta
		current_fuel = max(0, current_fuel - fuel_used)
		
		# Apply thrust
		velocity += (thrust_direction * effective_thrust) * delta


func get_fuel_percentage() -> float:
	return (current_fuel / max_fuel) * 100.0


func check_orbit_stability(delta: float) -> void:
	# Check if we're in a stable orbit around the target planet (Earth3)
	if target_body == null:
		return
	
	var to_target = target_body.global_position - global_position
	var distance = to_target.length()
	var soi = calculate_sphere_of_influence()
	
	# Check if we're within the target's sphere of influence
	if distance > soi or distance < 50.0:  # Not in SOI or too close (crashed)
		# Reset orbit tracking
		time_in_stable_orbit = 0.0
		orbit_distance_samples.clear()
		total_orbit_angle = 0.0
		return
	
	# Track distance samples for stability check
	orbit_distance_samples.append(distance)
	if orbit_distance_samples.size() > 60:  # Keep last ~1 second of samples at 60fps
		orbit_distance_samples.remove_at(0)
	
	# Calculate orbit angle progress
	var current_angle = atan2(to_target.y, to_target.x)
	if orbit_distance_samples.size() > 1:
		var angle_diff = current_angle - last_orbit_angle
		# Handle angle wrapping
		if angle_diff > PI:
			angle_diff -= TAU
		elif angle_diff < -PI:
			angle_diff += TAU
		total_orbit_angle += abs(angle_diff)
	last_orbit_angle = current_angle
	
	# Check orbit stability (distance variance)
	if orbit_distance_samples.size() >= 30:
		var min_dist = orbit_distance_samples.min()
		var max_dist = orbit_distance_samples.max()
		var variance = max_dist - min_dist
		
		# Orbit is stable if variance is low and we've completed some angular distance
		if variance <= orbit_stability_threshold and total_orbit_angle > PI:  # At least half orbit
			time_in_stable_orbit += delta
		else:
			time_in_stable_orbit = max(0, time_in_stable_orbit - delta * 0.5)  # Decay slowly


func is_in_stable_orbit() -> bool:
	return time_in_stable_orbit >= stable_orbit_time_required


func get_orbit_progress() -> float:
	# Returns 0.0 to 1.0 progress toward stable orbit
	return min(time_in_stable_orbit / stable_orbit_time_required, 1.0)


func reset_orbit_tracking() -> void:
	time_in_stable_orbit = 0.0
	orbit_distance_samples.clear()
	total_orbit_angle = 0.0
	last_orbit_angle = 0.0


func check_planet_collision() -> void:
	# Check if ship has collided with any planet
	# Check both ship center and ship head (front of ship based on rotation)
	
	# The ship sprite points UP (-Y in local space) by default
	# The collision shape is 20x61 pixels, centered at (1, -14.5) in local coords
	# Ship head is approximately 45 pixels from center in the "up" direction (local -Y)
	var ship_head_offset = 45.0  # Distance from center to head
	
	# The ship's local "up" direction (-Y) in world space
	# rotation is already set, so we use Transform2D to get the correct direction
	var local_up = Vector2(0, -1)  # Local "up" is -Y
	var world_up = local_up.rotated(rotation)
	var head_position = global_position + world_up * ship_head_offset
	
	for body in central_bodies:
		if body == null:
			continue
		
		# Get planet's collision radius (use sprite size or default)
		var planet_radius = planet_collision_radius
		if body.has_node("Sprite2D"):
			var sprite = body.get_node("Sprite2D")
			if sprite.texture:
				planet_radius = max(sprite.texture.get_width(), sprite.texture.get_height()) * sprite.scale.x / 2.0
		
		# Check collision with ship center
		var distance_center = (body.global_position - global_position).length()
		if distance_center < (body_radius + planet_radius):
			trigger_explosion(body)
			return
		
		# Check collision with ship head
		var distance_head = (body.global_position - head_position).length()
		if distance_head < planet_radius:
			trigger_explosion(body)
			return


func trigger_explosion(collided_planet: Node2D) -> void:
	# Start explosion sequence
	is_exploding = true
	explosion_time = 0.0
	velocity = Vector2.ZERO
	
	# Hide engine sprite during explosion
	if has_node("EngineAnimatedSprite"):
		get_node("EngineAnimatedSprite").visible = false
	
	# Play explosion animation on AnimatedSprite2D
	if has_node("AnimatedSprite2D"):
		var animated_sprite = get_node("AnimatedSprite2D")
		animated_sprite.position = Vector2.ZERO  # Center the explosion on the ship
		animated_sprite.offset = Vector2.ZERO  # Reset offset
		animated_sprite.play("exploding")
		animated_sprite.visible = true
	
	print("💥 Ship exploded on collision with %s!" % collided_planet.name)
	emit_signal("ship_exploded")


func update_explosion(delta: float) -> void:
	explosion_time += delta


func is_ship_exploded() -> bool:
	return is_exploding and explosion_time >= explosion_duration


func reset_explosion() -> void:
	is_exploding = false
	explosion_time = 0.0
	
	# Reset AnimatedSprite2D to default ship animation
	if has_node("AnimatedSprite2D"):
		var animated_sprite = get_node("AnimatedSprite2D")
		animated_sprite.stop()
		animated_sprite.play("default")
		animated_sprite.visible = true


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
		
		# Check for collision with planets - stop trajectory if it would hit
		var collision_detected = false
		for body in central_bodies:
			if body == null:
				continue
			
			# Get planet's collision radius
			var planet_radius = planet_collision_radius
			if body.has_node("Sprite2D"):
				var sprite = body.get_node("Sprite2D")
				if sprite.texture:
					planet_radius = max(sprite.texture.get_width(), sprite.texture.get_height()) * sprite.scale.x / 2.0
			
			var distance_to_planet = (body.global_position - sim_pos).length()
			if distance_to_planet < (body_radius + planet_radius):
				# Trajectory would hit this planet - add final point and stop
				predicted_trajectory.append(sim_pos)
				collision_detected = true
				break
		
		if collision_detected:
			break
		
		# Handle boundary bounces in simulation
		if sim_pos.x < boundary_left + body_radius:
			sim_pos.x = boundary_left + body_radius
			sim_vel.x = abs(sim_vel.x) * bounce_coefficient
		elif sim_pos.x > boundary_right - body_radius:
			sim_pos.x = boundary_right - body_radius
			sim_vel.x = -abs(sim_vel.x) * bounce_coefficient
		
		if sim_pos.y < boundary_top + body_radius:
			sim_pos.y = boundary_top + body_radius
			sim_vel.y = abs(sim_vel.y) * bounce_coefficient
		elif sim_pos.y > boundary_bottom - body_radius:
			sim_pos.y = boundary_bottom - body_radius
			sim_vel.y = -abs(sim_vel.y) * bounce_coefficient
		
		# Store predicted position
		predicted_trajectory.append(sim_pos)


func handle_screen_bounce() -> void:
	# Check left and right boundaries
	if global_position.x - body_radius < boundary_left:
		global_position.x = boundary_left + body_radius
		velocity.x = abs(velocity.x) * bounce_coefficient
		print("Bounced off left wall")
	elif global_position.x + body_radius > boundary_right:
		global_position.x = boundary_right - body_radius
		velocity.x = -abs(velocity.x) * bounce_coefficient
		print("Bounced off right wall")
	
	# Check top and bottom boundaries
	if global_position.y - body_radius < boundary_top:
		global_position.y = boundary_top + body_radius
		velocity.y = abs(velocity.y) * bounce_coefficient
		print("Bounced off top wall")
	elif global_position.y + body_radius > boundary_bottom:
		global_position.y = boundary_bottom - body_radius
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

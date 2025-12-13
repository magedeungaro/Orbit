extends CharacterBody2D

## Debug Settings
@export_group("Debug")
@export var debug_infinite_fuel: bool = false  ## Enable for testing without fuel limits

## Level Design Settings
@export_group("Level Design")
@export var initial_velocity: Vector2 = Vector2.ZERO  ## Starting velocity (use to set up initial orbits)
@export var thrust_force: float = 300.0
@export var max_fuel: float = 1000.0
@export var stable_orbit_time_required: float = 10.0
@export_range(0.0, 1.0, 0.05) var parent_gravity_attenuation: float = 0.05  ## How much parent body gravity affects ship inside child SOI (0=none, 1=full)

@export_group("Boundaries")
@export var boundary_left: float = -5000.0
@export var boundary_top: float = -5000.0
@export var boundary_right: float = 25000.0
@export var boundary_bottom: float = 25000.0

## Internal Physics Settings (not exposed to editor)
var gravitational_constant: float = 500000.0
var soi_multiplier: float = 50.0  ## Multiplier for SOI calculation: SOI = multiplier * sqrt(G * mass)
var proximity_gravity_boost: float = 3.0
var proximity_threshold: float = 150.0
var mass: float = 50.0
var bounce_coefficient: float = 0.8
var body_radius: float = 39.0
var thrust_angle_rotation_speed: float = 180.0
var fuel_consumption_rate: float = 50.0
var orbit_stability_threshold: float = 50.0
var explosion_duration: float = 1.0
var planet_collision_radius: float = 30.0

## Visualization Settings (internal)
var show_sphere_of_influence: bool = true
var show_orbit_trail: bool = true
var orbit_trail_color: Color = Color.MAGENTA
var trail_max_points: int = 500
var show_trajectory: bool = true
var trajectory_prediction_time: float = 60.0  ## Max prediction time (seconds)
var trajectory_points: int = 300  ## Max trajectory points
var trajectory_color: Color = Color.YELLOW
var trajectory_update_interval: float = 0.1  ## Seconds between trajectory recalculations

var current_fuel: float = 1000.0
var central_bodies: Array = []
var orbit_trail: PackedVector2Array = []
var trail_update_counter: int = 0
var thrust_angle: float = 0.0
var predicted_trajectory: PackedVector2Array = []
var target_body: Node2D = null
var time_in_stable_orbit: float = 0.0
var orbit_distance_samples: Array[float] = []
var last_orbit_angle: float = 0.0
var total_orbit_angle: float = 0.0
var is_exploding: bool = false
var explosion_time: float = 0.0

# Trajectory caching (legacy - kept for escape trajectory fallback)
var _trajectory_timer: float = 0.0
var _last_trajectory_pos: Vector2 = Vector2.ZERO
var _last_trajectory_vel: Vector2 = Vector2.ZERO
var _trajectory_needs_update: bool = true
var _trajectory_reference_positions: PackedVector2Array = []
var _trajectory_reference_body: Node2D = null

# Analytical orbit visualization
# Cached orbital elements - only updated when thrust applied or SOI changes
var _cached_orbital_elements: Dictionary = {}
var _cached_orbit_ref_body: Node2D = null
var _is_thrusting: bool = false
var _was_thrusting: bool = false
var _orbit_needs_recalc: bool = true

# N-body trajectory prediction (shows perturbations)
var _nbody_trajectory: PackedVector2Array = []
var _nbody_trajectory_color: Color = Color(0.5, 0.8, 1.0, 0.5)  # Light blue for n-body

enum OrientationLock { NONE, PROGRADE, RETROGRADE }
var orientation_lock: OrientationLock = OrientationLock.NONE

signal ship_exploded
signal orientation_lock_changed(lock_type: int)


func _ready() -> void:
	current_fuel = max_fuel
	velocity = initial_velocity  # Apply initial velocity for orbital setup
	var root = get_tree().root
	central_bodies = _find_all_nodes_with_script(root, "central_body")
	
	if central_bodies.is_empty():
		central_bodies = _find_all_nodes_by_name(root, "Earth")
	
	for body in central_bodies:
		if body.name == "Earth3":
			target_body = body
			break


func _find_all_nodes_with_script(node: Node, script_name: String) -> Array:
	var result: Array = []
	if node.get_script() != null:
		var script_filename = node.get_script().resource_path.get_file().trim_suffix(".gd")
		if script_filename == script_name:
			result.append(node)
	for child in node.get_children():
		result.append_array(_find_all_nodes_with_script(child, script_name))
	return result


func _find_all_nodes_by_name(node: Node, node_name: String) -> Array:
	var result: Array = []
	if node.name == node_name:
		result.append(node)
	for child in node.get_children():
		result.append_array(_find_all_nodes_by_name(child, node_name))
	return result


func _physics_process(delta: float) -> void:
	if is_exploding:
		update_explosion(delta)
		queue_redraw()
		return
	
	# Track SOI changes to trigger orbit recalculation
	var current_dominant_body = _find_dominant_gravity_body()
	if current_dominant_body != _cached_orbit_ref_body:
		_orbit_needs_recalc = true
	
	# Planet collision is now handled by Area2D trigger detection
	handle_thrust_input(delta)
	apply_gravity_from_all_bodies(delta)
	rotation = deg_to_rad(thrust_angle - 90)
	move_and_slide()
	handle_screen_bounce()
	update_orbit_trail()
	# Disabled: _update_trajectory_smart(delta) - replaced with direct orbital calculation
	check_orbit_stability(delta)
	queue_redraw()


func handle_thrust_input(delta: float) -> void:
	if Input.is_action_just_pressed("toggle_prograde"):
		toggle_prograde_lock()
	if Input.is_action_just_pressed("toggle_retrograde"):
		toggle_retrograde_lock()
	
	# Gamepad toggle orientation: cycles None -> Prograde -> Retrograde -> None
	if Input.is_action_just_pressed("toggle_orientation"):
		match orientation_lock:
			OrientationLock.NONE:
				toggle_prograde_lock()
			OrientationLock.PROGRADE:
				orientation_lock = OrientationLock.RETROGRADE
				orientation_lock_changed.emit(orientation_lock)
			OrientationLock.RETROGRADE:
				orientation_lock = OrientationLock.NONE
				orientation_lock_changed.emit(orientation_lock)
	
	var is_manually_rotating = Input.is_action_pressed("ui_left") or Input.is_action_pressed("rotate_left") or Input.is_action_pressed("ui_right") or Input.is_action_pressed("rotate_right")
	if is_manually_rotating and orientation_lock != OrientationLock.NONE:
		orientation_lock = OrientationLock.NONE
		orientation_lock_changed.emit(orientation_lock)
	
	if orientation_lock != OrientationLock.NONE:
		update_orientation_lock()
	else:
		if Input.is_action_pressed("ui_left") or Input.is_action_pressed("rotate_left"):
			thrust_angle -= thrust_angle_rotation_speed * delta
		if Input.is_action_pressed("ui_right") or Input.is_action_pressed("rotate_right"):
			thrust_angle += thrust_angle_rotation_speed * delta
	
	while thrust_angle < 0:
		thrust_angle += 360
	while thrust_angle >= 360:
		thrust_angle -= 360
	
	var has_fuel = current_fuel > 0 or debug_infinite_fuel
	_is_thrusting = Input.is_action_pressed("thrust") and has_fuel and not is_exploding
	
	if has_node("EngineAnimatedSprite"):
		get_node("EngineAnimatedSprite").visible = _is_thrusting
	
	if _is_thrusting:
		var thrust_angle_rad = deg_to_rad(thrust_angle)
		var thrust_direction = Vector2(-cos(thrust_angle_rad), -sin(thrust_angle_rad))
		if not debug_infinite_fuel:
			current_fuel = max(0, current_fuel - fuel_consumption_rate * delta)
		velocity += (thrust_direction * thrust_force) * delta


func get_fuel_percentage() -> float:
	return (current_fuel / max_fuel) * 100.0


func check_orbit_stability(delta: float) -> void:
	if target_body == null:
		return
	
	var to_target = target_body.global_position - global_position
	var distance = to_target.length()
	var soi = calculate_sphere_of_influence()
	
	if distance > soi or distance < 50.0:
		time_in_stable_orbit = 0.0
		orbit_distance_samples.clear()
		total_orbit_angle = 0.0
		return
	
	orbit_distance_samples.append(distance)
	if orbit_distance_samples.size() > 60:
		orbit_distance_samples.remove_at(0)
	
	var current_angle = atan2(to_target.y, to_target.x)
	if orbit_distance_samples.size() > 1:
		var angle_diff = current_angle - last_orbit_angle
		if angle_diff > PI:
			angle_diff -= TAU
		elif angle_diff < -PI:
			angle_diff += TAU
		total_orbit_angle += abs(angle_diff)
	last_orbit_angle = current_angle
	
	if orbit_distance_samples.size() >= 30:
		var min_dist = orbit_distance_samples.min()
		var max_dist = orbit_distance_samples.max()
		var variance = max_dist - min_dist
		
		if variance <= orbit_stability_threshold and total_orbit_angle > PI:
			time_in_stable_orbit += delta
		else:
			time_in_stable_orbit = max(0, time_in_stable_orbit - delta * 0.5)


func is_in_stable_orbit() -> bool:
	return time_in_stable_orbit >= stable_orbit_time_required


func get_orbit_progress() -> float:
	return min(time_in_stable_orbit / stable_orbit_time_required, 1.0)


func check_planet_collision() -> void:
	# Planet collision is now handled by Area2D trigger detection in central_body.gd
	# When the ship's collision shape overlaps a planet's Area2D, 
	# the planet calls trigger_explosion() on the ship
	pass


func trigger_explosion(_collided_planet: Node2D) -> void:
	is_exploding = true
	explosion_time = 0.0
	velocity = Vector2.ZERO
	
	if has_node("EngineAnimatedSprite"):
		get_node("EngineAnimatedSprite").visible = false
	
	if has_node("AnimatedSprite2D"):
		var animated_sprite = get_node("AnimatedSprite2D")
		animated_sprite.position = Vector2.ZERO
		animated_sprite.offset = Vector2.ZERO
		animated_sprite.play("exploding")
		animated_sprite.visible = true
	
	ship_exploded.emit()
	
	if Events:
		Events.ship_exploded.emit()


func update_explosion(delta: float) -> void:
	explosion_time += delta


func is_ship_exploded() -> bool:
	return is_exploding and explosion_time >= explosion_duration


func reset_explosion() -> void:
	is_exploding = false
	explosion_time = 0.0
	
	if has_node("AnimatedSprite2D"):
		var animated_sprite = get_node("AnimatedSprite2D")
		animated_sprite.stop()
		animated_sprite.play("default")
		animated_sprite.visible = true


## Calculate sphere of influence for a planet based on its mass
## SOI scales with sqrt(G * mass) - this reflects how gravity falls off with 1/r²
## At distance r where gravitational force equals a threshold, r ∝ sqrt(mass)
func calculate_sphere_of_influence_for_body(planet_mass: float) -> float:
	return soi_multiplier * sqrt(gravitational_constant * planet_mass / 10000.0)


## Legacy function - returns a default SOI for backwards compatibility
func calculate_sphere_of_influence() -> float:
	# Use a reference mass of 20 for default SOI
	return calculate_sphere_of_influence_for_body(20.0)


## Find which planet's SOI the ship is currently inside (excluding root/static bodies)
## Returns the innermost (smallest) SOI if nested, prioritizing orbiting bodies
func _find_current_soi_body() -> Node2D:
	var current_soi_body: Node2D = null
	var smallest_soi: float = INF
	
	for body in central_bodies:
		if body == null:
			continue
		
		# Skip static bodies (like the Sun) - we want to find orbiting planets' SOIs
		if "is_static" in body and body.is_static:
			continue
		if not ("orbits_around" in body) or body.orbits_around == null:
			continue
		
		var direction_to_body = body.global_position - global_position
		var distance = direction_to_body.length()
		var soi = calculate_sphere_of_influence_for_body(body.mass)
		
		# If inside this body's SOI and it's smaller than current best, use it
		if distance <= soi and soi < smallest_soi:
			smallest_soi = soi
			current_soi_body = body
	
	return current_soi_body


func apply_gravity_from_all_bodies(delta: float) -> void:
	# Implements "patched conic approximation" - true two-body problem
	# When inside a planet's SOI, ONLY that planet's gravity affects the ship
	# Parent bodies (like the Sun) are completely ignored
	var soi_body = _find_current_soi_body()
	
	# Build list of bodies to completely ignore (parent bodies when inside child's SOI)
	var ignored_bodies: Array = []
	if soi_body != null and "orbits_around" in soi_body and soi_body.orbits_around != null:
		ignored_bodies.append(soi_body.orbits_around)
		# Also ignore grandparent if exists (for moons orbiting planets orbiting sun)
		if "orbits_around" in soi_body.orbits_around and soi_body.orbits_around.orbits_around != null:
			ignored_bodies.append(soi_body.orbits_around.orbits_around)
	
	# When inside a moving planet's SOI, make the ship "ride along" with the planet
	# by applying the same acceleration the planet experiences from its parent
	# This creates a true two-body problem in the planet's reference frame
	if soi_body != null and "orbits_around" in soi_body and soi_body.orbits_around != null:
		var parent_body = soi_body.orbits_around
		var dir_to_parent = parent_body.global_position - soi_body.global_position
		var dist_to_parent = dir_to_parent.length()
		if dist_to_parent > 1.0:
			var parent_g_const = soi_body.orbital_gravitational_constant if "orbital_gravitational_constant" in soi_body else gravitational_constant
			var parent_accel = (parent_g_const * parent_body.mass) / (dist_to_parent * dist_to_parent)
			# Apply same acceleration to ship that planet experiences
			velocity += dir_to_parent.normalized() * parent_accel * delta
	
	for body in central_bodies:
		if body == null:
			continue
		
		# Skip parent bodies entirely when inside a child's SOI (two-body problem)
		if body in ignored_bodies:
			continue
		
		var direction_to_center = body.global_position - global_position
		var distance = direction_to_center.length()
		
		# Calculate SOI based on this specific planet's mass
		var soi = calculate_sphere_of_influence_for_body(body.mass)
		
		if distance > 1.0 and distance <= soi:
			var gravitational_acceleration = (gravitational_constant * body.mass) / (distance * distance)
			
			if distance < proximity_threshold:
				var proximity_factor = 1.0 - (distance / proximity_threshold)
				var boost = 1.0 + (proximity_gravity_boost - 1.0) * proximity_factor
				gravitational_acceleration *= boost
			
			velocity += direction_to_center.normalized() * gravitational_acceleration * delta


## Smart trajectory update - only recalculates when needed
func _update_trajectory_smart(delta: float) -> void:
	if not show_trajectory:
		predicted_trajectory.clear()
		return
	
	_trajectory_timer += delta
	
	# Only recalculate when velocity changes significantly (thrust applied or SOI transition)
	# Position changes constantly during orbit, but velocity should stay stable
	var vel_changed = (velocity - _last_trajectory_vel).length() > 2.0
	var timer_expired = _trajectory_timer >= trajectory_update_interval
	
	# Also check if reference body changed (SOI transition)
	var ref_body_changed = false
	var current_soi_body = _find_current_soi_body()
	if current_soi_body != _trajectory_reference_body:
		ref_body_changed = true
	
	if _trajectory_needs_update or vel_changed or ref_body_changed:
		calculate_trajectory()
		_last_trajectory_pos = global_position
		_last_trajectory_vel = velocity
		_trajectory_timer = 0.0
		_trajectory_needs_update = false


## Force trajectory recalculation on next frame
func invalidate_trajectory() -> void:
	_trajectory_needs_update = true


func calculate_trajectory() -> void:
	predicted_trajectory.clear()
	_trajectory_reference_positions.clear()
	_trajectory_reference_body = null
	_cached_orbital_elements.clear()
	
	if not show_trajectory:
		return
	
	var sim_pos = global_position
	var sim_vel = velocity
	var time_step = trajectory_prediction_time / trajectory_points
	
	# Find the current dominant SOI body for reference frame
	_trajectory_reference_body = _find_current_soi_body()
	
	# Calculate and cache orbital elements for ellipse drawing
	if _trajectory_reference_body != null:
		var ref_pos = _trajectory_reference_body.global_position
		var ref_mass = _trajectory_reference_body.mass
		_cached_orbital_elements = _calculate_orbital_elements(ref_pos, ref_mass)
	
	# Pre-cache planet data for performance (avoid repeated property access)
	var planet_data: Array = []
	for body in central_bodies:
		if body == null:
			continue
		var data = {
			"pos": body.global_position,
			"mass": body.mass,
			"soi": calculate_sphere_of_influence_for_body(body.mass),
			"radius": _get_planet_collision_radius(body),
			"is_static": body.is_static if "is_static" in body else true,
			"vel": body.velocity if "velocity" in body and not (body.is_static if "is_static" in body else true) else Vector2.ZERO,
			"orbits_around_idx": -1,
			"g_const": body.orbital_gravitational_constant if "orbital_gravitational_constant" in body else gravitational_constant,
			"body_ref": body
		}
		# Find parent index for orbiting planets
		if "orbits_around" in body and body.orbits_around != null:
			for j in range(central_bodies.size()):
				if central_bodies[j] == body.orbits_around:
					data["orbits_around_idx"] = j
					break
		planet_data.append(data)
	
	# Find the index of the reference body in planet_data
	var ref_body_idx: int = -1
	if _trajectory_reference_body != null:
		for j in range(planet_data.size()):
			if planet_data[j]["body_ref"] == _trajectory_reference_body:
				ref_body_idx = j
				break
	
	# Store initial reference position
	if ref_body_idx >= 0:
		_trajectory_reference_positions.append(planet_data[ref_body_idx]["pos"])
	else:
		_trajectory_reference_positions.append(Vector2.ZERO)
	
	predicted_trajectory.append(sim_pos)
	
	for i in range(trajectory_points):
		# Update moving planet positions (simplified Euler for planets)
		for j in range(planet_data.size()):
			var pd = planet_data[j]
			if pd["is_static"]:
				continue
			
			# Apply gravity from parent
			var parent_idx = pd["orbits_around_idx"]
			if parent_idx >= 0 and parent_idx < planet_data.size():
				var parent_pos = planet_data[parent_idx]["pos"]
				var dir_to_parent = parent_pos - pd["pos"]
				var dist = dir_to_parent.length()
				if dist > 1.0:
					var parent_mass = planet_data[parent_idx]["mass"]
					var g_acc = (pd["g_const"] * parent_mass) / (dist * dist)
					pd["vel"] += dir_to_parent.normalized() * g_acc * time_step
			
			pd["pos"] += pd["vel"] * time_step
		
		# Find which SOI the simulated ship position is inside (for patched conic approximation)
		var sim_soi_idx: int = -1
		var smallest_soi: float = INF
		for j in range(planet_data.size()):
			var pd = planet_data[j]
			if pd["is_static"] or pd["orbits_around_idx"] < 0:
				continue
			var dist_to_body = (pd["pos"] - sim_pos).length()
			if dist_to_body <= pd["soi"] and pd["soi"] < smallest_soi:
				smallest_soi = pd["soi"]
				sim_soi_idx = j
		
		# Build list of ignored parent indices (two-body problem)
		var attenuated_indices: Array = []
		if sim_soi_idx >= 0:
			var parent_idx = planet_data[sim_soi_idx]["orbits_around_idx"]
			if parent_idx >= 0:
				attenuated_indices.append(parent_idx)
				# Also check grandparent
				var grandparent_idx = planet_data[parent_idx]["orbits_around_idx"]
				if grandparent_idx >= 0:
					attenuated_indices.append(grandparent_idx)
		
		# Apply gravity to ship (simple Euler - fast)
		var total_accel = Vector2.ZERO
		for j in range(planet_data.size()):
			var pd = planet_data[j]
			
			# Skip parent bodies entirely when inside a child's SOI (two-body problem)
			if j in attenuated_indices:
				continue
			
			var dir_to_body = pd["pos"] - sim_pos
			var dist = dir_to_body.length()
			
			if dist > 1.0 and dist <= pd["soi"]:
				var g_acc = (gravitational_constant * pd["mass"]) / (dist * dist)
				
				if dist < proximity_threshold:
					var prox_factor = 1.0 - (dist / proximity_threshold)
					g_acc *= 1.0 + (proximity_gravity_boost - 1.0) * prox_factor
				
				total_accel += dir_to_body.normalized() * g_acc
		
		sim_vel += total_accel * time_step
		sim_pos += sim_vel * time_step
		
		# Check collision (simplified)
		var collision = false
		for pd in planet_data:
			if (pd["pos"] - sim_pos).length() < (body_radius + pd["radius"]):
				collision = true
				break
		
		if collision:
			predicted_trajectory.append(sim_pos)
			break
		
		# Simple boundary check
		sim_pos.x = clamp(sim_pos.x, boundary_left + body_radius, boundary_right - body_radius)
		sim_pos.y = clamp(sim_pos.y, boundary_top + body_radius, boundary_bottom - body_radius)
		
		predicted_trajectory.append(sim_pos)
		
		# Store reference body position for this trajectory point
		if ref_body_idx >= 0:
			_trajectory_reference_positions.append(planet_data[ref_body_idx]["pos"])
		else:
			_trajectory_reference_positions.append(Vector2.ZERO)


## Get collision radius for a planet
func _get_planet_collision_radius(body: Node2D) -> float:
	var radius = planet_collision_radius
	if body.has_node("Sprite2D"):
		var sprite = body.get_node("Sprite2D")
		if sprite.texture:
			radius = max(sprite.texture.get_width(), sprite.texture.get_height()) * sprite.scale.x / 2.0
	return radius


func handle_screen_bounce() -> void:
	if global_position.x - body_radius < boundary_left:
		global_position.x = boundary_left + body_radius
		velocity.x = abs(velocity.x) * bounce_coefficient
	elif global_position.x + body_radius > boundary_right:
		global_position.x = boundary_right - body_radius
		velocity.x = -abs(velocity.x) * bounce_coefficient
	
	if global_position.y - body_radius < boundary_top:
		global_position.y = boundary_top + body_radius
		velocity.y = abs(velocity.y) * bounce_coefficient
	elif global_position.y + body_radius > boundary_bottom:
		global_position.y = boundary_bottom - body_radius
		velocity.y = -abs(velocity.y) * bounce_coefficient


func update_orbit_trail() -> void:
	trail_update_counter += 1
	
	if trail_update_counter >= 2:
		trail_update_counter = 0
		orbit_trail.append(global_position)
		
		if orbit_trail.size() > trail_max_points:
			orbit_trail.remove_at(0)


func _draw() -> void:
	if not show_trajectory:
		return
	
	# Find current dominant body for orbit visualization
	# This includes static bodies (like the Sun) unlike _find_current_soi_body()
	var current_ref_body = _find_dominant_gravity_body()
	
	# Detect if we need to recalculate orbit
	# Recalc when: thrust just stopped, SOI changed, or first calculation
	var thrust_just_stopped = _was_thrusting and not _is_thrusting
	var soi_changed = current_ref_body != _cached_orbit_ref_body
	
	if _orbit_needs_recalc or thrust_just_stopped or soi_changed:
		_cached_orbit_ref_body = current_ref_body
		if current_ref_body != null:
			_cached_orbital_elements = _calculate_orbital_elements(
				current_ref_body.global_position, 
				current_ref_body.mass
			)
		else:
			_cached_orbital_elements.clear()
		
		# Also recalculate n-body trajectory
		_calculate_nbody_trajectory()
		_orbit_needs_recalc = false
	
	# Update thrust tracking for next frame
	_was_thrusting = _is_thrusting
	
	# If currently thrusting, show real-time orbit preview (recalculates each frame)
	var elements_to_draw = _cached_orbital_elements
	if _is_thrusting and current_ref_body != null:
		elements_to_draw = _calculate_orbital_elements(
			current_ref_body.global_position,
			current_ref_body.mass
		)
		# Also update n-body trajectory while thrusting
		_calculate_nbody_trajectory()
	
	# Draw the two-body orbit (yellow ellipse)
	if not elements_to_draw.is_empty() and current_ref_body != null:
		var max_eccentricity_for_ellipse: float = 0.98
		if elements_to_draw["eccentricity"] < max_eccentricity_for_ellipse:
			_draw_trajectory_ellipse(elements_to_draw, current_ref_body.global_position)
		else:
			# Escape trajectory - draw a partial arc or line
			_draw_escape_trajectory(elements_to_draw, current_ref_body)
	
	# Draw n-body trajectory overlay (shows perturbations from other bodies)
	_draw_nbody_trajectory()


## Calculate n-body trajectory using numerical integration
## This shows how other gravitational bodies will perturb the orbit
func _calculate_nbody_trajectory() -> void:
	_nbody_trajectory.clear()
	
	if central_bodies.is_empty():
		return
	
	var sim_pos = global_position
	var sim_vel = velocity
	var time_step = trajectory_prediction_time / trajectory_points
	
	# Pre-cache planet data
	var planet_data: Array = []
	for body in central_bodies:
		if body == null:
			continue
		var data = {
			"pos": body.global_position,
			"mass": body.mass,
			"soi": calculate_sphere_of_influence_for_body(body.mass),
			"radius": _get_planet_collision_radius(body),
			"is_static": body.is_static if "is_static" in body else true,
			"vel": body.velocity if "velocity" in body and not (body.is_static if "is_static" in body else true) else Vector2.ZERO,
			"orbits_around_idx": -1,
			"g_const": body.orbital_gravitational_constant if "orbital_gravitational_constant" in body else gravitational_constant
		}
		if "orbits_around" in body and body.orbits_around != null:
			for j in range(central_bodies.size()):
				if central_bodies[j] == body.orbits_around:
					data["orbits_around_idx"] = j
					break
		planet_data.append(data)
	
	_nbody_trajectory.append(sim_pos)
	
	for i in range(trajectory_points):
		# Update moving planet positions (same as actual physics)
		for j in range(planet_data.size()):
			var pd = planet_data[j]
			if pd["is_static"]:
				continue
			var parent_idx = pd["orbits_around_idx"]
			if parent_idx >= 0 and parent_idx < planet_data.size():
				var parent_pos = planet_data[parent_idx]["pos"]
				var dir_to_parent = parent_pos - pd["pos"]
				var dist = dir_to_parent.length()
				if dist > 1.0:
					var parent_mass = planet_data[parent_idx]["mass"]
					var g_acc = (pd["g_const"] * parent_mass) / (dist * dist)
					pd["vel"] += dir_to_parent.normalized() * g_acc * time_step
			pd["pos"] += pd["vel"] * time_step
		
		# Find which SOI the simulated ship is inside (patched conic approximation)
		# This matches the actual ship physics in apply_gravity_from_all_bodies()
		var sim_soi_idx: int = -1
		var smallest_soi: float = INF
		for j in range(planet_data.size()):
			var pd = planet_data[j]
			# Only consider non-static bodies that orbit something (like the actual ship does)
			if pd["is_static"] or pd["orbits_around_idx"] < 0:
				continue
			var dist_to_body = (pd["pos"] - sim_pos).length()
			if dist_to_body <= pd["soi"] and pd["soi"] < smallest_soi:
				smallest_soi = pd["soi"]
				sim_soi_idx = j
		
		# Build list of ignored parent indices (matches ship's patched conic logic)
		var ignored_indices: Array = []
		if sim_soi_idx >= 0:
			var parent_idx = planet_data[sim_soi_idx]["orbits_around_idx"]
			if parent_idx >= 0:
				ignored_indices.append(parent_idx)
				# Also ignore grandparent
				var grandparent_idx = planet_data[parent_idx]["orbits_around_idx"]
				if grandparent_idx >= 0:
					ignored_indices.append(grandparent_idx)
		
		# When inside a moving planet's SOI, apply the same acceleration the planet gets
		# This makes the ship "ride along" with the planet (reference frame matching)
		if sim_soi_idx >= 0:
			var parent_idx = planet_data[sim_soi_idx]["orbits_around_idx"]
			if parent_idx >= 0:
				var soi_pd = planet_data[sim_soi_idx]
				var parent_pd = planet_data[parent_idx]
				var dir_to_parent = parent_pd["pos"] - soi_pd["pos"]
				var dist_to_parent = dir_to_parent.length()
				if dist_to_parent > 1.0:
					var parent_accel = (soi_pd["g_const"] * parent_pd["mass"]) / (dist_to_parent * dist_to_parent)
					sim_vel += dir_to_parent.normalized() * parent_accel * time_step
		
		# Apply gravity using same patched conic rules as actual ship
		var total_accel = Vector2.ZERO
		for j in range(planet_data.size()):
			var pd = planet_data[j]
			
			# Skip parent bodies when inside child's SOI (patched conics)
			if j in ignored_indices:
				continue
			
			var dir_to_body = pd["pos"] - sim_pos
			var dist = dir_to_body.length()
			
			# Only apply gravity if within this body's SOI
			if dist > 1.0 and dist <= pd["soi"]:
				var g_acc = (gravitational_constant * pd["mass"]) / (dist * dist)
				total_accel += dir_to_body.normalized() * g_acc
		
		sim_vel += total_accel * time_step
		sim_pos += sim_vel * time_step
		
		# Check collision
		var collision = false
		for pd in planet_data:
			if (pd["pos"] - sim_pos).length() < (body_radius + pd["radius"]):
				collision = true
				break
		
		if collision:
			_nbody_trajectory.append(sim_pos)
			break
		
		# Boundary check
		if sim_pos.x < boundary_left or sim_pos.x > boundary_right or sim_pos.y < boundary_top or sim_pos.y > boundary_bottom:
			break
		
		_nbody_trajectory.append(sim_pos)


## Draw the n-body trajectory as a dashed/different colored line
func _draw_nbody_trajectory() -> void:
	if _nbody_trajectory.size() < 2:
		return
	
	# Only draw if there are multiple gravitational bodies (otherwise it's same as ellipse)
	if central_bodies.size() < 2:
		return
	
	var point_count = _nbody_trajectory.size()
	
	# Draw as dashed line to distinguish from the ellipse
	for i in range(point_count - 1):
		# Skip every other segment to create dashed effect
		if i % 3 == 0:
			continue
		
		var start_local = to_local(_nbody_trajectory[i])
		var end_local = to_local(_nbody_trajectory[i + 1])
		
		# Fade based on distance along trajectory
		var t = float(i) / float(point_count)
		var alpha = 0.6 - t * 0.4
		var color = Color(_nbody_trajectory_color.r, _nbody_trajectory_color.g, _nbody_trajectory_color.b, alpha)
		
		draw_line(start_local, end_local, color, 1.5)


## Find the dominant gravity body for orbit visualization
## Unlike _find_current_soi_body(), this includes static bodies like the Sun
func _find_dominant_gravity_body() -> Node2D:
	# First check if we're inside any orbiting planet's SOI
	var soi_body = _find_current_soi_body()
	if soi_body != null:
		return soi_body
	
	# Otherwise, find the body exerting the strongest gravitational pull
	var best_body: Node2D = null
	var strongest_gravity: float = 0.0
	
	for body in central_bodies:
		if body == null:
			continue
		
		var distance = (body.global_position - global_position).length()
		if distance < 1.0:
			continue
		
		# Calculate gravitational acceleration from this body
		var gravity = gravitational_constant * body.mass / (distance * distance)
		
		if gravity > strongest_gravity:
			strongest_gravity = gravity
			best_body = body
	
	return best_body


## Calculate orbital elements from current position and velocity relative to reference body
func _calculate_orbital_elements(ref_pos: Vector2, ref_mass: float) -> Dictionary:
	# Get position and velocity relative to reference body
	var r_vec = global_position - ref_pos
	var v_vec = velocity
	
	# If reference body is moving, subtract its velocity
	if _cached_orbit_ref_body != null and "velocity" in _cached_orbit_ref_body:
		v_vec = velocity - _cached_orbit_ref_body.velocity
	
	var r = r_vec.length()
	var v = v_vec.length()
	
	if r < 1.0:
		return {}  # Too close, invalid orbit
	
	var mu = gravitational_constant * ref_mass  # Standard gravitational parameter
	
	# Specific orbital energy: E = v²/2 - μ/r
	var energy = (v * v / 2.0) - (mu / r)
	
	# Semi-major axis: a = -μ/(2E)
	# Negative energy = bound orbit (positive semi-major)
	# Positive energy = hyperbolic (negative semi-major)
	var semi_major: float
	if abs(energy) > 0.001:
		semi_major = -mu / (2.0 * energy)
	else:
		return {}  # Parabolic - can't draw as ellipse
	
	# Angular momentum (scalar in 2D): h = r × v (z-component)
	var h = r_vec.x * v_vec.y - r_vec.y * v_vec.x
	
	# Eccentricity vector: e = (v × h)/μ - r/|r|
	# In 2D, v × h (where h is scalar z-component):
	# v × (0,0,h) = (vy*h, -vx*h) = h * Vector2(vy, -vx)
	var v_cross_h = Vector2(v_vec.y, -v_vec.x) * h
	var e_vec = (v_cross_h / mu) - (r_vec / r)
	var eccentricity = e_vec.length()
	
	# Argument of periapsis (angle from positive x-axis to periapsis)
	var arg_periapsis = atan2(e_vec.y, e_vec.x)
	
	# Semi-minor axis: b = a * sqrt(1 - e²) for ellipse
	var semi_minor: float
	if eccentricity < 1.0 and semi_major > 0:
		semi_minor = semi_major * sqrt(1.0 - eccentricity * eccentricity)
	else:
		semi_minor = abs(semi_major) * sqrt(abs(eccentricity * eccentricity - 1.0))
	
	# Distance from center to focus (where the planet is): c = a * e
	var focus_distance = abs(semi_major) * eccentricity
	
	return {
		"semi_major": semi_major,
		"semi_minor": semi_minor,
		"eccentricity": eccentricity,
		"arg_periapsis": arg_periapsis,
		"focus_distance": focus_distance,
		"energy": energy,
		"angular_momentum": h
	}


## Draw trajectory as an ellipse
func _draw_trajectory_ellipse(elements: Dictionary, ref_pos: Vector2) -> void:
	var semi_major = elements["semi_major"]
	var semi_minor = elements["semi_minor"]
	var eccentricity = elements["eccentricity"]
	var arg_periapsis = elements["arg_periapsis"]
	var focus_distance = elements["focus_distance"]
	
	# Sanity check
	if semi_major <= 0 or semi_minor <= 0 or not is_finite(semi_major) or not is_finite(semi_minor):
		return
	
	# Cap very large orbits for visual clarity
	var max_orbit_size = 20000.0
	if semi_major > max_orbit_size or semi_minor > max_orbit_size:
		return
	
	# Calculate SOI for the reference body
	var soi_radius: float = INF
	if _cached_orbit_ref_body != null:
		soi_radius = calculate_sphere_of_influence_for_body(_cached_orbit_ref_body.mass)
	
	# Calculate apoapsis distance
	var periapsis_distance = semi_major * (1.0 - eccentricity)
	var apoapsis_distance = semi_major * (1.0 + eccentricity)
	
	# Check if orbit exits SOI
	var exits_soi = apoapsis_distance > soi_radius
	
	# Calculate ellipse center (offset from focus/planet by c = a*e)
	var center_offset = Vector2(-focus_distance, 0).rotated(arg_periapsis)
	var ellipse_center = ref_pos + center_offset
	
	# Find the true anomaly range to draw
	# True anomaly is 0 at periapsis, PI at apoapsis
	var start_anomaly: float = 0.0
	var end_anomaly: float = TAU
	
	if exits_soi:
		# Find true anomaly where r = SOI
		# Orbit equation: r = a(1-e²) / (1 + e*cos(θ))
		# Solving for θ: cos(θ) = (a(1-e²)/r - 1) / e
		var p = semi_major * (1.0 - eccentricity * eccentricity)  # Semi-latus rectum
		var cos_exit = (p / soi_radius - 1.0) / eccentricity
		cos_exit = clamp(cos_exit, -1.0, 1.0)
		var exit_anomaly = acos(cos_exit)
		
		# Draw from -exit_anomaly to +exit_anomaly (symmetric around periapsis)
		start_anomaly = -exit_anomaly
		end_anomaly = exit_anomaly
	
	# Draw the orbit arc
	var num_points = 128
	var alpha = 0.7
	var orbit_color = Color(trajectory_color.r, trajectory_color.g, trajectory_color.b, alpha)
	
	var points: PackedVector2Array = []
	for i in range(num_points + 1):
		var t = float(i) / float(num_points)
		var true_anomaly = start_anomaly + t * (end_anomaly - start_anomaly)
		
		# Convert true anomaly to position using orbit equation
		var r = semi_major * (1.0 - eccentricity * eccentricity) / (1.0 + eccentricity * cos(true_anomaly))
		var world_point = ref_pos + Vector2(r * cos(true_anomaly + arg_periapsis), r * sin(true_anomaly + arg_periapsis))
		points.append(to_local(world_point))
	
	# Draw the orbit segments
	for i in range(num_points):
		draw_line(points[i], points[i + 1], orbit_color, 2.0)
	
	# Draw periapsis marker (closest point) - orange dot
	var periapsis_pos = ref_pos + Vector2(periapsis_distance, 0).rotated(arg_periapsis)
	draw_circle(to_local(periapsis_pos), 4.0, Color(1.0, 0.5, 0.3, 0.8))
	
	# Draw apoapsis marker only if inside SOI
	if not exits_soi:
		var apoapsis_pos = ref_pos + Vector2(-apoapsis_distance, 0).rotated(arg_periapsis)
		draw_circle(to_local(apoapsis_pos), 4.0, Color(0.3, 0.5, 1.0, 0.8))
	else:
		# Draw SOI exit markers (where orbit crosses SOI boundary)
		var exit_color = Color(1.0, 0.3, 0.3, 0.9)  # Red for exit points
		
		# Calculate exit points
		var p = semi_major * (1.0 - eccentricity * eccentricity)  # Semi-latus rectum
		var cos_exit = (p / soi_radius - 1.0) / eccentricity
		cos_exit = clamp(cos_exit, -1.0, 1.0)
		var exit_anomaly = acos(cos_exit)
		
		# Two exit points (symmetric around periapsis)
		var exit_pos1 = ref_pos + Vector2(soi_radius * cos(exit_anomaly + arg_periapsis), soi_radius * sin(exit_anomaly + arg_periapsis))
		var exit_pos2 = ref_pos + Vector2(soi_radius * cos(-exit_anomaly + arg_periapsis), soi_radius * sin(-exit_anomaly + arg_periapsis))
		
		# Draw exit markers
		draw_circle(to_local(exit_pos1), 5.0, exit_color)
		draw_circle(to_local(exit_pos2), 5.0, exit_color)
		
		# Calculate velocity direction at exit points
		# v_r = (μ/h) * e * sin(θ)  - radial component
		# v_θ = (μ/h) * (1 + e * cos(θ))  - tangential component
		var h = elements["angular_momentum"]
		var mu = gravitational_constant * _cached_orbit_ref_body.mass
		var h_sign = sign(h)  # Determines orbit direction (CCW vs CW)
		
		# Exit 1 (positive true anomaly)
		var v_r1 = (mu / abs(h)) * eccentricity * sin(exit_anomaly)
		var v_t1 = (mu / abs(h)) * (1.0 + eccentricity * cos(exit_anomaly))
		# Radial direction (outward from focus)
		var radial_dir1 = Vector2(cos(exit_anomaly + arg_periapsis), sin(exit_anomaly + arg_periapsis))
		# Tangential direction (perpendicular, in direction of motion)
		var tangent_dir1 = Vector2(-sin(exit_anomaly + arg_periapsis), cos(exit_anomaly + arg_periapsis)) * h_sign
		var vel_dir1 = (radial_dir1 * v_r1 + tangent_dir1 * v_t1).normalized()
		
		# Exit 2 (negative true anomaly - ship approaching)
		var v_r2 = (mu / abs(h)) * eccentricity * sin(-exit_anomaly)
		var v_t2 = (mu / abs(h)) * (1.0 + eccentricity * cos(-exit_anomaly))
		var radial_dir2 = Vector2(cos(-exit_anomaly + arg_periapsis), sin(-exit_anomaly + arg_periapsis))
		var tangent_dir2 = Vector2(-sin(-exit_anomaly + arg_periapsis), cos(-exit_anomaly + arg_periapsis)) * h_sign
		var vel_dir2 = (radial_dir2 * v_r2 + tangent_dir2 * v_t2).normalized()
		
		# Draw escape lines in velocity direction
		var escape_alpha = 0.4
		var escape_color = Color(trajectory_color.r, trajectory_color.g, trajectory_color.b, escape_alpha)
		var extend_distance = 300.0
		
		draw_line(to_local(exit_pos1), to_local(exit_pos1 + vel_dir1 * extend_distance), escape_color, 2.0)
		draw_line(to_local(exit_pos2), to_local(exit_pos2 + vel_dir2 * extend_distance), escape_color, 2.0)


## Draw escape/hyperbolic trajectory as a curved line
func _draw_escape_trajectory(elements: Dictionary, ref_body: Node2D) -> void:
	var eccentricity = elements["eccentricity"]
	var semi_major = abs(elements["semi_major"])  # Negative for hyperbolic
	var arg_periapsis = elements["arg_periapsis"]
	var ref_pos = ref_body.global_position
	
	# For hyperbolic orbits (e > 1), semi_major is negative
	# Periapsis distance = a(1 - e) but a is negative, so = |a|(e - 1)
	var periapsis_distance = semi_major * (eccentricity - 1.0) if eccentricity > 1.0 else semi_major * (1.0 - eccentricity)
	
	# Draw trajectory as points along the hyperbolic/parabolic path
	var num_points = 100
	var max_true_anomaly = acos(-1.0 / eccentricity) * 0.9 if eccentricity > 1.0 else PI * 0.95  # Asymptotic limit
	
	var points: PackedVector2Array = []
	for i in range(num_points):
		# True anomaly from -max to +max (symmetric around periapsis)
		var t = float(i) / float(num_points - 1)
		var true_anomaly = -max_true_anomaly + t * 2.0 * max_true_anomaly
		
		# Radius at this true anomaly (orbit equation)
		var r: float
		if eccentricity >= 1.0:
			var denom = 1.0 + eccentricity * cos(true_anomaly)
			if denom <= 0.01:
				continue  # Skip asymptotic points
			r = semi_major * (eccentricity * eccentricity - 1.0) / denom
		else:
			r = semi_major * (1.0 - eccentricity * eccentricity) / (1.0 + eccentricity * cos(true_anomaly))
		
		if r <= 0 or r > 50000:
			continue
		
		# Convert to cartesian (relative to focus at origin)
		var angle = true_anomaly + arg_periapsis
		var pos = ref_pos + Vector2(r * cos(angle), r * sin(angle))
		points.append(to_local(pos))
	
	# Draw the trajectory
	if points.size() > 1:
		var alpha = 0.7
		var faded_color = Color(trajectory_color.r, trajectory_color.g, trajectory_color.b, alpha)
		for i in range(points.size() - 1):
			# Fade out toward the ends
			var t = abs(float(i) - float(points.size()) / 2.0) / (float(points.size()) / 2.0)
			var line_alpha = alpha * (1.0 - t * 0.5)
			var line_color = Color(trajectory_color.r, trajectory_color.g, trajectory_color.b, line_alpha)
			draw_line(points[i], points[i + 1], line_color, 2.0)
	
	# Draw periapsis marker
	var periapsis_pos = ref_pos + Vector2(periapsis_distance, 0).rotated(arg_periapsis)
	draw_circle(to_local(periapsis_pos), 4.0, Color(1.0, 0.5, 0.3, 0.8))


## Draw trajectory as line segments (fallback for escape trajectories)
func _draw_trajectory_lines(current_ref_pos: Vector2) -> void:
	var point_count = predicted_trajectory.size()
	var fade_start = 0.9
	var fade_end = 0.2
	
	# Calculate draw limit for escape trajectories
	var draw_limit = point_count - 1
	if _trajectory_reference_body != null and _trajectory_reference_positions.size() >= point_count:
		var ref_soi: float = calculate_sphere_of_influence_for_body(_trajectory_reference_body.mass)
		var exit_point_idx: int = -1
		
		for i in range(point_count):
			var ref_pos = _trajectory_reference_positions[i]
			var ship_pos = predicted_trajectory[i]
			var relative_distance = (ship_pos - ref_pos).length()
			
			if exit_point_idx < 0 and relative_distance > ref_soi:
				exit_point_idx = i
				break
		
		if exit_point_idx > 0:
			draw_limit = min(draw_limit, exit_point_idx + 10)
	
	for i in range(draw_limit):
		var ref_offset_start = Vector2.ZERO
		var ref_offset_end = Vector2.ZERO
		
		if _trajectory_reference_body != null and _trajectory_reference_positions.size() > i + 1:
			ref_offset_start = current_ref_pos - _trajectory_reference_positions[i]
			ref_offset_end = current_ref_pos - _trajectory_reference_positions[i + 1]
		
		var start_world = predicted_trajectory[i] + ref_offset_start
		var end_world = predicted_trajectory[i + 1] + ref_offset_end
		
		var start_local = to_local(start_world)
		var end_local = to_local(end_world)
		
		var t = float(i) / float(draw_limit)
		var alpha = fade_start - t * (fade_start - fade_end)
		var faded_color = Color(trajectory_color.r, trajectory_color.g, trajectory_color.b, alpha)
		draw_line(start_local, end_local, faded_color, 2.0)


func toggle_prograde_lock() -> void:
	if orientation_lock == OrientationLock.PROGRADE:
		orientation_lock = OrientationLock.NONE
	else:
		orientation_lock = OrientationLock.PROGRADE
	orientation_lock_changed.emit(orientation_lock)


func toggle_retrograde_lock() -> void:
	if orientation_lock == OrientationLock.RETROGRADE:
		orientation_lock = OrientationLock.NONE
	else:
		orientation_lock = OrientationLock.RETROGRADE
	orientation_lock_changed.emit(orientation_lock)


func update_orientation_lock() -> void:
	if velocity.length() < 1.0:
		if orientation_lock != OrientationLock.NONE:
			orientation_lock = OrientationLock.NONE
			orientation_lock_changed.emit(orientation_lock)
		return
	
	var prograde_angle = rad_to_deg(velocity.angle())
	var target_angle: float
	
	if orientation_lock == OrientationLock.PROGRADE:
		# Prograde: nozzle opposite to velocity, thrust in direction of travel
		target_angle = prograde_angle + 180.0
	elif orientation_lock == OrientationLock.RETROGRADE:
		# Retrograde: nozzle in velocity direction, thrust against direction of travel
		target_angle = prograde_angle
	else:
		return
	
	while target_angle < 0:
		target_angle += 360
	while target_angle >= 360:
		target_angle -= 360
	
	var angle_diff = target_angle - thrust_angle
	
	while angle_diff > 180:
		angle_diff -= 360
	while angle_diff < -180:
		angle_diff += 360
	
	var delta = get_physics_process_delta_time()
	var max_rotation = thrust_angle_rotation_speed * delta
	
	if abs(angle_diff) <= max_rotation:
		thrust_angle = target_angle
	elif angle_diff > 0:
		thrust_angle += max_rotation
	else:
		thrust_angle -= max_rotation
	
	while thrust_angle < 0:
		thrust_angle += 360
	while thrust_angle >= 360:
		thrust_angle -= 360


func get_orientation_lock() -> OrientationLock:
	return orientation_lock


func get_orientation_lock_name() -> String:
	match orientation_lock:
		OrientationLock.NONE:
			return "Manual"
		OrientationLock.PROGRADE:
			return "Prograde"
		OrientationLock.RETROGRADE:
			return "Retrograde"
	return "Unknown"

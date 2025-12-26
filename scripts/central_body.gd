@tool
extends Area2D
class_name Planet
## Planet that exerts gravitational pull on the ship.
## Configure mass and appearance in the editor.
## The gravitational sphere of influence is shown in the editor for level design.
## Uses Area2D for trigger-based collision detection with the ship.
## Can orbit around other planets to create solar system-like configurations.

@export_group("Physics")
@export var mass: float = 20.0:
	set(value):
		mass = value
		queue_redraw()

@export_group("Orbital Motion")
## If true, this planet will not move (ignores orbital mechanics)
@export var is_static: bool = false
## The path to the planet this body orbits around (leave empty for stationary planets like the Sun)
@export var orbits_around_path: NodePath = NodePath("")
## Initial velocity of the planet (used if not auto-calculating orbital velocity)
@export var initial_velocity: Vector2 = Vector2.ZERO
## Automatically calculate orbital velocity based on distance to parent
@export var auto_orbital_velocity: bool = true
## Gravitational constant for orbital calculations
@export var orbital_gravitational_constant: float = 500000.0
## Direction of orbit: true = counter-clockwise, false = clockwise
@export var orbit_counter_clockwise: bool = true

@export_group("Custom Orbit Shape")
## Enable custom orbit parameters (semi-major axis and eccentricity)
@export var use_custom_orbit: bool = false:
	set(value):
		use_custom_orbit = value
		notify_property_list_changed()
		queue_redraw()
## Semi-major axis of the orbit (half of the longest diameter)
@export var orbit_semi_major_axis: float = 8000.0:
	set(value):
		orbit_semi_major_axis = max(100.0, value)
		queue_redraw()
## Eccentricity of the orbit (0 = circle, 0.5 = moderate ellipse, <1 = ellipse)
@export_range(0.0, 0.99, 0.01) var orbit_eccentricity: float = 0.0:
	set(value):
		orbit_eccentricity = clamp(value, 0.0, 0.99)
		queue_redraw()
## Argument of periapsis - rotation angle of the orbit in degrees (0 = periapsis to the right)
@export_range(0.0, 360.0, 1.0) var orbit_argument_of_periapsis: float = 0.0:
	set(value):
		orbit_argument_of_periapsis = fmod(value, 360.0)
		queue_redraw()
## Starting position on the orbit in degrees (0 = periapsis, 180 = apoapsis)
@export_range(0.0, 360.0, 1.0) var orbit_starting_true_anomaly: float = 0.0:
	set(value):
		orbit_starting_true_anomaly = fmod(value, 360.0)
		queue_redraw()
## Show the orbit path in the editor
@export var show_orbit_in_editor: bool = true:
	set(value):
		show_orbit_in_editor = value
		queue_redraw()
## Color of the orbit path in editor
@export var orbit_path_color: Color = Color(0.5, 0.7, 1.0, 0.5):
	set(value):
		orbit_path_color = value
		queue_redraw()

## The resolved planet reference (set at runtime from orbits_around_path)
var orbits_around: Planet = null

@export_group("Target")
## If true, this is the planet the player must orbit to win
@export var is_target: bool = false:
	set(value):
		is_target = value
		queue_redraw()

@export_group("Debug")
## Enable debug logging for orbital mechanics
@export var debug_orbital_motion: bool = false

@export_group("Editor Visualization")
## Show the sphere of influence in the editor
@export var show_soi_in_editor: bool = true:
	set(value):
		show_soi_in_editor = value
		queue_redraw()
## Color of the SOI circle in editor
@export var soi_color: Color = Color(0.3, 0.6, 1.0, 0.15):
	set(value):
		soi_color = value
		queue_redraw()
## Color of the SOI border in editor
@export var soi_border_color: Color = Color(0.3, 0.6, 1.0, 0.5):
	set(value):
		soi_border_color = value
		queue_redraw()
## Gravitational constant (should match ship's value)
@export var gravitational_constant: float = 500000.0:
	set(value):
		gravitational_constant = value
		queue_redraw()
## SOI multiplier: SOI = multiplier * sqrt(G * mass / 10000)
@export var soi_multiplier: float = 50.0:
	set(value):
		soi_multiplier = value
		queue_redraw()

## Current velocity of the planet (for orbital motion)
var velocity: Vector2 = Vector2.ZERO
## All other planets in the scene (for multi-body gravitational interactions)
var other_planets: Array = []

## Keplerian orbital state (for analytical propagation)
var _orbital_elements: OrbitalMechanics.OrbitalElements = null
var _orbit_epoch_time: float = 0.0  # Time when orbital elements were calculated
var _use_keplerian_propagation: bool = true  # Use analytical Keplerian motion

## Debug logging
var _debug_frame_counter: int = 0
const DEBUG_LOG_INTERVAL: int = 60  # Log every 60 frames


func _ready() -> void:
	queue_redraw()
	# Connect to body_entered signal for collision detection
	if not Engine.is_editor_hint():
		body_entered.connect(_on_body_entered)
		# Resolve the orbits_around_path to a Planet reference
		_resolve_orbit_parent()
		# Defer orbit initialization to ensure parent planets have initialized first
		call_deferred("_initialize_orbit")
		# Find all other planets in the scene for gravitational interactions
		call_deferred("_find_other_planets")
		# Create target indicator overlay if this is a target
		if is_target:
			_create_target_indicator()


func _resolve_orbit_parent() -> void:
	if orbits_around_path != NodePath(""):
		var node = get_node_or_null(orbits_around_path)
		if node is Planet:
			orbits_around = node
		else:
			push_warning("Planet '%s': orbits_around_path does not point to a valid Planet node" % name)


func _on_body_entered(body: Node2D) -> void:
	# Check if it's the ship (has the orbiting_body script)
	if body.has_method("trigger_explosion"):
		body.trigger_explosion(self)


func _find_other_planets() -> void:
	other_planets.clear()
	var root = get_tree().root
	other_planets = _find_all_planets(root)
	# Remove self from the list
	other_planets.erase(self)


func _find_all_planets(node: Node) -> Array:
	var result: Array = []
	if node is Planet:
		result.append(node)
	for child in node.get_children():
		result.append_array(_find_all_planets(child))
	return result


func _initialize_orbit() -> void:
	if orbits_around != null and auto_orbital_velocity:
		if use_custom_orbit:
			# Initialize with custom elliptical orbit parameters
			_initialize_custom_orbit()
		else:
			# Calculate circular orbital velocity based on current position
			_initialize_circular_orbit()
	else:
		velocity = initial_velocity
		_use_keplerian_propagation = false  # Use numerical fallback


## Initialize a circular orbit based on current position
func _initialize_circular_orbit() -> void:
	if orbits_around == null:
		return
	
	var direction_to_parent = orbits_around.global_position - global_position
	var distance = direction_to_parent.length()
	
	if distance <= 0:
		return
	
	var mu = orbital_gravitational_constant * orbits_around.mass
	
	# v = sqrt(G * M / r) for circular orbit
	var orbital_speed = sqrt(mu / distance)
	
	# Calculate perpendicular direction for orbital velocity
	var perpendicular = direction_to_parent.normalized().rotated(PI / 2 if orbit_counter_clockwise else -PI / 2)
	var relative_velocity = perpendicular * orbital_speed
	
	# Add parent's velocity so the moon moves with the parent in global frame
	if "velocity" in orbits_around:
		velocity = relative_velocity + orbits_around.velocity
	else:
		velocity = relative_velocity
	
	# Store orbital elements for Keplerian propagation (circular orbit: e = 0)
	var rel_pos = global_position - orbits_around.global_position
	var omega = atan2(rel_pos.y, rel_pos.x)  # Current angle is argument of periapsis for circular
	
	_orbital_elements = OrbitalMechanics.OrbitalElements.new()
	_orbital_elements.semi_major_axis = distance
	_orbital_elements.eccentricity = 0.0  # Circular orbit
	_orbital_elements.argument_of_periapsis = omega
	_orbital_elements.true_anomaly = 0.0  # Start at "periapsis" (any point for circular)
	_orbital_elements.angular_momentum = sqrt(mu * distance)  # h = sqrt(μ * a) for circular
	_orbital_elements.semi_minor_axis = distance
	_orbital_elements.periapsis = distance
	_orbital_elements.apoapsis = distance
	_orbital_elements.orbital_period = TAU * sqrt(pow(distance, 3) / mu)
	_orbital_elements.mean_motion = TAU / _orbital_elements.orbital_period
	_orbital_elements.is_valid = true
	
	# Record the epoch time
	_orbit_epoch_time = Time.get_ticks_msec() / 1000.0


## Initialize orbit using custom orbital parameters (semi-major axis, eccentricity, etc.)
func _initialize_custom_orbit() -> void:
	if orbits_around == null:
		return
	
	var mu = orbital_gravitational_constant * orbits_around.mass
	var a = orbit_semi_major_axis
	var e = orbit_eccentricity
	var omega = deg_to_rad(orbit_argument_of_periapsis)  # Argument of periapsis
	var nu = deg_to_rad(orbit_starting_true_anomaly)     # True anomaly (starting position)
	
	# Calculate semi-latus rectum: p = a(1 - e²)
	var p = a * (1.0 - e * e)
	
	# Calculate distance at current true anomaly: r = p / (1 + e·cos(ν))
	var r = p / (1.0 + e * cos(nu))
	
	# Calculate position relative to parent (in orbital frame, then rotate by ω)
	var angle = nu + omega
	var rel_pos = Vector2(r * cos(angle), r * sin(angle))
	
	# Set position
	global_position = orbits_around.global_position + rel_pos
	
	# Calculate velocity using vis-viva equation and angular momentum
	# v² = μ(2/r - 1/a)
	var v_squared = mu * (2.0 / r - 1.0 / a)
	var v_mag = sqrt(max(0.0, v_squared))
	
	# Angular momentum: h = sqrt(μ * p)
	var h = sqrt(mu * p)
	
	# Velocity components in orbital frame:
	# Radial velocity: v_r = (μ/h) * e * sin(ν)
	# Tangential velocity: v_t = (μ/h) * (1 + e * cos(ν))
	var v_r = (mu / h) * e * sin(nu) if h > 0 else 0.0
	var v_t = (mu / h) * (1.0 + e * cos(nu)) if h > 0 else v_mag
	
	# Convert to Cartesian velocity
	# Radial direction (pointing outward from parent)
	var radial_dir = rel_pos.normalized()
	# Tangential direction (perpendicular to radial, in direction of motion)
	var tangent_dir = radial_dir.rotated(PI / 2 if orbit_counter_clockwise else -PI / 2)
	
	# Combine radial and tangential components (relative to parent)
	var relative_velocity: Vector2
	if orbit_counter_clockwise:
		relative_velocity = radial_dir * v_r + tangent_dir * v_t
	else:
		relative_velocity = radial_dir * (-v_r) + tangent_dir * v_t
	
	# Add parent's velocity so the moon moves with the parent in global frame
	# This is critical for moons orbiting moving planets
	if "velocity" in orbits_around:
		velocity = relative_velocity + orbits_around.velocity
	else:
		velocity = relative_velocity
	
	# Store orbital elements for Keplerian propagation
	_orbital_elements = OrbitalMechanics.OrbitalElements.new()
	_orbital_elements.semi_major_axis = a
	_orbital_elements.eccentricity = e
	_orbital_elements.argument_of_periapsis = omega
	_orbital_elements.true_anomaly = nu
	_orbital_elements.angular_momentum = h
	_orbital_elements.semi_minor_axis = a * sqrt(1.0 - e * e)
	_orbital_elements.periapsis = a * (1.0 - e)
	_orbital_elements.apoapsis = a * (1.0 + e)
	_orbital_elements.orbital_period = TAU * sqrt(pow(a, 3) / mu)
	_orbital_elements.mean_motion = TAU / _orbital_elements.orbital_period
	_orbital_elements.is_valid = true
	
	# Record the epoch time
	_orbit_epoch_time = Time.get_ticks_msec() / 1000.0


func _process(_delta: float) -> void:
	# Continuously redraw in editor to ensure visualization is updated
	if Engine.is_editor_hint():
		queue_redraw()


func _physics_process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	
	# Static planets don't move
	if is_static:
		return
	
	# Only move if we orbit something
	if orbits_around == null:
		return
	
	# Debug logging
	_debug_frame_counter += 1
	
	# Use Keplerian propagation for consistent orbital mechanics
	if _use_keplerian_propagation and _orbital_elements != null and _orbital_elements.is_valid:
		_propagate_keplerian_orbit()
	else:
		# Fallback to numerical integration if Keplerian fails
		_apply_gravity(_delta)
		if velocity.length() > 0:
			global_position += velocity * _delta


## Propagate orbit using analytical Keplerian mechanics
## This uses the same math as the ship's trajectory prediction
func _propagate_keplerian_orbit() -> void:
	if orbits_around == null or _orbital_elements == null:
		return
	
	var elements = _orbital_elements
	var mu = orbital_gravitational_constant * orbits_around.mass
	
	# Get current time since epoch
	var current_time = Time.get_ticks_msec() / 1000.0
	var elapsed_time = current_time - _orbit_epoch_time
	
	# Calculate mean anomaly at current time: M = M0 + n * t
	var initial_mean_anomaly = _true_to_mean_anomaly(elements.true_anomaly, elements.eccentricity)
	var current_mean_anomaly = initial_mean_anomaly + elements.mean_motion * elapsed_time
	
	# Solve Kepler's equation to get current true anomaly
	var current_true_anomaly = _mean_to_true_anomaly(current_mean_anomaly, elements.eccentricity)
	
	# Calculate position from true anomaly
	var a = elements.semi_major_axis
	var e = elements.eccentricity
	var omega = elements.argument_of_periapsis
	var p = a * (1.0 - e * e)  # Semi-latus rectum
	
	var r = p / (1.0 + e * cos(current_true_anomaly))
	var angle = current_true_anomaly + omega
	
	# Position relative to parent
	var rel_pos = Vector2(r * cos(angle), r * sin(angle))
	global_position = orbits_around.global_position + rel_pos
	
	# Calculate velocity from orbital mechanics
	# v_r = (mu/h) * e * sin(nu)  (radial component)
	# v_t = (mu/h) * (1 + e * cos(nu))  (tangential component)
	var h = elements.angular_momentum
	if h > 0:
		var v_r = (mu / h) * e * sin(current_true_anomaly)
		var v_t = (mu / h) * (1.0 + e * cos(current_true_anomaly))
		
		var radial_dir = rel_pos.normalized()
		var tangent_dir = radial_dir.rotated(PI / 2 if orbit_counter_clockwise else -PI / 2)
		
		# Combine components for relative velocity
		var relative_velocity: Vector2
		if orbit_counter_clockwise:
			relative_velocity = radial_dir * v_r + tangent_dir * v_t
		else:
			relative_velocity = radial_dir * (-v_r) + tangent_dir * v_t
		
		# Add parent's velocity for global velocity
		if "velocity" in orbits_around:
			velocity = relative_velocity + orbits_around.velocity
		else:
			velocity = relative_velocity
	
	# Debug logging
	if debug_orbital_motion and _debug_frame_counter % DEBUG_LOG_INTERVAL == 0:
		print("[%s] t=%.2f, elapsed=%.2f, M0=%.1f deg, M=%.1f deg, v=%.1f deg" % [
			name, current_time, elapsed_time,
			rad_to_deg(initial_mean_anomaly),
			rad_to_deg(current_mean_anomaly),
			rad_to_deg(current_true_anomaly)
		])
		print("  pos=(%.1f, %.1f), rel_pos=(%.1f, %.1f), r=%.1f" % [
			global_position.x, global_position.y,
			rel_pos.x, rel_pos.y, r
		])
		print("  vel=(%.1f, %.1f), speed=%.1f" % [velocity.x, velocity.y, velocity.length()])


## Convert true anomaly to mean anomaly (for elliptical orbits)
func _true_to_mean_anomaly(true_anomaly: float, eccentricity: float) -> float:
	var e = eccentricity
	var nu = true_anomaly
	
	# Eccentric anomaly: tan(E/2) = sqrt((1-e)/(1+e)) * tan(nu/2)
	var half_nu = nu / 2.0
	var tan_half_nu = tan(half_nu)
	var factor = sqrt((1.0 - e) / (1.0 + e))
	var tan_half_E = factor * tan_half_nu
	var E = 2.0 * atan(tan_half_E)
	
	# Mean anomaly: M = E - e*sin(E)
	var M = E - e * sin(E)
	
	return M


## Convert mean anomaly to true anomaly using Newton-Raphson iteration
func _mean_to_true_anomaly(mean_anomaly: float, eccentricity: float) -> float:
	var M = fmod(mean_anomaly, TAU)
	if M < 0:
		M += TAU
	
	var e = eccentricity
	
	# Solve Kepler's equation: M = E - e*sin(E) for E
	var E = M  # Initial guess
	for _i in range(10):
		var f = E - e * sin(E) - M
		var f_prime = 1.0 - e * cos(E)
		if abs(f_prime) < 1e-10:
			break
		E = E - f / f_prime
		if abs(f) < 1e-10:
			break
	
	# Convert eccentric anomaly to true anomaly
	var half_E = E / 2.0
	var tan_half_E = tan(half_E)
	var factor = sqrt((1.0 + e) / (1.0 - e))
	var tan_half_nu = factor * tan_half_E
	var nu = 2.0 * atan(tan_half_nu)
	
	return nu


func _apply_gravity(delta: float) -> void:
	# Apply gravity only from parent body (two-body problem for orbital stability)
	if orbits_around != null:
		var direction_to_parent = orbits_around.global_position - global_position
		var distance = direction_to_parent.length()
		
		if distance > 1.0:
			var gravitational_acceleration = (orbital_gravitational_constant * orbits_around.mass) / (distance * distance)
			velocity += direction_to_parent.normalized() * gravitational_acceleration * delta
		
		# "Ride along" logic: if our parent also orbits something (grandparent),
		# we need to experience the same acceleration our parent does from the grandparent.
		# This keeps moons in stable orbits around moving planets.
		if orbits_around.orbits_around != null:
			var grandparent = orbits_around.orbits_around
			var dir_parent_to_grandparent = grandparent.global_position - orbits_around.global_position
			var dist_to_grandparent = dir_parent_to_grandparent.length()
			
			if dist_to_grandparent > 1.0:
				# Use parent's gravitational constant for consistency
				var parent_g_const = orbits_around.orbital_gravitational_constant
				var grandparent_accel = (parent_g_const * grandparent.mass) / (dist_to_grandparent * dist_to_grandparent)
				# Apply same acceleration to this moon that the parent planet experiences
				velocity += dir_parent_to_grandparent.normalized() * grandparent_accel * delta


func _create_target_indicator() -> void:
	var indicator = TargetIndicator.new()
	indicator.name = "TargetIndicator"
	add_child(indicator)


func _draw() -> void:
	if not Engine.is_editor_hint():
		return
	
	# Draw orbit path if enabled and this planet orbits something
	if show_orbit_in_editor and use_custom_orbit and orbits_around_path != NodePath(""):
		_draw_orbit_path_in_editor()
	
	if not show_soi_in_editor:
		return
	
	var soi = _calculate_soi()
	
	# Draw gradient SOI visualization (opacity increases closer to center)
	var num_rings = 20
	for i in range(num_rings, 0, -1):
		var ring_ratio = float(i) / float(num_rings)
		var ring_radius = soi * ring_ratio
		var gravity_strength = 1.0 / (ring_ratio * ring_ratio) if ring_ratio > 0.1 else 100.0
		var normalized_strength = clamp(gravity_strength / 100.0, 0.02, 0.4)
		var ring_color = Color(soi_color.r, soi_color.g, soi_color.b, normalized_strength)
		draw_circle(Vector2.ZERO, ring_radius, ring_color)
	
	draw_arc(Vector2.ZERO, soi, 0, TAU, 64, soi_border_color, 2.0)
	
	if is_target:
		var target_color = Color(0.0, 1.0, 0.3, 0.3)
		var target_border = Color(0.0, 1.0, 0.3, 0.8)
		draw_circle(Vector2.ZERO, soi * 0.1, target_color)
		draw_arc(Vector2.ZERO, soi * 0.1, 0, TAU, 32, target_border, 3.0)


## Draw the orbital path in the editor for visualization
func _draw_orbit_path_in_editor() -> void:
	var parent_node = get_node_or_null(orbits_around_path)
	if parent_node == null:
		return
	
	# In the editor, we need to draw relative to our own position
	# Calculate parent position relative to this node
	var parent_pos_local = to_local(parent_node.global_position)
	var a = orbit_semi_major_axis
	var e = orbit_eccentricity
	var omega = deg_to_rad(orbit_argument_of_periapsis)
	
	# Calculate semi-latus rectum: p = a(1 - e²)
	var p = a * (1.0 - e * e)
	
	var num_points = 128
	var points: PackedVector2Array = []
	
	for i in range(num_points + 1):
		var t = float(i) / float(num_points)
		var true_anomaly = t * TAU
		
		# Polar equation of ellipse: r = p / (1 + e·cos(θ))
		var r = p / (1.0 + e * cos(true_anomaly))
		
		# Convert to local position (relative to parent in local coords)
		var angle = true_anomaly + omega
		var local_point = parent_pos_local + Vector2(r * cos(angle), r * sin(angle))
		points.append(local_point)
	
	# Draw the orbit ellipse
	for i in range(num_points):
		draw_line(points[i], points[i + 1], orbit_path_color, 10.0)
	
	# Draw periapsis marker (closest point to parent)
	var periapsis_distance = a * (1.0 - e)
	var periapsis_local = parent_pos_local + Vector2(periapsis_distance, 0).rotated(omega)
	var pe_color = Color(1.0, 0.5, 0.3, 0.9)
	draw_circle(periapsis_local, 25.0, pe_color)
	
	# Draw apoapsis marker (farthest point from parent)
	var apoapsis_distance = a * (1.0 + e)
	var apoapsis_local = parent_pos_local + Vector2(-apoapsis_distance, 0).rotated(omega)
	var ap_color = Color(0.3, 0.5, 1.0, 0.9)
	draw_circle(apoapsis_local, 25.0, ap_color)
	
	# Draw starting position marker
	var nu = deg_to_rad(orbit_starting_true_anomaly)
	var start_r = p / (1.0 + e * cos(nu))
	var start_angle = nu + omega
	var start_local = parent_pos_local + Vector2(start_r * cos(start_angle), start_r * sin(start_angle))
	var start_color = Color(0.0, 1.0, 0.5, 0.9)
	draw_circle(start_local, 30.0, start_color)
	# Draw a small arrow indicating orbital direction
	var arrow_dir = (start_local - parent_pos_local).normalized()
	var arrow_perp = arrow_dir.rotated(PI / 2 if orbit_counter_clockwise else -PI / 2)
	draw_line(start_local, start_local + arrow_perp * 80.0, start_color, 8.0)


func _calculate_soi() -> float:
	return soi_multiplier * sqrt(gravitational_constant * mass / 10000.0)


## Calculate the orbital velocity needed for a circular orbit at a given distance from a parent body
static func calculate_orbital_velocity(parent_mass: float, distance: float, g_constant: float = 500000.0) -> float:
	if distance <= 0:
		return 0.0
	return sqrt(g_constant * parent_mass / distance)


## Get current orbital velocity magnitude
func get_orbital_speed() -> float:
	return velocity.length()


## Check if this planet is in a stable orbit
func is_orbiting() -> bool:
	return orbits_around != null and velocity.length() > 0


## Get the current orbital elements (for external calculations like SOI intersection)
## Returns a copy with updated true anomaly based on current time
func get_orbital_elements() -> OrbitalMechanics.OrbitalElements:
	if _orbital_elements == null or not _orbital_elements.is_valid:
		return null
	
	# Create a copy with current true anomaly
	var elements = OrbitalMechanics.OrbitalElements.new()
	elements.semi_major_axis = _orbital_elements.semi_major_axis
	elements.eccentricity = _orbital_elements.eccentricity
	elements.argument_of_periapsis = _orbital_elements.argument_of_periapsis
	elements.angular_momentum = _orbital_elements.angular_momentum
	elements.semi_minor_axis = _orbital_elements.semi_minor_axis
	elements.periapsis = _orbital_elements.periapsis
	elements.apoapsis = _orbital_elements.apoapsis
	elements.orbital_period = _orbital_elements.orbital_period
	elements.mean_motion = _orbital_elements.mean_motion
	elements.is_valid = _orbital_elements.is_valid
	
	# Calculate current true anomaly
	var current_time = Time.get_ticks_msec() / 1000.0
	var elapsed_time = current_time - _orbit_epoch_time
	var initial_mean_anomaly = _true_to_mean_anomaly(_orbital_elements.true_anomaly, _orbital_elements.eccentricity)
	var current_mean_anomaly = initial_mean_anomaly + _orbital_elements.mean_motion * elapsed_time
	elements.true_anomaly = _mean_to_true_anomaly(current_mean_anomaly, _orbital_elements.eccentricity)
	
	return elements


## Get the orbit epoch time (when orbital elements were calculated)
func get_orbit_epoch_time() -> float:
	return _orbit_epoch_time


## Inner class for target indicator that renders on top of the sprite
class TargetIndicator extends Node2D:
	func _ready() -> void:
		# Ensure this renders on top by setting z_index
		z_index = 1
	
	func _process(_delta: float) -> void:
		queue_redraw()
	
	func _draw() -> void:
		var parent = get_parent()
		if parent == null:
			return
		
		# Get planet radius from collision shape
		var planet_radius = 156.0  # Default
		for child in parent.get_children():
			if child is CollisionShape2D and child.shape is CircleShape2D:
				planet_radius = child.shape.radius
				break
		
		# Draw circle inside the planet (80% of radius)
		var circle_radius = planet_radius * 0.7
		var circle_color = Color(0.0, 1.0, 0.3, 0.6)
		draw_arc(Vector2.ZERO, circle_radius, 0, TAU, 64, circle_color, 3.0)

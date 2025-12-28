class_name OrbitalMechanics
## Centralized Patched Conics Approximation system for orbital mechanics.
## 
## This class provides a unified approach to orbital calculations using the
## patched conics approximation - treating gravity as a two-body problem within
## each Sphere of Influence (SOI).
##
## Key concepts:
## - SOI (Sphere of Influence): Region where a body's gravity dominates
## - Patched Conics: Treat orbit as two-body problem, "patch" together at SOI boundaries
## - Reference Frame: All calculations relative to current dominant body

## Configuration
const GRAVITATIONAL_CONSTANT: float = 500000.0
const SOI_MULTIPLIER: float = 50.0


## Calculate Sphere of Influence radius for a body based on its mass
## SOI = multiplier * sqrt(G * M / 10000)
static func calculate_soi(mass: float, g_const: float = GRAVITATIONAL_CONSTANT) -> float:
	return SOI_MULTIPLIER * sqrt(g_const * mass / 10000.0)


## Data structure representing the current patched conics state
class PatchedConicsState:
	## The body whose SOI we're currently in (null = outermost/sun)
	var reference_body: Node2D = null
	## Parent body (what reference_body orbits, if any)
	var parent_body: Node2D = null
	## Grandparent body (for nested moons)
	var grandparent_body: Node2D = null
	## Cached SOI radius of reference body
	var reference_soi: float = INF
	## Current orbital elements relative to reference_body
	var orbital_elements: OrbitalElements = null
	## Whether we're exiting the current SOI
	var exiting_soi: bool = false
	## Distance to SOI edge
	var distance_to_soi_edge: float = INF
	
	func clear() -> void:
		reference_body = null
		parent_body = null
		grandparent_body = null
		reference_soi = INF
		orbital_elements = null
		exiting_soi = false
		distance_to_soi_edge = INF


## Data structure for Keplerian orbital elements
class OrbitalElements:
	var semi_major_axis: float = 0.0      ## a - half the longest diameter
	var semi_minor_axis: float = 0.0      ## b - half the shortest diameter
	var eccentricity: float = 0.0         ## e - shape (0=circle, <1=ellipse, 1=parabola, >1=hyperbola)
	var argument_of_periapsis: float = 0.0 ## ω - rotation angle of orbit
	var true_anomaly: float = 0.0         ## ν - current position angle from periapsis
	var specific_energy: float = 0.0      ## ε - total orbital energy per unit mass
	var angular_momentum: float = 0.0     ## h - angular momentum per unit mass
	var periapsis: float = 0.0            ## Closest approach distance
	var apoapsis: float = 0.0             ## Farthest distance (INF for hyperbolic)
	var orbital_period: float = 0.0       ## T - time for one orbit (INF for non-elliptical)
	var mean_motion: float = 0.0          ## n - angular velocity for circular orbit
	var is_valid: bool = false            ## Whether calculation succeeded
	
	## Check if orbit is bound (elliptical)
	func is_bound() -> bool:
		return eccentricity < 1.0 and semi_major_axis > 0
	
	## Check if orbit is circular (within tolerance)
	func is_circular(tolerance: float = 0.01) -> bool:
		return eccentricity < tolerance
	
	## Check if orbit escapes (hyperbolic/parabolic)
	func is_escape() -> bool:
		return eccentricity >= 1.0


## Calculate orbital elements from position and velocity vectors
## 
## @param position: Position relative to reference body center
## @param velocity: Velocity relative to reference body (not global!)
## @param mu: Standard gravitational parameter (G * M of reference body)
## @return: OrbitalElements with calculated values
static func calculate_orbital_elements(position: Vector2, velocity: Vector2, mu: float) -> OrbitalElements:
	var elements = OrbitalElements.new()
	
	var r = position.length()
	var v = velocity.length()
	
	if r < 1.0 or mu <= 0:
		return elements  # Invalid input
	
	# Specific orbital energy: ε = v²/2 - μ/r
	elements.specific_energy = (v * v / 2.0) - (mu / r)
	
	# Angular momentum (scalar in 2D): h = r × v (z-component)
	elements.angular_momentum = position.x * velocity.y - position.y * velocity.x
	
	# Semi-major axis: a = -μ/(2ε)
	if abs(elements.specific_energy) > 0.001:
		elements.semi_major_axis = -mu / (2.0 * elements.specific_energy)
	else:
		# Near-parabolic, treat as very large
		elements.semi_major_axis = INF
		elements.eccentricity = 1.0
		elements.is_valid = false
		return elements
	
	# Eccentricity vector: e = (v × h)/μ - r/|r|
	var h = elements.angular_momentum
	var v_cross_h = Vector2(velocity.y, -velocity.x) * h
	var e_vec = (v_cross_h / mu) - (position / r)
	elements.eccentricity = e_vec.length()
	
	# Argument of periapsis (direction of periapsis from reference)
	elements.argument_of_periapsis = atan2(e_vec.y, e_vec.x)
	
	# True anomaly (current position angle from periapsis)
	var current_angle = atan2(position.y, position.x)
	elements.true_anomaly = current_angle - elements.argument_of_periapsis
	# Normalize to [-π, π]
	while elements.true_anomaly > PI:
		elements.true_anomaly -= TAU
	while elements.true_anomaly < -PI:
		elements.true_anomaly += TAU
	
	# Semi-minor axis
	var a = elements.semi_major_axis
	var e = elements.eccentricity
	if e < 1.0 and a > 0:
		elements.semi_minor_axis = a * sqrt(1.0 - e * e)
	else:
		elements.semi_minor_axis = abs(a) * sqrt(abs(e * e - 1.0))
	
	# Periapsis and apoapsis
	elements.periapsis = abs(a) * (1.0 - e)
	if e < 1.0:
		elements.apoapsis = a * (1.0 + e)
	else:
		elements.apoapsis = INF
	
	# Orbital period (only for elliptical orbits)
	if e < 1.0 and a > 0:
		elements.orbital_period = TAU * sqrt(pow(a, 3) / mu)
		elements.mean_motion = TAU / elements.orbital_period
	else:
		elements.orbital_period = INF
		elements.mean_motion = 0.0
	
	elements.is_valid = true
	return elements


## Find position on orbit at a given true anomaly
## 
## @param elements: Orbital elements
## @param true_anomaly: Angle from periapsis (radians)
## @return: Position vector relative to reference body
static func position_at_true_anomaly(elements: OrbitalElements, true_anomaly: float) -> Vector2:
	if not elements.is_valid:
		return Vector2.ZERO
	
	var a = elements.semi_major_axis
	var e = elements.eccentricity
	
	# Semi-latus rectum: p = a(1 - e²)
	var p = a * (1.0 - e * e)
	
	# Distance from focus: r = p / (1 + e·cos(ν))
	var r = p / (1.0 + e * cos(true_anomaly))
	
	# Position in orbital frame rotated by argument of periapsis
	var angle = true_anomaly + elements.argument_of_periapsis
	return Vector2(r * cos(angle), r * sin(angle))


## Generate trajectory points for visualization
## 
## @param elements: Orbital elements
## @param num_points: Number of points to generate
## @param soi_radius: SOI radius (to clip trajectory at exit)
## @return: Array of position vectors relative to reference body
static func generate_trajectory_points(elements: OrbitalElements, num_points: int = 128, soi_radius: float = INF) -> PackedVector2Array:
	var points = PackedVector2Array()
	
	if not elements.is_valid or elements.eccentricity >= 1.0:
		return points
	
	var a = elements.semi_major_axis
	var e = elements.eccentricity
	
	# Determine if orbit exits SOI
	var apoapsis = a * (1.0 + e)
	var exits_soi = apoapsis > soi_radius and e > 0.01
	
	var start_anomaly: float = 0.0
	var end_anomaly: float = TAU
	
	if exits_soi:
		# Find true anomaly where r = SOI
		var p = a * (1.0 - e * e)
		var cos_exit = (p / soi_radius - 1.0) / e
		cos_exit = clamp(cos_exit, -1.0, 1.0)
		var exit_anomaly = acos(cos_exit)
		start_anomaly = -exit_anomaly
		end_anomaly = exit_anomaly
	
	for i in range(num_points + 1):
		var t = float(i) / float(num_points)
		var true_anomaly = start_anomaly + t * (end_anomaly - start_anomaly)
		points.append(position_at_true_anomaly(elements, true_anomaly))
	
	return points


## Build SOI hierarchy from ship position
## 
## This is the core of patched conics: determine which body's SOI we're in,
## and build the parent chain for reference frame transformations.
##
## @param ship_position: Global position of ship
## @param bodies: Array of central bodies (planets)
## @param g_const: Gravitational constant
## @return: PatchedConicsState with hierarchy information
static func build_soi_hierarchy(ship_position: Vector2, bodies: Array, g_const: float = GRAVITATIONAL_CONSTANT) -> PatchedConicsState:
	var state = PatchedConicsState.new()
	
	# Find the innermost (smallest) SOI the ship is inside
	# Excluding static bodies as they represent the "root" (like the Sun)
	var smallest_soi: float = INF
	var current_body: Node2D = null
	
	for body in bodies:
		if body == null:
			continue
		
		# Skip static bodies - we want orbiting bodies' SOIs
		if "is_static" in body and body.is_static:
			continue
		if not ("orbits_around" in body) or body.orbits_around == null:
			continue
		
		var distance = (body.global_position - ship_position).length()
		var soi = calculate_soi(body.mass, g_const)
		
		# If inside this SOI and it's smaller than current, use it
		if distance <= soi and soi < smallest_soi:
			smallest_soi = soi
			current_body = body
	
	if current_body != null:
		state.reference_body = current_body
		state.reference_soi = smallest_soi
		state.distance_to_soi_edge = smallest_soi - (current_body.global_position - ship_position).length()
		
		# Build parent chain
		if "orbits_around" in current_body and current_body.orbits_around != null:
			state.parent_body = current_body.orbits_around
			
			if "orbits_around" in state.parent_body and state.parent_body.orbits_around != null:
				state.grandparent_body = state.parent_body.orbits_around
	else:
		# Not inside any child SOI - find a body whose SOI we ARE inside
		# This includes static bodies (like the Sun) which have large SOIs
		for body in bodies:
			if body == null:
				continue
			var distance = (body.global_position - ship_position).length()
			if distance < 1.0:
				continue
			var soi = calculate_soi(body.mass, g_const)
			# Only use this body if we're actually inside its SOI
			if distance <= soi:
				state.reference_body = body
				state.reference_soi = soi
				state.distance_to_soi_edge = soi - distance
				break  # Use the first valid body (typically the root/sun)
	
	return state


## Calculate gravitational acceleration using patched conics
## 
## In patched conics, we only apply gravity from the reference body.
## We also apply "frame dragging" acceleration to account for the reference
## body's own orbital motion.
##
## @param ship_position: Global position of ship
## @param ship_velocity: Current velocity of ship (will be modified)
## @param state: Current patched conics state
## @param delta: Physics timestep
## @param g_const: Gravitational constant
## @return: New velocity after gravity application
static func apply_patched_conic_gravity(
	ship_position: Vector2,
	ship_velocity: Vector2,
	state: PatchedConicsState,
	delta: float,
	g_const: float = GRAVITATIONAL_CONSTANT
) -> Vector2:
	var new_velocity = ship_velocity
	
	if state.reference_body == null:
		return new_velocity
	
	# Apply "frame dragging" - ship experiences same acceleration as reference body
	# This keeps the ship's orbit stable relative to a moving reference frame
	if state.parent_body != null:
		var ref_body = state.reference_body
		var parent_body = state.parent_body
		
		var dir_to_parent = parent_body.global_position - ref_body.global_position
		var dist_to_parent = dir_to_parent.length()
		
		if dist_to_parent > 1.0:
			var parent_g_const = ref_body.orbital_gravitational_constant if "orbital_gravitational_constant" in ref_body else g_const
			var parent_accel = (parent_g_const * parent_body.mass) / (dist_to_parent * dist_to_parent)
			new_velocity += dir_to_parent.normalized() * parent_accel * delta
		
		# Also apply grandparent frame dragging (for moons)
		if state.grandparent_body != null:
			var grandparent_body = state.grandparent_body
			var dir_to_grandparent = grandparent_body.global_position - parent_body.global_position
			var dist_to_grandparent = dir_to_grandparent.length()
			
			if dist_to_grandparent > 1.0:
				var gp_g_const = parent_body.orbital_gravitational_constant if "orbital_gravitational_constant" in parent_body else g_const
				var gp_accel = (gp_g_const * grandparent_body.mass) / (dist_to_grandparent * dist_to_grandparent)
				new_velocity += dir_to_grandparent.normalized() * gp_accel * delta
	
	# Apply gravity from reference body only (true two-body problem)
	# Only apply if within the body's SOI (patched conics boundary)
	var direction_to_center = state.reference_body.global_position - ship_position
	var distance = direction_to_center.length()
	
	if distance > 1.0 and distance <= state.reference_soi:
		var gravity_accel = (g_const * state.reference_body.mass) / (distance * distance)
		new_velocity += direction_to_center.normalized() * gravity_accel * delta
	
	return new_velocity


## Get velocity relative to reference body (for orbital calculations)
## 
## @param ship_velocity: Global velocity of ship
## @param reference_body: Body to calculate relative velocity from
## @return: Velocity relative to reference body
static func get_relative_velocity(ship_velocity: Vector2, reference_body: Node2D) -> Vector2:
	if reference_body == null:
		return ship_velocity
	
	if "velocity" in reference_body:
		return ship_velocity - reference_body.velocity
	
	return ship_velocity


## Get position relative to reference body
##
## @param ship_position: Global position of ship
## @param reference_body: Body to calculate relative position from
## @return: Position relative to reference body center
static func get_relative_position(ship_position: Vector2, reference_body: Node2D) -> Vector2:
	if reference_body == null:
		return ship_position
	
	return ship_position - reference_body.global_position


## Predict trajectory using patched conics (with SOI transitions)
## 
## This generates trajectory points that account for SOI transitions,
## creating multiple "patches" as the ship moves between bodies.
##
## @param ship_position: Starting position
## @param ship_velocity: Starting velocity
## @param bodies: Array of central bodies
## @param max_time: Maximum prediction time
## @param num_points: Number of trajectory points
## @param g_const: Gravitational constant
## @return: Array of trajectory patches, each containing points relative to its reference body
static func predict_patched_trajectory(
	ship_position: Vector2,
	ship_velocity: Vector2,
	bodies: Array,
	max_time: float = 60.0,
	num_points: int = 200,
	g_const: float = GRAVITATIONAL_CONSTANT
) -> Array:  # Array of { "ref_body": Node2D, "points": PackedVector2Array }
	
	var patches: Array = []
	var current_patch = { "ref_body": null, "points": PackedVector2Array() }
	
	# Get initial state
	var state = build_soi_hierarchy(ship_position, bodies, g_const)
	current_patch["ref_body"] = state.reference_body
	
	# If we have a stable elliptical orbit, just use Keplerian prediction
	if state.reference_body != null:
		var rel_pos = get_relative_position(ship_position, state.reference_body)
		var rel_vel = get_relative_velocity(ship_velocity, state.reference_body)
		var mu = g_const * state.reference_body.mass
		var elements = calculate_orbital_elements(rel_pos, rel_vel, mu)
		
		if elements.is_valid and elements.is_bound():
			# Simple Keplerian trajectory
			current_patch["points"] = generate_trajectory_points(elements, num_points, state.reference_soi)
			patches.append(current_patch)
			return patches
	
	# For escape trajectories or complex situations, do numerical integration
	var time_step = max_time / num_points
	var sim_pos = ship_position
	var sim_vel = ship_velocity
	var last_ref_body = state.reference_body
	
	# Add first point
	if last_ref_body != null:
		current_patch["points"].append(sim_pos - last_ref_body.global_position)
	else:
		current_patch["points"].append(sim_pos)
	
	for i in range(num_points):
		# Update SOI state
		state = build_soi_hierarchy(sim_pos, bodies, g_const)
		
		# Check for SOI transition
		if state.reference_body != last_ref_body:
			# Save current patch and start new one
			if current_patch["points"].size() > 1:
				patches.append(current_patch)
			current_patch = { "ref_body": state.reference_body, "points": PackedVector2Array() }
			last_ref_body = state.reference_body
		
		# Apply gravity using patched conics
		sim_vel = apply_patched_conic_gravity(sim_pos, sim_vel, state, time_step, g_const)
		sim_pos += sim_vel * time_step
		
		# Store point relative to reference body
		if state.reference_body != null:
			current_patch["points"].append(sim_pos - state.reference_body.global_position)
		else:
			current_patch["points"].append(sim_pos)
	
	if current_patch["points"].size() > 1:
		patches.append(current_patch)
	
	return patches

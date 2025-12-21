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
			var parent_accel = (g_const * parent_body.mass) / (dist_to_parent * dist_to_parent)
			new_velocity += dir_to_parent.normalized() * parent_accel * delta
		
		# Also apply grandparent frame dragging (for moons)
		if state.grandparent_body != null:
			var grandparent_body = state.grandparent_body
			var dir_to_grandparent = grandparent_body.global_position - parent_body.global_position
			var dist_to_grandparent = dir_to_grandparent.length()
			
			if dist_to_grandparent > 1.0:
				var gp_accel = (g_const * grandparent_body.mass) / (dist_to_grandparent * dist_to_grandparent)
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


# =============================================================================
# ENCOUNTER PREDICTION SYSTEM (KSP-Style Patched Conics)
# =============================================================================

## Exit types for orbit patches
enum PatchExitType { NONE, SOI_EXIT, SOI_ENTER, COLLISION, MAX_TIME }

## Represents a single segment of predicted trajectory (one conic section)
class OrbitPatch:
	var reference_body: Node2D       ## Which body we're orbiting
	var orbital_elements: OrbitalElements  
	var start_time: float = 0.0      ## When this patch begins (from prediction start)
	var end_time: float = INF        ## When this patch ends
	var start_true_anomaly: float    ## True anomaly at patch start
	var end_true_anomaly: float      ## True anomaly at patch end
	var exit_type: int = PatchExitType.NONE
	var next_body: Node2D = null     ## Body whose SOI we enter (if SOI_ENTER)
	var soi_radius: float = INF      ## SOI radius of reference body
	
	## Get trajectory points for visualization (relative to reference body)
	func get_trajectory_points(num_points: int = 128) -> PackedVector2Array:
		if orbital_elements == null or not orbital_elements.is_valid:
			return PackedVector2Array()
		return OrbitalMechanics.generate_trajectory_points_range(
			orbital_elements, start_true_anomaly, end_true_anomaly, num_points
		)


## Cached orbital data for a moving body (planet/moon)
class BodyOrbitCache:
	var body: Node2D
	var parent_body: Node2D
	var orbital_elements: OrbitalElements
	var mu: float                    ## G * parent_mass
	var mean_anomaly_at_epoch: float ## M₀ at time 0
	var is_valid: bool = false


# =============================================================================
# KEPLER EQUATION SOLVER
# =============================================================================

## Solve Kepler's equation: M = E - e*sin(E) for elliptic orbits
## Uses Newton-Raphson iteration
## @param M: Mean anomaly (radians)
## @param e: Eccentricity (0 <= e < 1)
## @param tolerance: Convergence tolerance
## @param max_iterations: Maximum iterations
## @return: Eccentric anomaly E (radians)
static func solve_kepler_elliptic(M: float, e: float, tolerance: float = 1e-8, max_iterations: int = 30) -> float:
	# Normalize M to [0, 2π]
	M = fmod(M, TAU)
	if M < 0:
		M += TAU
	
	# Initial guess (Danby's approximation for better convergence)
	var E: float
	if M < PI:
		E = M + e * 0.85
	else:
		E = M - e * 0.85
	
	# Newton-Raphson iteration: E_new = E - f(E)/f'(E)
	# f(E) = E - e*sin(E) - M
	# f'(E) = 1 - e*cos(E)
	for i in range(max_iterations):
		var f = E - e * sin(E) - M
		var f_prime = 1.0 - e * cos(E)
		
		if abs(f_prime) < 1e-12:
			break
		
		var delta = f / f_prime
		E -= delta
		
		if abs(delta) < tolerance:
			break
	
	return E


## Solve Kepler's equation for hyperbolic orbits: M = e*sinh(H) - H
## @param M: Mean anomaly (radians, can be any value)
## @param e: Eccentricity (e > 1)
## @return: Hyperbolic anomaly H
static func solve_kepler_hyperbolic(M: float, e: float, tolerance: float = 1e-8, max_iterations: int = 30) -> float:
	# Initial guess
	var H: float
	if abs(M) < 1.0:
		H = M
	else:
		H = sign(M) * log(2.0 * abs(M) / e + 1.8)
	
	# Newton-Raphson: f(H) = e*sinh(H) - H - M, f'(H) = e*cosh(H) - 1
	for i in range(max_iterations):
		var sinh_H = sinh(H)
		var cosh_H = cosh(H)
		var f = e * sinh_H - H - M
		var f_prime = e * cosh_H - 1.0
		
		if abs(f_prime) < 1e-12:
			break
		
		var delta = f / f_prime
		H -= delta
		
		if abs(delta) < tolerance:
			break
	
	return H


## Convert eccentric anomaly to true anomaly (elliptic orbit)
static func eccentric_to_true_anomaly(E: float, e: float) -> float:
	var beta = e / (1.0 + sqrt(1.0 - e * e))
	return E + 2.0 * atan2(beta * sin(E), 1.0 - beta * cos(E))


## Convert true anomaly to eccentric anomaly (elliptic orbit)
static func true_to_eccentric_anomaly(nu: float, e: float) -> float:
	return 2.0 * atan2(sqrt(1.0 - e) * sin(nu / 2.0), sqrt(1.0 + e) * cos(nu / 2.0))


## Convert hyperbolic anomaly to true anomaly
static func hyperbolic_to_true_anomaly(H: float, e: float) -> float:
	return 2.0 * atan2(sqrt(e + 1.0) * sinh(H / 2.0), sqrt(e - 1.0) * cosh(H / 2.0))


## Convert true anomaly to hyperbolic anomaly
static func true_to_hyperbolic_anomaly(nu: float, e: float) -> float:
	var tan_half_nu = tan(nu / 2.0)
	var tanh_half_H = tan_half_nu * sqrt((e - 1.0) / (e + 1.0))
	return 2.0 * atanh(clamp(tanh_half_H, -0.99999, 0.99999))


## Calculate mean anomaly from true anomaly
static func true_to_mean_anomaly(nu: float, e: float) -> float:
	if e < 1.0:
		# Elliptic
		var E = true_to_eccentric_anomaly(nu, e)
		return E - e * sin(E)
	else:
		# Hyperbolic
		var H = true_to_hyperbolic_anomaly(nu, e)
		return e * sinh(H) - H


## Calculate true anomaly from mean anomaly
static func mean_to_true_anomaly(M: float, e: float) -> float:
	if e < 1.0:
		var E = solve_kepler_elliptic(M, e)
		return eccentric_to_true_anomaly(E, e)
	else:
		var H = solve_kepler_hyperbolic(M, e)
		return hyperbolic_to_true_anomaly(H, e)


# =============================================================================
# TIME-OF-FLIGHT CALCULATIONS
# =============================================================================

## Calculate time to travel from current true anomaly to target true anomaly
## @param elements: Orbital elements
## @param nu_start: Starting true anomaly (radians)
## @param nu_end: Ending true anomaly (radians)
## @param mu: Standard gravitational parameter
## @return: Time of flight (positive, accounts for wrap-around for elliptic)
static func time_of_flight(elements: OrbitalElements, nu_start: float, nu_end: float, mu: float) -> float:
	if not elements.is_valid or mu <= 0:
		return INF
	
	var e = elements.eccentricity
	var a = elements.semi_major_axis
	
	if e < 1.0 and a > 0:
		# Elliptic orbit
		var M_start = true_to_mean_anomaly(nu_start, e)
		var M_end = true_to_mean_anomaly(nu_end, e)
		
		var delta_M = M_end - M_start
		# Handle wrap-around (always go forward in time)
		if delta_M < 0:
			delta_M += TAU
		
		# T = delta_M / n, where n = sqrt(mu/a³)
		var n = sqrt(mu / pow(a, 3))
		return delta_M / n
	
	elif e > 1.0:
		# Hyperbolic orbit
		var a_abs = abs(a)
		var M_start = true_to_mean_anomaly(nu_start, e)
		var M_end = true_to_mean_anomaly(nu_end, e)
		
		var delta_M = M_end - M_start
		var n = sqrt(mu / pow(a_abs, 3))
		return abs(delta_M) / n
	
	return INF


## Calculate true anomaly after a given time from current position
## @param elements: Orbital elements  
## @param current_nu: Current true anomaly
## @param delta_time: Time to advance
## @param mu: Standard gravitational parameter
## @return: New true anomaly
static func true_anomaly_after_time(elements: OrbitalElements, current_nu: float, delta_time: float, mu: float) -> float:
	if not elements.is_valid or mu <= 0 or delta_time <= 0:
		return current_nu
	
	var e = elements.eccentricity
	var a = elements.semi_major_axis
	
	# Determine orbit direction from angular momentum sign
	# Positive h = counter-clockwise (prograde), mean anomaly increases
	# Negative h = clockwise (retrograde), mean anomaly decreases
	var direction = sign(elements.angular_momentum) if elements.angular_momentum != 0 else 1.0
	
	if e < 1.0 and a > 0:
		# Elliptic
		var n = sqrt(mu / pow(a, 3))
		var M_current = true_to_mean_anomaly(current_nu, e)
		var M_new = M_current + direction * n * delta_time
		return mean_to_true_anomaly(M_new, e)
	
	elif e > 1.0:
		# Hyperbolic
		var a_abs = abs(a)
		var n = sqrt(mu / pow(a_abs, 3))
		var M_current = true_to_mean_anomaly(current_nu, e)
		var M_new = M_current + direction * n * delta_time
		return mean_to_true_anomaly(M_new, e)
	
	return current_nu


# =============================================================================
# BODY POSITION PREDICTION
# =============================================================================

## Build orbit cache for a moving body (planet or moon)
static func build_body_orbit_cache(body: Node2D, g_const: float = GRAVITATIONAL_CONSTANT) -> BodyOrbitCache:
	var cache = BodyOrbitCache.new()
	cache.body = body
	
	# Check if body orbits something
	if not ("orbits_around" in body) or body.orbits_around == null:
		cache.is_valid = false
		return cache
	
	cache.parent_body = body.orbits_around
	
	# Get gravitational parameter (use consistent g_const for all bodies)
	cache.mu = g_const * cache.parent_body.mass
	
	# Calculate current orbital elements
	var rel_pos = body.global_position - cache.parent_body.global_position
	var body_vel = body.velocity if "velocity" in body else Vector2.ZERO
	var parent_vel = cache.parent_body.velocity if "velocity" in cache.parent_body else Vector2.ZERO
	var rel_vel = body_vel - parent_vel
	
	cache.orbital_elements = calculate_orbital_elements(rel_pos, rel_vel, cache.mu)
	
	if cache.orbital_elements.is_valid:
		# Calculate mean anomaly at epoch (current time = 0)
		cache.mean_anomaly_at_epoch = true_to_mean_anomaly(
			cache.orbital_elements.true_anomaly,
			cache.orbital_elements.eccentricity
		)
		cache.is_valid = true
	
	return cache


## Predict position of a body at future time t (relative to its parent)
static func predict_body_position_relative(cache: BodyOrbitCache, time: float) -> Vector2:
	if not cache.is_valid:
		return Vector2.ZERO
	
	var e = cache.orbital_elements.eccentricity
	var a = cache.orbital_elements.semi_major_axis
	
	# Determine orbit direction from angular momentum sign
	var direction = sign(cache.orbital_elements.angular_momentum) if cache.orbital_elements.angular_momentum != 0 else 1.0
	
	# Calculate mean anomaly at time t
	var n = sqrt(cache.mu / pow(abs(a), 3)) if a != 0 else 0.0
	var M = cache.mean_anomaly_at_epoch + direction * n * time
	
	# Convert to true anomaly
	var nu = mean_to_true_anomaly(M, e)
	
	# Get position at this anomaly
	return position_at_true_anomaly(cache.orbital_elements, nu)


## Predict global position of a body at future time (recursive for moons)
static func predict_body_position_global(cache: BodyOrbitCache, body_caches: Dictionary, time: float) -> Vector2:
	if not cache.is_valid:
		return cache.body.global_position if cache.body else Vector2.ZERO
	
	# Get position relative to parent
	var rel_pos = predict_body_position_relative(cache, time)
	
	# Get parent's predicted position
	var parent_pos: Vector2
	if cache.parent_body in body_caches:
		parent_pos = predict_body_position_global(body_caches[cache.parent_body], body_caches, time)
	else:
		# Parent is stationary (like the Sun)
		parent_pos = cache.parent_body.global_position
	
	return parent_pos + rel_pos


# =============================================================================
# SOI ENCOUNTER DETECTION
# =============================================================================

## Check if a position is inside a body's SOI
static func is_inside_soi(position: Vector2, body_position: Vector2, soi_radius: float) -> bool:
	return (position - body_position).length() <= soi_radius


## Find the time when ship trajectory intersects a body's SOI
## Uses bisection search on sampled trajectory points
## @return: Dictionary with { "time": float, "position": Vector2, "velocity": Vector2, "entering": bool } or empty if no intersection
static func find_soi_intersection(
	ship_elements: OrbitalElements,
	ship_ref_body: Node2D,
	target_body: Node2D,
	target_cache: BodyOrbitCache,
	body_caches: Dictionary,
	start_time: float,
	end_time: float,
	current_soi_radius: float,
	g_const: float,
	num_samples: int = 64
) -> Dictionary:
	if not ship_elements.is_valid:
		return {}
	
	var target_soi = calculate_soi(target_body.mass, g_const)
	var mu = g_const * ship_ref_body.mass if ship_ref_body else 0.0
	
	# Sample the trajectory
	var time_step = (end_time - start_time) / num_samples
	var prev_inside: bool = false
	var prev_time: float = start_time
	var prev_distance: float = INF
	
	for i in range(num_samples + 1):
		var t = start_time + i * time_step
		
		# Get ship position at time t
		var nu = true_anomaly_after_time(ship_elements, ship_elements.true_anomaly, t - start_time, mu)
		var ship_rel_pos = position_at_true_anomaly(ship_elements, nu)
		
		# Get reference body position at time t
		var ref_body_pos: Vector2
		if ship_ref_body in body_caches:
			ref_body_pos = predict_body_position_global(body_caches[ship_ref_body], body_caches, t)
		else:
			ref_body_pos = ship_ref_body.global_position if ship_ref_body else Vector2.ZERO
		
		var ship_global_pos = ref_body_pos + ship_rel_pos
		
		# Get target body position at time t
		var target_pos = predict_body_position_global(target_cache, body_caches, t)
		
		var distance = (ship_global_pos - target_pos).length()
		var inside = distance <= target_soi
		
		# Check for SOI entry (wasn't inside, now is)
		if inside and not prev_inside and i > 0:
			# Refine with bisection
			var refined = _refine_soi_crossing(
				ship_elements, ship_ref_body, target_cache, body_caches,
				prev_time, t, target_soi, mu, g_const, true
			)
			if not refined.is_empty():
				refined["entering"] = true
				return refined
		
		# Check for SOI exit (was inside, now isn't)
		if not inside and prev_inside and i > 0:
			var refined = _refine_soi_crossing(
				ship_elements, ship_ref_body, target_cache, body_caches,
				prev_time, t, target_soi, mu, g_const, false
			)
			if not refined.is_empty():
				refined["entering"] = false
				return refined
		
		prev_inside = inside
		prev_time = t
		prev_distance = distance
	
	return {}


## Refine SOI crossing time using bisection
static func _refine_soi_crossing(
	ship_elements: OrbitalElements,
	ship_ref_body: Node2D,
	target_cache: BodyOrbitCache,
	body_caches: Dictionary,
	t_start: float,
	t_end: float,
	target_soi: float,
	mu: float,
	g_const: float,
	looking_for_entry: bool,
	iterations: int = 16
) -> Dictionary:
	var t_low = t_start
	var t_high = t_end
	
	for i in range(iterations):
		var t_mid = (t_low + t_high) / 2.0
		
		var nu = true_anomaly_after_time(ship_elements, ship_elements.true_anomaly, t_mid, mu)
		var ship_rel_pos = position_at_true_anomaly(ship_elements, nu)
		
		var ref_body_pos: Vector2
		if ship_ref_body in body_caches:
			ref_body_pos = predict_body_position_global(body_caches[ship_ref_body], body_caches, t_mid)
		else:
			ref_body_pos = ship_ref_body.global_position if ship_ref_body else Vector2.ZERO
		
		var ship_global_pos = ref_body_pos + ship_rel_pos
		var target_pos = predict_body_position_global(target_cache, body_caches, t_mid)
		
		var distance = (ship_global_pos - target_pos).length()
		var inside = distance <= target_soi
		
		if looking_for_entry:
			if inside:
				t_high = t_mid
			else:
				t_low = t_mid
		else:
			if inside:
				t_low = t_mid
			else:
				t_high = t_mid
	
	var t_final = (t_low + t_high) / 2.0
	
	# Calculate final state
	var nu_final = true_anomaly_after_time(ship_elements, ship_elements.true_anomaly, t_final, mu)
	var ship_rel_pos = position_at_true_anomaly(ship_elements, nu_final)
	
	# Calculate velocity at this point
	var ship_rel_vel = velocity_at_true_anomaly(ship_elements, nu_final, mu)
	
	var ref_body_pos: Vector2
	var ref_body_vel: Vector2
	if ship_ref_body in body_caches:
		ref_body_pos = predict_body_position_global(body_caches[ship_ref_body], body_caches, t_final)
		# Approximate ref body velocity
		var ref_pos_later = predict_body_position_global(body_caches[ship_ref_body], body_caches, t_final + 0.01)
		ref_body_vel = (ref_pos_later - ref_body_pos) / 0.01
	else:
		ref_body_pos = ship_ref_body.global_position if ship_ref_body else Vector2.ZERO
		ref_body_vel = ship_ref_body.velocity if ship_ref_body and "velocity" in ship_ref_body else Vector2.ZERO
	
	return {
		"time": t_final,
		"position": ref_body_pos + ship_rel_pos,
		"velocity": ref_body_vel + ship_rel_vel,
		"true_anomaly": nu_final
	}


## Calculate velocity at a given true anomaly
## Uses the stored angular momentum sign to determine orbit direction
static func velocity_at_true_anomaly(elements: OrbitalElements, nu: float, mu: float) -> Vector2:
	if not elements.is_valid or mu <= 0:
		return Vector2.ZERO
	
	var a = elements.semi_major_axis
	var e = elements.eccentricity
	var omega = elements.argument_of_periapsis
	
	# Semi-latus rectum
	var p: float
	if e < 1.0:
		p = a * (1.0 - e * e)
	else:
		p = abs(a) * (e * e - 1.0)
	
	if p <= 0:
		return Vector2.ZERO
	
	# Use signed angular momentum to preserve orbit direction
	# h > 0 = counter-clockwise, h < 0 = clockwise
	var h = elements.angular_momentum
	if abs(h) < 0.001:
		# Fallback to computed magnitude if stored h is too small
		h = sqrt(mu * p)
	
	# Velocity components in perifocal frame
	# v_r = (μ/h) * e * sin(ν)
	# v_t = (μ/h) * (1 + e*cos(ν))
	# Note: when h is negative, both components flip, reversing tangential direction
	var v_r = (mu / h) * e * sin(nu)  # Radial
	var v_t = (mu / h) * (1.0 + e * cos(nu))  # Tangential
	
	# Convert to inertial frame
	var angle = nu + omega
	var radial_dir = Vector2(cos(angle), sin(angle))
	var tangent_dir = Vector2(-sin(angle), cos(angle))
	
	return radial_dir * v_r + tangent_dir * v_t


# =============================================================================
# ORBIT PATCH CHAIN PREDICTION
# =============================================================================

## Predict chain of orbit patches (encounters with moving bodies)
## This is the main entry point for KSP-style trajectory prediction
## @param ship_position: Current global position
## @param ship_velocity: Current global velocity
## @param bodies: Array of all central bodies
## @param max_time: Maximum prediction time
## @param max_patches: Maximum number of orbit patches to compute
## @param g_const: Gravitational constant
## @return: Array of OrbitPatch objects
static func predict_encounter_chain(
	ship_position: Vector2,
	ship_velocity: Vector2,
	bodies: Array,
	max_time: float = 300.0,
	max_patches: int = 3,
	g_const: float = GRAVITATIONAL_CONSTANT
) -> Array[OrbitPatch]:
	var patches: Array[OrbitPatch] = []
	
	# Build orbit caches for all moving bodies
	var body_caches: Dictionary = {}
	for body in bodies:
		if body == null:
			continue
		if "orbits_around" in body and body.orbits_around != null:
			body_caches[body] = build_body_orbit_cache(body, g_const)
	
	# Get initial state
	var state = build_soi_hierarchy(ship_position, bodies, g_const)
	var current_pos = ship_position
	var current_vel = ship_velocity
	var current_time: float = 0.0
	
	for patch_idx in range(max_patches):
		var ref_body = state.reference_body
		if ref_body == null:
			break
		
		# Calculate orbital elements relative to current reference body
		var rel_pos = get_relative_position(current_pos, ref_body)
		var rel_vel = get_relative_velocity(current_vel, ref_body)
		var mu = g_const * ref_body.mass
		var elements = calculate_orbital_elements(rel_pos, rel_vel, mu)
		
		if not elements.is_valid:
			break
		
		# Create orbit patch
		var patch = OrbitPatch.new()
		patch.reference_body = ref_body
		patch.orbital_elements = elements
		patch.start_time = current_time
		patch.start_true_anomaly = elements.true_anomaly
		patch.soi_radius = state.reference_soi
		
		# Determine patch end (SOI exit, encounter, or max time)
		var remaining_time = max_time - current_time
		
		# Calculate when we'd exit current SOI (if orbit is escape or extends beyond)
		var soi_exit_time: float = INF
		var soi_exit_anomaly: float = INF
		
		if elements.eccentricity >= 1.0 or elements.apoapsis > state.reference_soi:
			# Will exit SOI - find exit time
			var exit_info = _find_soi_exit_time(elements, state.reference_soi, mu)
			soi_exit_time = exit_info["time"]
			soi_exit_anomaly = exit_info["anomaly"]
		
		# Check for encounters with other bodies inside this SOI
		var earliest_encounter: Dictionary = {}
		var earliest_encounter_time: float = INF
		var encounter_body: Node2D = null
		
		for body in bodies:
			if body == null or body == ref_body:
				continue
			
			# Only check bodies that orbit our reference body (moons/children)
			if not ("orbits_around" in body) or body.orbits_around != ref_body:
				continue
			
			if not body in body_caches:
				continue
			
			var check_time = min(remaining_time, soi_exit_time)
			var intersection = find_soi_intersection(
				elements, ref_body, body, body_caches[body], body_caches,
				current_time, current_time + check_time, state.reference_soi, g_const
			)
			
			if not intersection.is_empty() and intersection["entering"]:
				if intersection["time"] < earliest_encounter_time:
					earliest_encounter = intersection
					earliest_encounter_time = intersection["time"]
					encounter_body = body
		
		# Determine how this patch ends
		if earliest_encounter_time < soi_exit_time and earliest_encounter_time < current_time + remaining_time:
			# Encounter with child body
			patch.end_time = earliest_encounter_time
			patch.end_true_anomaly = earliest_encounter.get("true_anomaly", elements.true_anomaly)
			patch.exit_type = PatchExitType.SOI_ENTER
			patch.next_body = encounter_body
			
			# Update state for next patch
			current_pos = earliest_encounter["position"]
			current_vel = earliest_encounter["velocity"]
			current_time = earliest_encounter_time
			
			# Build new SOI state
			state = build_soi_hierarchy(current_pos, bodies, g_const)
			
		elif soi_exit_time < remaining_time:
			# Exit current SOI
			patch.end_time = current_time + soi_exit_time
			patch.end_true_anomaly = soi_exit_anomaly
			patch.exit_type = PatchExitType.SOI_EXIT
			
			# Calculate position/velocity at SOI exit
			var exit_pos = position_at_true_anomaly(elements, soi_exit_anomaly)
			var exit_vel = velocity_at_true_anomaly(elements, soi_exit_anomaly, mu)
			
			# Transform to parent reference frame
			var ref_body_pos: Vector2
			var ref_body_vel: Vector2
			
			if ref_body in body_caches:
				var exit_time = current_time + soi_exit_time
				ref_body_pos = predict_body_position_global(body_caches[ref_body], body_caches, exit_time)
				var ref_pos_later = predict_body_position_global(body_caches[ref_body], body_caches, exit_time + 0.01)
				ref_body_vel = (ref_pos_later - ref_body_pos) / 0.01
			else:
				ref_body_pos = ref_body.global_position
				ref_body_vel = ref_body.velocity if "velocity" in ref_body else Vector2.ZERO
			
			current_pos = ref_body_pos + exit_pos
			current_vel = ref_body_vel + exit_vel
			current_time = patch.end_time
			
			# Get parent body as new reference
			if "orbits_around" in ref_body and ref_body.orbits_around != null:
				patch.next_body = ref_body.orbits_around
			
			# Rebuild SOI state
			state = build_soi_hierarchy(current_pos, bodies, g_const)
			
		else:
			# Orbit continues within SOI for remaining time
			patch.end_time = max_time
			if elements.eccentricity < 1.0:
				# Full ellipse or remaining arc
				patch.end_true_anomaly = elements.true_anomaly + TAU
			else:
				patch.end_true_anomaly = soi_exit_anomaly if is_finite(soi_exit_anomaly) else elements.true_anomaly
			patch.exit_type = PatchExitType.MAX_TIME
		
		patches.append(patch)
		
		# Stop if we hit max time or no valid continuation
		if patch.exit_type == PatchExitType.MAX_TIME or state.reference_body == null:
			break
	
	return patches


## Find time until ship exits the SOI
static func _find_soi_exit_time(elements: OrbitalElements, soi_radius: float, mu: float) -> Dictionary:
	var e = elements.eccentricity
	var a = elements.semi_major_axis
	var nu_current = elements.true_anomaly
	
	# Semi-latus rectum
	var p: float
	if e < 1.0:
		p = a * (1.0 - e * e)
	else:
		p = abs(a) * (e * e - 1.0)
	
	if p <= 0:
		return { "time": INF, "anomaly": INF }
	
	# Find true anomaly at SOI boundary: r = p / (1 + e*cos(nu)) = soi
	# cos(nu_exit) = (p/soi - 1) / e
	var cos_exit = (p / soi_radius - 1.0) / e
	
	if abs(cos_exit) > 1.0:
		# Orbit doesn't reach SOI boundary
		return { "time": INF, "anomaly": INF }
	
	var nu_exit = acos(cos_exit)
	
	# We want the exit point in the direction of travel
	# Check if we're moving towards or away from periapsis
	if e < 1.0:
		# Elliptic - find the exit that's ahead in time
		# If current anomaly is negative (approaching periapsis from one side)
		# the exit will be on the other side
		
		# Calculate time to both exit points
		var time_to_pos_exit = time_of_flight(elements, nu_current, nu_exit, mu)
		var time_to_neg_exit = time_of_flight(elements, nu_current, -nu_exit, mu)
		
		if time_to_pos_exit < time_to_neg_exit:
			return { "time": time_to_pos_exit, "anomaly": nu_exit }
		else:
			return { "time": time_to_neg_exit, "anomaly": -nu_exit }
	else:
		# Hyperbolic - only one exit direction makes sense
		# Moving outward from periapsis
		if nu_current >= 0:
			var time_to_exit = time_of_flight(elements, nu_current, nu_exit, mu)
			return { "time": time_to_exit, "anomaly": nu_exit }
		else:
			var time_to_exit = time_of_flight(elements, nu_current, -nu_exit, mu)
			return { "time": time_to_exit, "anomaly": -nu_exit }


## Generate trajectory points for a specific anomaly range
static func generate_trajectory_points_range(
	elements: OrbitalElements,
	start_anomaly: float,
	end_anomaly: float,
	num_points: int = 128
) -> PackedVector2Array:
	var points = PackedVector2Array()
	
	if not elements.is_valid:
		return points
	
	for i in range(num_points + 1):
		var t = float(i) / float(num_points)
		var nu = start_anomaly + t * (end_anomaly - start_anomaly)
		var pos = position_at_true_anomaly(elements, nu)
		if pos.length() < 100000:  # Sanity check
			points.append(pos)
	
	return points


# =============================================================================
# ENCOUNTER PREDICTION (Orbit Intersection Method)
# =============================================================================
# 
# This approach:
# 1. First checks if the ship's orbit geometrically overlaps with the "SOI tube"
#    swept by each potential encounter body along its orbit
# 2. If overlap exists, finds the exact encounter time using iterative refinement
# 3. Computes the hyperbola/orbit in the new SOI at the encounter point

## Result of encounter prediction - contains next orbit after SOI transition
class EncounterPrediction:
	var has_encounter: bool = false
	var encounter_body: Node2D = null        ## The body we'll encounter
	var reference_body: Node2D = null        ## The reference body at prediction time (to track movement)
	var encounter_time: float = 0.0          ## Time until encounter (seconds)
	var encounter_position: Vector2          ## Global position at SOI entry
	var encounter_body_pos_relative: Vector2 ## Position of encounter body relative to reference body at encounter
	var ship_velocity_at_encounter: Vector2  ## Global velocity at SOI entry
	var relative_position: Vector2           ## Position relative to encounter body
	var relative_velocity: Vector2           ## Velocity relative to encounter body
	var next_orbit_elements: OrbitalElements ## Orbital elements in new SOI
	var next_soi_radius: float = 0.0


## Check if ship's orbit could potentially intersect a body's SOI tube
## Returns true if the orbit radii ranges overlap
static func _orbits_could_intersect(ship_elements: OrbitalElements, body_elements: OrbitalElements, body_soi: float) -> bool:
	if not ship_elements.is_valid or not body_elements.is_valid:
		return false
	
	# Get ship's periapsis and apoapsis (or max range for hyperbola)
	var ship_pe = ship_elements.periapsis
	var ship_ap = ship_elements.apoapsis if ship_elements.eccentricity < 1.0 else ship_elements.periapsis * 10.0
	
	# Get body's orbit inner and outer bounds (orbit ± SOI)
	var body_pe = body_elements.periapsis
	var body_ap = body_elements.apoapsis if body_elements.eccentricity < 1.0 else body_elements.periapsis * 2.0
	
	var body_inner = max(0, body_pe - body_soi)
	var body_outer = body_ap + body_soi
	
	# Check if ranges overlap
	# Ship range: [ship_pe, ship_ap]
	# Body SOI tube: [body_inner, body_outer]
	return ship_ap >= body_inner and ship_pe <= body_outer


## Predict the next encounter using orbit intersection method
## 
## Algorithm:
## 1. For each potential encounter body (children of current reference body)
## 2. Check if ship's orbit overlaps with the body's SOI tube
## 3. If yes, sample along ship's orbit to find closest approach times
## 4. Refine to find exact SOI entry point
## 5. Calculate the orbit in the new SOI
static func predict_next_encounter(
	ship_position: Vector2,
	ship_velocity: Vector2,
	current_ref_body: Node2D,
	bodies: Array,
	max_time: float = 300.0,
	time_step: float = 0.5,
	g_const: float = GRAVITATIONAL_CONSTANT
) -> EncounterPrediction:
	var result = EncounterPrediction.new()
	
	if current_ref_body == null:
		return result
	
	var current_soi = calculate_soi(current_ref_body.mass, g_const)
	var ref_pos = current_ref_body.global_position
	var ref_vel = current_ref_body.velocity if "velocity" in current_ref_body else Vector2.ZERO
	
	# Calculate ship's orbital elements relative to reference body
	var ship_rel_pos = ship_position - ref_pos
	var ship_rel_vel = ship_velocity - ref_vel
	var ship_mu = g_const * current_ref_body.mass
	var ship_elements = calculate_orbital_elements(ship_rel_pos, ship_rel_vel, ship_mu)
	
	if not ship_elements.is_valid:
		return result
	
	var ship_nu0 = ship_elements.true_anomaly
	
	# Find potential encounter bodies (children orbiting the same parent)
	var candidates: Array = []
	
	for body in bodies:
		if body == null or body == current_ref_body:
			continue
		if not ("orbits_around" in body) or body.orbits_around != current_ref_body:
			continue
		
		# Get body's orbital elements
		var body_pos = body.global_position
		var body_vel = body.velocity if "velocity" in body else Vector2.ZERO
		var body_rel_pos = body_pos - ref_pos
		var body_rel_vel = body_vel - ref_vel
		
		var body_mu = g_const * current_ref_body.mass
		var body_elements = calculate_orbital_elements(body_rel_pos, body_rel_vel, body_mu)
		var body_soi = calculate_soi(body.mass, g_const)
		
		if not body_elements.is_valid:
			continue
		
		# PHASE 1: Quick geometric check - do the orbits overlap?
		if not _orbits_could_intersect(ship_elements, body_elements, body_soi):
			continue
		
		# Store as candidate for detailed checking
		candidates.append({
			"body": body,
			"elements": body_elements,
			"mu": body_mu,
			"nu0": body_elements.true_anomaly,
			"soi": body_soi
		})
	
	if candidates.is_empty():
		return result
	
	# PHASE 2: Find earliest encounter among candidates
	var earliest_time: float = INF
	var earliest_candidate: Dictionary = {}
	
	for candidate in candidates:
		# Use adaptive time step based on body's orbital period for better accuracy
		# Smaller/faster bodies need finer sampling
		var body_period = candidate["elements"].orbital_period
		var adaptive_step = time_step
		if body_period < INF and body_period > 0:
			# Use at least 100 samples per orbit, but don't go below 0.1s
			adaptive_step = min(time_step, max(0.1, body_period / 100.0))
		
		var encounter_info = _find_encounter_time(
			ship_elements, ship_nu0, ship_mu,
			candidate["elements"], candidate["nu0"], candidate["mu"],
			candidate["soi"], current_soi, max_time, adaptive_step
		)
		
		if encounter_info["found"] and encounter_info["time"] < earliest_time:
			earliest_time = encounter_info["time"]
			earliest_candidate = candidate
			earliest_candidate["encounter_info"] = encounter_info
	
	if earliest_candidate.is_empty():
		return result
	
	# PHASE 3: Calculate exact state at encounter
	var enc_info = earliest_candidate["encounter_info"]
	var enc_time = enc_info["time"]
	var body = earliest_candidate["body"]
	var body_elements = earliest_candidate["elements"]
	var body_nu0 = earliest_candidate["nu0"]
	var body_mu = earliest_candidate["mu"]
	var body_soi = earliest_candidate["soi"]
	
	# Ship state at encounter time
	var ship_nu_enc = true_anomaly_after_time(ship_elements, ship_nu0, enc_time, ship_mu)
	var ship_pos_enc = position_at_true_anomaly(ship_elements, ship_nu_enc)
	var ship_vel_enc = velocity_at_true_anomaly(ship_elements, ship_nu_enc, ship_mu)
	
	# Body state at encounter time
	var body_nu_enc = true_anomaly_after_time(body_elements, body_nu0, enc_time, body_mu)
	var body_pos_enc = position_at_true_anomaly(body_elements, body_nu_enc)
	var body_vel_enc = velocity_at_true_anomaly(body_elements, body_nu_enc, body_mu)
	
	# Relative state (ship relative to encounter body)
	var rel_pos = ship_pos_enc - body_pos_enc
	var rel_vel = ship_vel_enc - body_vel_enc
	
	# Normalize relative position to exactly the SOI boundary
	# This ensures the encounter point is precisely on the SOI edge
	var actual_distance = rel_pos.length()
	if actual_distance > 0.1:
		rel_pos = rel_pos.normalized() * body_soi
		# Adjust ship_pos_enc to match the normalized entry point
		ship_pos_enc = body_pos_enc + rel_pos
	
	# Calculate orbital elements in new SOI
	var new_mu = g_const * body.mass
	var new_elements = calculate_orbital_elements(rel_pos, rel_vel, new_mu)
	
	# Fill result
	result.has_encounter = true
	result.encounter_body = body
	result.reference_body = current_ref_body  # Store reference body to track its movement
	result.encounter_time = enc_time
	result.encounter_position = ref_pos + ship_pos_enc
	result.encounter_body_pos_relative = body_pos_enc  # Store relative to ref body, not global
	result.ship_velocity_at_encounter = ref_vel + ship_vel_enc
	result.relative_position = rel_pos
	result.relative_velocity = rel_vel
	result.next_orbit_elements = new_elements
	result.next_soi_radius = body_soi
	
	return result


## Find the time when ship enters a body's SOI
## Uses coarse sampling followed by bisection refinement
static func _find_encounter_time(
	ship_elements: OrbitalElements, ship_nu0: float, ship_mu: float,
	body_elements: OrbitalElements, body_nu0: float, body_mu: float,
	body_soi: float, current_soi: float, max_time: float, time_step: float
) -> Dictionary:
	var result = { "found": false, "time": INF }
	
	var num_steps = int(max_time / time_step)
	var prev_distance: float = INF
	var prev_inside: bool = false
	var prev_time: float = 0.0
	
	for step in range(num_steps + 1):
		var t = step * time_step
		
		# Ship position at time t
		var ship_nu = true_anomaly_after_time(ship_elements, ship_nu0, t, ship_mu)
		var ship_pos = position_at_true_anomaly(ship_elements, ship_nu)
		
		# Check if ship has exited current SOI (no point continuing)
		if ship_pos.length() > current_soi:
			break
		
		# Body position at time t
		var body_nu = true_anomaly_after_time(body_elements, body_nu0, t, body_mu)
		var body_pos = position_at_true_anomaly(body_elements, body_nu)
		
		var distance = (ship_pos - body_pos).length()
		var inside = distance <= body_soi
		
		# Detect SOI entry (transition from outside to inside)
		if inside and not prev_inside and step > 0:
			# Refine using bisection (24 iterations for ~0.00001s precision)
			var refined_time = _bisect_soi_crossing(
				ship_elements, ship_nu0, ship_mu,
				body_elements, body_nu0, body_mu,
				body_soi, prev_time, t, 24
			)
			result["found"] = true
			result["time"] = refined_time
			return result
		
		prev_distance = distance
		prev_inside = inside
		prev_time = t
	
	return result


## Bisection search to find exact SOI crossing time
static func _bisect_soi_crossing(
	ship_elements: OrbitalElements, ship_nu0: float, ship_mu: float,
	body_elements: OrbitalElements, body_nu0: float, body_mu: float,
	body_soi: float, t_low: float, t_high: float, iterations: int
) -> float:
	for i in range(iterations):
		var t_mid = (t_low + t_high) / 2.0
		
		var ship_nu = true_anomaly_after_time(ship_elements, ship_nu0, t_mid, ship_mu)
		var ship_pos = position_at_true_anomaly(ship_elements, ship_nu)
		
		var body_nu = true_anomaly_after_time(body_elements, body_nu0, t_mid, body_mu)
		var body_pos = position_at_true_anomaly(body_elements, body_nu)
		
		var distance = (ship_pos - body_pos).length()
		
		if distance <= body_soi:
			t_high = t_mid  # Inside SOI, search earlier
		else:
			t_low = t_mid   # Outside SOI, search later
	
	return (t_low + t_high) / 2.0


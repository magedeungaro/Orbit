extends Node2D

var orbiting_body: CharacterBody2D
var planets: Array = []


func _ready() -> void:
	# Find all planets in the scene
	call_deferred("_find_planets")


func _find_planets() -> void:
	planets.clear()
	var root = get_tree().root
	planets = _find_all_planets(root)


func _find_all_planets(node: Node) -> Array:
	var result: Array = []
	if node.get_script() != null:
		var script_path = node.get_script().resource_path
		if script_path.ends_with("central_body.gd"):
			result.append(node)
	for child in node.get_children():
		result.append_array(_find_all_planets(child))
	return result


## Update the ship reference (called when ship is replaced)
func set_ship(ship: CharacterBody2D) -> void:
	orbiting_body = ship


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	_draw_orbital_paths()
	
	if orbiting_body == null:
		return
	
	# Check both the ship's setting and the global GameController setting
	var soi_enabled = orbiting_body.show_sphere_of_influence and GameController.soi_visible
	if soi_enabled and not orbiting_body.central_bodies.is_empty():
		for body in orbiting_body.central_bodies:
			if body != null:
				var soi = orbiting_body.calculate_sphere_of_influence_for_body(body.mass)
				
				var num_rings = 15
				var base_color = Color(1.0, 0.97, 0.9)
				
				for i in range(num_rings, 0, -1):
					var ring_ratio = float(i) / float(num_rings)
					var ring_radius = soi * ring_ratio
					var gravity_strength = 1.0 / (ring_ratio * ring_ratio) if ring_ratio > 0.1 else 100.0
					var normalized_strength = clamp(gravity_strength / 100.0, 0.01, 0.15)
					var ring_color = Color(base_color.r, base_color.g, base_color.b, normalized_strength)
					draw_circle(body.global_position, ring_radius, ring_color)
				
				var border_color = Color(1.0, 0.97, 0.9, 0.3)
				draw_arc(body.global_position, soi, 0, TAU, 64, border_color, 1.0)


func _draw_orbital_paths() -> void:
	for planet in planets:
		if planet == null or not is_instance_valid(planet):
			continue
		
		# Check if this planet orbits around another body (i.e., is moving)
		if not ("orbits_around" in planet) or planet.orbits_around == null:
			continue
		
		var parent = planet.orbits_around
		var parent_pos = parent.global_position
		
		# Choose color based on planet type
		var orbit_color: Color
		if "is_target" in planet and planet.is_target:
			orbit_color = Color(0.3, 1.0, 0.5, 0.4)  # Green for target
		elif parent.orbits_around != null:
			# This is a moon (parent also orbits something)
			orbit_color = Color(1.0, 0.8, 0.4, 0.5)  # Orange/gold for moons
		else:
			orbit_color = Color(0.5, 0.7, 1.0, 0.3)  # Blue for other planets
		
		# Calculate proper orbital elements for this planet
		var elements = _calculate_planet_orbital_elements(planet, parent)
		if elements.is_empty():
			continue
		
		# Draw the orbital ellipse using the calculated elements
		_draw_orbital_ellipse(elements, parent_pos, orbit_color, 2.0)


## Calculate orbital elements for a planet orbiting around a parent body
func _calculate_planet_orbital_elements(planet: Node2D, parent: Node2D) -> Dictionary:
	var r_vec = planet.global_position - parent.global_position
	
	# Get the planet's velocity relative to the parent
	# For moons, we need to subtract the parent's velocity to get the orbital velocity
	var planet_vel = planet.velocity if "velocity" in planet else Vector2.ZERO
	var parent_vel = parent.velocity if "velocity" in parent else Vector2.ZERO
	var v_vec = planet_vel - parent_vel  # Relative velocity
	
	var r = r_vec.length()
	var v = v_vec.length()
	
	if r < 1.0 or v < 0.001:
		return {}
	
	# Get gravitational constant from planet or use default
	var g_const = planet.orbital_gravitational_constant if "orbital_gravitational_constant" in planet else 500000.0
	var mu = g_const * parent.mass
	
	# Specific orbital energy: E = v²/2 - μ/r
	var energy = (v * v / 2.0) - (mu / r)
	
	# Semi-major axis: a = -μ/(2E)
	var semi_major: float
	if abs(energy) > 0.001:
		semi_major = -mu / (2.0 * energy)
	else:
		# Nearly parabolic, fall back to current distance as circular orbit
		return {
			"semi_major": r,
			"semi_minor": r,
			"eccentricity": 0.0,
			"arg_periapsis": 0.0
		}
	
	# Angular momentum (scalar in 2D): h = r × v (z-component)
	var h = r_vec.x * v_vec.y - r_vec.y * v_vec.x
	
	# Eccentricity vector: e = (v × h)/μ - r/|r|
	var v_cross_h = Vector2(v_vec.y, -v_vec.x) * h
	var e_vec = (v_cross_h / mu) - (r_vec / r)
	var eccentricity = e_vec.length()
	
	# Argument of periapsis (angle of periapsis from positive x-axis)
	var arg_periapsis = atan2(e_vec.y, e_vec.x)
	
	# Semi-minor axis
	var semi_minor: float
	if eccentricity < 1.0 and semi_major > 0:
		semi_minor = semi_major * sqrt(1.0 - eccentricity * eccentricity)
	else:
		# Hyperbolic or parabolic - use absolute value
		semi_minor = abs(semi_major) * sqrt(abs(eccentricity * eccentricity - 1.0))
	
	return {
		"semi_major": semi_major,
		"semi_minor": semi_minor,
		"eccentricity": eccentricity,
		"arg_periapsis": arg_periapsis
	}


## Draw an orbital ellipse using calculated orbital elements
## This draws a proper Keplerian orbit using the polar equation: r = a(1-e²)/(1+e·cos(θ))
func _draw_orbital_ellipse(elements: Dictionary, focus_pos: Vector2, color: Color, width: float) -> void:
	var semi_major = elements["semi_major"]
	var semi_minor = elements["semi_minor"]
	var eccentricity = elements["eccentricity"]
	var arg_periapsis = elements["arg_periapsis"]
	
	if semi_major <= 0 or semi_minor <= 0 or not is_finite(semi_major) or not is_finite(semi_minor):
		return
	
	# Limit to reasonable size
	var max_orbit_size = 50000.0
	if semi_major > max_orbit_size or semi_minor > max_orbit_size:
		return
	
	# For elliptical orbits (e < 1), draw the full orbit
	# For hyperbolic orbits (e >= 1), we'd need to handle differently, but planets should be elliptical
	if eccentricity >= 1.0:
		return
	
	var num_points = 128
	var points: PackedVector2Array = []
	
	# Calculate semi-latus rectum: p = a(1 - e²)
	var p = semi_major * (1.0 - eccentricity * eccentricity)
	
	for i in range(num_points + 1):
		var t = float(i) / float(num_points)
		var true_anomaly = t * TAU  # Full orbit from 0 to 2π
		
		# Polar equation of ellipse: r = p / (1 + e·cos(θ))
		var r = p / (1.0 + eccentricity * cos(true_anomaly))
		
		# Convert to Cartesian, applying rotation by argument of periapsis
		var angle = true_anomaly + arg_periapsis
		var point = focus_pos + Vector2(r * cos(angle), r * sin(angle))
		points.append(point)
	
	# Draw the ellipse as connected line segments
	for i in range(num_points):
		draw_line(points[i], points[i + 1], color, width)

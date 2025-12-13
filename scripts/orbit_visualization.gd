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
	# Draw orbital paths for all orbiting planets
	_draw_orbital_paths()
	
	if orbiting_body == null:
		return
	
	if orbiting_body.show_sphere_of_influence and not orbiting_body.central_bodies.is_empty():
		for body in orbiting_body.central_bodies:
			if body != null:
				# Use per-planet SOI based on mass
				var soi = orbiting_body.calculate_sphere_of_influence_for_body(body.mass)
				
				# Draw gradient SOI - opacity increases with gravity strength (closer = stronger)
				var num_rings = 15
				var base_color = Color(1.0, 0.97, 0.9)
				
				for i in range(num_rings, 0, -1):
					var ring_ratio = float(i) / float(num_rings)
					var ring_radius = soi * ring_ratio
					
					# Calculate opacity based on inverse square law (gravity strength)
					var gravity_strength = 1.0 / (ring_ratio * ring_ratio) if ring_ratio > 0.1 else 100.0
					var normalized_strength = clamp(gravity_strength / 100.0, 0.01, 0.15)
					
					var ring_color = Color(base_color.r, base_color.g, base_color.b, normalized_strength)
					draw_circle(body.global_position, ring_radius, ring_color)
				
				# Draw SOI border
				var border_color = Color(1.0, 0.97, 0.9, 0.3)
				draw_arc(body.global_position, soi, 0, TAU, 64, border_color, 1.0)
	
	if orbiting_body.show_orbit_trail and orbiting_body.orbit_trail.size() > 1:
		for i in range(orbiting_body.orbit_trail.size() - 1):
			var from_pos = orbiting_body.orbit_trail[i]
			var to_pos = orbiting_body.orbit_trail[i + 1]
			var age_ratio = float(i) / float(orbiting_body.orbit_trail.size())
			var faded_color = orbiting_body.orbit_trail_color
			faded_color.a = age_ratio * 0.7
			draw_line(from_pos, to_pos, faded_color, 2.0)


func _draw_orbital_paths() -> void:
	for planet in planets:
		if planet == null or not is_instance_valid(planet):
			continue
		
		# Check if this planet orbits around another body (i.e., is moving)
		if not ("orbits_around" in planet) or planet.orbits_around == null:
			continue
		
		var parent = planet.orbits_around
		var parent_pos = parent.global_position
		
		# Calculate orbital radius (current distance to parent)
		var orbital_radius = (planet.global_position - parent_pos).length()
		
		# Choose color based on planet type
		var orbit_color: Color
		if "is_target" in planet and planet.is_target:
			orbit_color = Color(0.3, 1.0, 0.5, 0.4)  # Green for target
		elif parent.orbits_around != null:
			# This is a moon (parent also orbits something)
			orbit_color = Color(1.0, 0.8, 0.4, 0.5)  # Orange/gold for moons
		else:
			orbit_color = Color(0.5, 0.7, 1.0, 0.3)  # Blue for other planets
		
		# Draw elliptical orbit using transform
		_draw_ellipse(parent_pos, orbital_radius, orbital_radius * 0.95, orbit_color, 2.0)


## Draw an ellipse by scaling a circle
## center: center of the ellipse
## semi_major: half the width (along x-axis before rotation)
## semi_minor: half the height (along y-axis before rotation)
## color: the color to draw
## width: line width
## rotation: rotation angle in radians (default 0)
func _draw_ellipse(center: Vector2, semi_major: float, semi_minor: float, color: Color, width: float, rotation: float = 0.0) -> void:
	# Save the current transform
	var original_transform = get_canvas_transform()
	
	# Create transform: translate to center, rotate, then scale y-axis
	var scale_ratio = semi_minor / semi_major if semi_major > 0 else 1.0
	
	# We need to use draw_set_transform to apply scaling
	# This transforms subsequent draw calls
	draw_set_transform(center, rotation, Vector2(1.0, scale_ratio))
	
	# Draw a circle at origin - it will be scaled into an ellipse
	draw_arc(Vector2.ZERO, semi_major, 0, TAU, 128, color, width)
	
	# Reset transform
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)

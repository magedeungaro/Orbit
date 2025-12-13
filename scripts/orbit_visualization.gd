extends Node2D

var orbiting_body: CharacterBody2D


func _ready() -> void:
	pass


## Update the ship reference (called when ship is replaced)
func set_ship(ship: CharacterBody2D) -> void:
	orbiting_body = ship


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
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

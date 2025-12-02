extends Node2D
## Visualization layer for drawing the orbit trail

var orbiting_body: CharacterBody2D


func _ready() -> void:
	# Get reference to the orbiting body
	orbiting_body = get_parent().get_node("OrbitingBody")
	
	if orbiting_body == null:
		print("Error: Could not find OrbitingBody node!")


func _process(_delta: float) -> void:
	# Redraw every frame to show trail
	queue_redraw()


func _draw() -> void:
	if orbiting_body == null:
		return
	
	# Draw sphere of influence for all central bodies
	if orbiting_body.show_sphere_of_influence and not orbiting_body.central_bodies.is_empty():
		for body in orbiting_body.central_bodies:
			if body != null:
				var soi = orbiting_body.calculate_sphere_of_influence()
				# Creamy, white-ish transparent color
				var soi_color = Color(1.0, 0.97, 0.9, 0.1)  # Creamy white, very transparent
				draw_circle(body.global_position, soi, soi_color)
				
				# Draw the boundary with a soft creamy line
				var border_color = Color(1.0, 0.97, 0.9, 0.3)
				draw_arc(body.global_position, soi, 0, TAU, 64, border_color, 1.0)
	
	# Draw orbit trail
	if orbiting_body.show_orbit_trail and orbiting_body.orbit_trail.size() > 1:
		# Draw lines connecting trail points
		for i in range(orbiting_body.orbit_trail.size() - 1):
			var from_pos = orbiting_body.orbit_trail[i]
			var to_pos = orbiting_body.orbit_trail[i + 1]
			
			# Fade the color based on age (older points are more transparent)
			var age_ratio = float(i) / float(orbiting_body.orbit_trail.size())
			var faded_color = orbiting_body.orbit_trail_color
			faded_color.a = age_ratio * 0.7  # Fade out older points
			
			draw_line(from_pos, to_pos, faded_color, 2.0)

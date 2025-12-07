extends Node2D

var orbiting_body: CharacterBody2D


func _ready() -> void:
	orbiting_body = get_tree().root.find_child("Ship", true, false)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if orbiting_body == null:
		return
	
	if orbiting_body.show_sphere_of_influence and not orbiting_body.central_bodies.is_empty():
		for body in orbiting_body.central_bodies:
			if body != null:
				var soi = orbiting_body.calculate_sphere_of_influence()
				var soi_color = Color(1.0, 0.97, 0.9, 0.1)
				draw_circle(body.global_position, soi, soi_color)
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

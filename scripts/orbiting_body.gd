extends CharacterBody2D

@export var thrust_force: float = 300.0
@export var gravitational_constant: float = 500000.0
@export var base_sphere_of_influence: float = 350.0
@export var proximity_gravity_boost: float = 3.0
@export var proximity_threshold: float = 150.0
@export var show_sphere_of_influence: bool = true
@export var mass: float = 50.0
@export var bounce_coefficient: float = 0.8
@export var body_radius: float = 39.0
@export var boundary_left: float = -5000.0
@export var boundary_top: float = -5000.0
@export var boundary_right: float = 25000.0
@export var boundary_bottom: float = 25000.0
@export var show_orbit_trail: bool = true
@export var orbit_trail_color: Color = Color.MAGENTA
@export var trail_max_points: int = 500
@export var use_escape_velocity_thrust: bool = false
@export var thrust_angle_rotation_speed: float = 180.0
@export var show_trajectory: bool = true
@export var trajectory_prediction_time: float = 15.0
@export var trajectory_points: int = 100
@export var trajectory_color: Color = Color.YELLOW
@export var max_fuel: float = 1000.0
@export var fuel_consumption_rate: float = 50.0
@export var stable_orbit_time_required: float = 10.0
@export var orbit_stability_threshold: float = 50.0
@export var explosion_duration: float = 1.0
@export var planet_collision_radius: float = 30.0

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

enum OrientationLock { NONE, PROGRADE, RETROGRADE }
var orientation_lock: OrientationLock = OrientationLock.NONE

signal ship_exploded
signal orientation_lock_changed(lock_type: int)


func _ready() -> void:
	current_fuel = max_fuel
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
	
	check_planet_collision()
	handle_thrust_input(delta)
	apply_gravity_from_all_bodies(delta)
	rotation = deg_to_rad(thrust_angle - 90)
	move_and_slide()
	handle_screen_bounce()
	update_orbit_trail()
	calculate_trajectory()
	check_orbit_stability(delta)
	queue_redraw()


func handle_thrust_input(delta: float) -> void:
	if Input.is_action_just_pressed("toggle_prograde"):
		toggle_prograde_lock()
	if Input.is_action_just_pressed("toggle_retrograde"):
		toggle_retrograde_lock()
	
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
	
	var is_thrusting = (Input.is_action_pressed("ui_select") or Input.is_action_pressed("thrust")) and current_fuel > 0 and not is_exploding
	
	if has_node("EngineAnimatedSprite"):
		get_node("EngineAnimatedSprite").visible = is_thrusting
	
	if is_thrusting:
		var thrust_angle_rad = deg_to_rad(thrust_angle)
		var thrust_direction = Vector2(-cos(thrust_angle_rad), -sin(thrust_angle_rad))
		var effective_thrust = calculate_escape_velocity_thrust() if use_escape_velocity_thrust else thrust_force
		current_fuel = max(0, current_fuel - fuel_consumption_rate * delta)
		velocity += (thrust_direction * effective_thrust) * delta


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
	var ship_head_offset = 43.5
	var local_up = Vector2(0, -1)
	var world_up = local_up.rotated(rotation)
	var head_position = global_position + world_up * ship_head_offset
	
	for body in central_bodies:
		if body == null:
			continue
		
		var planet_radius = planet_collision_radius
		if body.has_node("Sprite2D"):
			var sprite = body.get_node("Sprite2D")
			if sprite.texture:
				planet_radius = max(sprite.texture.get_width(), sprite.texture.get_height()) * sprite.scale.x / 2.0
		
		if (body.global_position - global_position).length() < (body_radius + planet_radius):
			trigger_explosion(body)
			return
		
		if (body.global_position - head_position).length() < planet_radius:
			trigger_explosion(body)
			return


func trigger_explosion(collided_planet: Node2D) -> void:
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


func calculate_sphere_of_influence() -> float:
	var base_gravity = 100000.0
	var gravity_ratio = gravitational_constant / base_gravity
	return base_sphere_of_influence * sqrt(gravity_ratio)


func calculate_escape_velocity_thrust() -> float:
	if central_bodies.is_empty():
		return thrust_force
	
	var closest_body = null
	var closest_distance = INF
	
	for body in central_bodies:
		var dist = (body.global_position - global_position).length()
		if dist < closest_distance:
			closest_distance = dist
			closest_body = body
	
	if closest_body == null or closest_distance < 1.0:
		return thrust_force
	
	var escape_velocity = sqrt((2.0 * gravitational_constant * closest_body.mass) / closest_distance)
	var required_acceleration = escape_velocity / 5.0
	return required_acceleration * mass


func calculate_current_escape_velocity() -> float:
	if central_bodies.is_empty():
		return 0.0
	
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
	for body in central_bodies:
		if body == null:
			continue
		
		var direction_to_center = body.global_position - global_position
		var distance = direction_to_center.length()
		var soi = calculate_sphere_of_influence()
		
		if distance > 1.0 and distance <= soi:
			var gravitational_acceleration = (gravitational_constant * body.mass) / (distance * distance)
			
			if distance < proximity_threshold:
				var proximity_factor = 1.0 - (distance / proximity_threshold)
				var boost = 1.0 + (proximity_gravity_boost - 1.0) * proximity_factor
				gravitational_acceleration *= boost
			
			velocity += direction_to_center.normalized() * gravitational_acceleration * delta


func calculate_trajectory() -> void:
	predicted_trajectory.clear()
	
	if not show_trajectory:
		return
	
	var sim_pos = global_position
	var sim_vel = velocity
	var time_step = trajectory_prediction_time / trajectory_points
	
	predicted_trajectory.append(sim_pos)
	
	for i in range(trajectory_points):
		for body in central_bodies:
			if body == null:
				continue
			
			var direction_to_center = body.global_position - sim_pos
			var distance = direction_to_center.length()
			var soi = calculate_sphere_of_influence()
			
			if distance > 1.0 and distance <= soi:
				var gravitational_acceleration = (gravitational_constant * body.mass) / (distance * distance)
				
				if distance < proximity_threshold:
					var proximity_factor = 1.0 - (distance / proximity_threshold)
					var boost = 1.0 + (proximity_gravity_boost - 1.0) * proximity_factor
					gravitational_acceleration *= boost
				
				sim_vel += direction_to_center.normalized() * gravitational_acceleration * time_step
		
		sim_pos += sim_vel * time_step
		
		var collision_detected = false
		for body in central_bodies:
			if body == null:
				continue
			
			var planet_radius = planet_collision_radius
			if body.has_node("Sprite2D"):
				var sprite = body.get_node("Sprite2D")
				if sprite.texture:
					planet_radius = max(sprite.texture.get_width(), sprite.texture.get_height()) * sprite.scale.x / 2.0
			
			if (body.global_position - sim_pos).length() < (body_radius + planet_radius):
				predicted_trajectory.append(sim_pos)
				collision_detected = true
				break
		
		if collision_detected:
			break
		
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
		
		predicted_trajectory.append(sim_pos)


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
	if not show_trajectory or predicted_trajectory.size() <= 1:
		return
	
	var dot_length = 8.0
	var gap_length = 12.0
	
	for i in range(predicted_trajectory.size() - 1):
		var start_local = to_local(predicted_trajectory[i])
		var end_local = to_local(predicted_trajectory[i + 1])
		
		var segment = end_local - start_local
		var segment_length = segment.length()
		var segment_dir = segment.normalized()
		
		var current_pos = 0.0
		var is_dot = true
		
		while current_pos < segment_length:
			if is_dot:
				var next_pos = min(current_pos + dot_length, segment_length)
				var p1 = start_local + segment_dir * current_pos
				var p2 = start_local + segment_dir * next_pos
				var fade = 1.0 - (float(i) / predicted_trajectory.size()) * 0.7
				var faded_color = Color(trajectory_color.r, trajectory_color.g, trajectory_color.b, trajectory_color.a * fade)
				draw_line(p1, p2, faded_color, 2.0)
				current_pos = next_pos + gap_length
			else:
				current_pos += gap_length
			is_dot = not is_dot


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
		target_angle = prograde_angle
	elif orientation_lock == OrientationLock.RETROGRADE:
		target_angle = prograde_angle + 180.0
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

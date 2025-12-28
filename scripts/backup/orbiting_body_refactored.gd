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

@export_group("Boundaries")
@export var boundary_left: float = -5000.0
@export var boundary_top: float = -5000.0
@export var boundary_right: float = 25000.0
@export var boundary_bottom: float = 25000.0

## Physics constants (match OrbitalMechanics)
var gravitational_constant: float = OrbitalMechanics.GRAVITATIONAL_CONSTANT
var soi_multiplier: float = OrbitalMechanics.SOI_MULTIPLIER

## Ship physical properties
var mass: float = 50.0
var bounce_coefficient: float = 0.8
var body_radius: float = 39.0
var thrust_angle_rotation_speed: float = 180.0
var fuel_consumption_rate: float = 50.0
var explosion_duration: float = 1.0

## Trajectory visualization settings
var show_trajectory: bool = true
var trajectory_color: Color = Color.YELLOW
var trajectory_points: int = 128

## Runtime state
var current_fuel: float = 1000.0
var central_bodies: Array = []
var thrust_angle: float = 0.0
var target_body: Node2D = null
var is_exploding: bool = false
var explosion_time: float = 0.0

## Orbit stability tracking
var orbit_stability_threshold: float = 50.0
var time_in_stable_orbit: float = 0.0
var orbit_distance_samples: Array[float] = []
var last_orbit_angle: float = 0.0
var total_orbit_angle: float = 0.0

## Patched Conics state (centralized orbital mechanics)
var _patched_conics_state: OrbitalMechanics.PatchedConicsState = null
var _cached_orbital_elements: OrbitalMechanics.OrbitalElements = null
var _is_thrusting: bool = false
var _was_thrusting: bool = false
var _orbit_needs_recalc: bool = true

## Orientation lock
enum OrientationLock { NONE, PROGRADE, RETROGRADE }
var orientation_lock: OrientationLock = OrientationLock.NONE

signal ship_exploded
signal orientation_lock_changed(lock_type: int)


## Get the current camera zoom scale factor for drawing
func _get_draw_scale() -> float:
	var camera = get_viewport().get_camera_2d()
	if camera != null:
		return 1.0 / camera.zoom.x
	return 1.0


func _ready() -> void:
	current_fuel = max_fuel
	velocity = initial_velocity
	_patched_conics_state = OrbitalMechanics.PatchedConicsState.new()
	
	var root = get_tree().root
	central_bodies = _find_all_nodes_with_script(root, "central_body")
	
	if central_bodies.is_empty():
		central_bodies = _find_all_nodes_by_name(root, "Earth")
	
	# Find target body for orbit stability checking
	for body in central_bodies:
		if "is_target" in body and body.is_target:
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
		_update_explosion(delta)
		queue_redraw()
		return
	
	# Update patched conics state (determines which SOI we're in)
	_update_patched_conics_state()
	
	# Handle input and thrust
	_handle_thrust_input(delta)
	
	# Apply gravity using patched conics (single reference body)
	_apply_patched_conic_gravity(delta)
	
	# Update rotation and movement
	rotation = deg_to_rad(thrust_angle - 90)
	move_and_slide()
	_handle_screen_bounce()
	
	# Check orbit stability for win condition
	_check_orbit_stability(delta)
	
	queue_redraw()


## Update the patched conics state - determines current SOI and reference body
func _update_patched_conics_state() -> void:
	var old_ref_body = _patched_conics_state.reference_body if _patched_conics_state else null
	
	_patched_conics_state = OrbitalMechanics.build_soi_hierarchy(
		global_position,
		central_bodies,
		gravitational_constant
	)
	
	# Mark orbit for recalculation if reference body changed
	if _patched_conics_state.reference_body != old_ref_body:
		_orbit_needs_recalc = true


## Apply gravity using the patched conics approximation
## Only the reference body's gravity affects the ship (true two-body problem)
func _apply_patched_conic_gravity(delta: float) -> void:
	velocity = OrbitalMechanics.apply_patched_conic_gravity(
		global_position,
		velocity,
		_patched_conics_state,
		delta,
		gravitational_constant
	)


func _handle_thrust_input(delta: float) -> void:
	# Orientation lock toggles
	if Input.is_action_just_pressed("toggle_prograde"):
		_toggle_prograde_lock()
	if Input.is_action_just_pressed("toggle_retrograde"):
		_toggle_retrograde_lock()
	
	# Gamepad toggle: cycles None -> Prograde -> Retrograde -> None
	if Input.is_action_just_pressed("toggle_orientation"):
		match orientation_lock:
			OrientationLock.NONE:
				_toggle_prograde_lock()
			OrientationLock.PROGRADE:
				orientation_lock = OrientationLock.RETROGRADE
				orientation_lock_changed.emit(orientation_lock)
			OrientationLock.RETROGRADE:
				orientation_lock = OrientationLock.NONE
				orientation_lock_changed.emit(orientation_lock)
	
	# Manual rotation breaks orientation lock
	var is_manually_rotating = Input.is_action_pressed("ui_left") or Input.is_action_pressed("rotate_left") or Input.is_action_pressed("ui_right") or Input.is_action_pressed("rotate_right")
	if is_manually_rotating and orientation_lock != OrientationLock.NONE:
		orientation_lock = OrientationLock.NONE
		orientation_lock_changed.emit(orientation_lock)
	
	# Apply orientation lock or manual rotation
	if orientation_lock != OrientationLock.NONE:
		_update_orientation_lock()
	else:
		if Input.is_action_pressed("ui_left") or Input.is_action_pressed("rotate_left"):
			thrust_angle -= thrust_angle_rotation_speed * delta
		if Input.is_action_pressed("ui_right") or Input.is_action_pressed("rotate_right"):
			thrust_angle += thrust_angle_rotation_speed * delta
	
	# Normalize thrust angle
	thrust_angle = fmod(thrust_angle + 360.0, 360.0)
	
	# Handle thrust
	var has_fuel = current_fuel > 0 or debug_infinite_fuel
	_is_thrusting = Input.is_action_pressed("thrust") and has_fuel and not is_exploding
	
	if has_node("EngineAnimatedSprite"):
		get_node("EngineAnimatedSprite").visible = _is_thrusting
	
	if _is_thrusting:
		var thrust_angle_rad = deg_to_rad(thrust_angle)
		var thrust_direction = Vector2(-cos(thrust_angle_rad), -sin(thrust_angle_rad))
		if not debug_infinite_fuel:
			current_fuel = max(0, current_fuel - fuel_consumption_rate * delta)
		velocity += thrust_direction * thrust_force * delta
		_orbit_needs_recalc = true


func get_fuel_percentage() -> float:
	return (current_fuel / max_fuel) * 100.0


func _check_orbit_stability(delta: float) -> void:
	if target_body == null:
		return
	
	var to_target = target_body.global_position - global_position
	var distance = to_target.length()
	var soi = OrbitalMechanics.calculate_soi(target_body.mass, gravitational_constant)
	
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


func _update_explosion(delta: float) -> void:
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


func _handle_screen_bounce() -> void:
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


# =============================================================================
# TRAJECTORY VISUALIZATION (Using Patched Conics)
# =============================================================================

func _draw() -> void:
	if not show_trajectory:
		return
	
	var ref_body = _patched_conics_state.reference_body if _patched_conics_state else null
	if ref_body == null:
		return
	
	# Recalculate orbital elements if needed
	var thrust_just_stopped = _was_thrusting and not _is_thrusting
	if _orbit_needs_recalc or thrust_just_stopped or _is_thrusting:
		_update_orbital_elements()
		_orbit_needs_recalc = false
	
	_was_thrusting = _is_thrusting
	
	# Draw the Keplerian trajectory ellipse
	if _cached_orbital_elements != null and _cached_orbital_elements.is_valid:
		if _cached_orbital_elements.eccentricity < 0.98:
			_draw_trajectory_ellipse()


## Update cached orbital elements using patched conics
func _update_orbital_elements() -> void:
	var ref_body = _patched_conics_state.reference_body if _patched_conics_state else null
	if ref_body == null:
		_cached_orbital_elements = null
		return
	
	var rel_pos = OrbitalMechanics.get_relative_position(global_position, ref_body)
	var rel_vel = OrbitalMechanics.get_relative_velocity(velocity, ref_body)
	var mu = gravitational_constant * ref_body.mass
	
	_cached_orbital_elements = OrbitalMechanics.calculate_orbital_elements(rel_pos, rel_vel, mu)


## Draw the Keplerian trajectory ellipse
func _draw_trajectory_ellipse() -> void:
	if _cached_orbital_elements == null or not _cached_orbital_elements.is_valid:
		return
	
	var ref_body = _patched_conics_state.reference_body
	if ref_body == null:
		return
	
	var elements = _cached_orbital_elements
	var ref_pos = ref_body.global_position
	
	var a = elements.semi_major_axis
	var e = elements.eccentricity
	var omega = elements.argument_of_periapsis
	
	if a <= 0 or not is_finite(a):
		return
	
	var max_orbit_size = 20000.0
	if a > max_orbit_size:
		return
	
	var soi_radius = _patched_conics_state.reference_soi
	var apoapsis = elements.apoapsis
	var exits_soi = apoapsis > soi_radius and e > 0.01
	
	# Determine drawing range
	var start_anomaly: float = 0.0
	var end_anomaly: float = TAU
	
	if exits_soi:
		var p = a * (1.0 - e * e)
		var cos_exit = (p / soi_radius - 1.0) / e
		cos_exit = clamp(cos_exit, -1.0, 1.0)
		var exit_anomaly = acos(cos_exit)
		start_anomaly = -exit_anomaly
		end_anomaly = exit_anomaly
	
	# Generate and draw trajectory points
	var draw_scale = _get_draw_scale()
	var line_width = 1.5 * draw_scale
	var alpha = 0.7
	var orbit_color = Color(trajectory_color.r, trajectory_color.g, trajectory_color.b, alpha)
	
	var points: PackedVector2Array = []
	var num_points = trajectory_points
	
	for i in range(num_points + 1):
		var t = float(i) / float(num_points)
		var true_anomaly = start_anomaly + t * (end_anomaly - start_anomaly)
		var p = a * (1.0 - e * e)
		var r = p / (1.0 + e * cos(true_anomaly))
		var world_point = ref_pos + Vector2(r * cos(true_anomaly + omega), r * sin(true_anomaly + omega))
		points.append(to_local(world_point))
	
	for i in range(num_points):
		draw_line(points[i], points[i + 1], orbit_color, line_width)
	
	# Draw periapsis marker
	var periapsis_color = Color(1.0, 0.5, 0.3, 0.9)
	var periapsis_pos = ref_pos + Vector2(elements.periapsis, 0).rotated(omega)
	var periapsis_local = to_local(periapsis_pos)
	var periapsis_dir = periapsis_local.normalized() if periapsis_local.length() > 1 else Vector2.RIGHT
	_draw_apsis_marker(periapsis_local, periapsis_dir, periapsis_color, "Pe", draw_scale)
	
	# Draw apoapsis marker (only if orbit doesn't exit SOI)
	if not exits_soi:
		var apoapsis_color = Color(0.3, 0.5, 1.0, 0.9)
		var apoapsis_pos = ref_pos + Vector2(-apoapsis, 0).rotated(omega)
		var apoapsis_local = to_local(apoapsis_pos)
		var apoapsis_dir = apoapsis_local.normalized() if apoapsis_local.length() > 1 else Vector2.LEFT
		_draw_apsis_marker(apoapsis_local, apoapsis_dir, apoapsis_color, "Ap", draw_scale)
	else:
		# Draw SOI exit markers
		var exit_color = Color(1.0, 0.3, 0.3, 0.9)
		var p = a * (1.0 - e * e)
		var cos_exit = (p / soi_radius - 1.0) / e
		cos_exit = clamp(cos_exit, -1.0, 1.0)
		var exit_anomaly = acos(cos_exit)
		
		var exit_pos1 = ref_pos + Vector2(soi_radius * cos(exit_anomaly + omega), soi_radius * sin(exit_anomaly + omega))
		var exit_pos2 = ref_pos + Vector2(soi_radius * cos(-exit_anomaly + omega), soi_radius * sin(-exit_anomaly + omega))
		
		draw_circle(to_local(exit_pos1), 5.0 * draw_scale, exit_color)
		draw_circle(to_local(exit_pos2), 5.0 * draw_scale, exit_color)


## Draw an apsis marker with chevron and label
func _draw_apsis_marker(pos: Vector2, direction: Vector2, color: Color, label: String, draw_scale: float = 1.0) -> void:
	var chevron_size = 8.0 * draw_scale
	var marker_radius = 4.0 * draw_scale
	var chevron_offset = 12.0 * draw_scale
	var label_offset_dist = 28.0 * draw_scale
	var line_width = 1.5 * draw_scale
	
	draw_circle(pos, marker_radius, color)
	
	var perp = Vector2(-direction.y, direction.x)
	var chevron_tip = pos + direction * chevron_offset
	var chevron_left = chevron_tip - direction * chevron_size + perp * chevron_size * 0.6
	var chevron_right = chevron_tip - direction * chevron_size - perp * chevron_size * 0.6
	
	draw_line(chevron_left, chevron_tip, color, line_width)
	draw_line(chevron_right, chevron_tip, color, line_width)
	
	var label_offset = direction * label_offset_dist
	var label_pos = pos + label_offset
	
	draw_set_transform(label_pos, -rotation, Vector2(draw_scale, draw_scale))
	draw_string(ThemeDB.fallback_font, Vector2(-8, 4), label, HORIZONTAL_ALIGNMENT_CENTER, -1, 14, color)
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)


# =============================================================================
# ORIENTATION LOCK
# =============================================================================

func _toggle_prograde_lock() -> void:
	if orientation_lock == OrientationLock.PROGRADE:
		orientation_lock = OrientationLock.NONE
	else:
		orientation_lock = OrientationLock.PROGRADE
	orientation_lock_changed.emit(orientation_lock)


func _toggle_retrograde_lock() -> void:
	if orientation_lock == OrientationLock.RETROGRADE:
		orientation_lock = OrientationLock.NONE
	else:
		orientation_lock = OrientationLock.RETROGRADE
	orientation_lock_changed.emit(orientation_lock)


func _update_orientation_lock() -> void:
	# Use relative velocity for prograde/retrograde direction
	var ref_body = _patched_conics_state.reference_body if _patched_conics_state else null
	var relative_velocity = OrbitalMechanics.get_relative_velocity(velocity, ref_body)
	
	if relative_velocity.length() < 1.0:
		if orientation_lock != OrientationLock.NONE:
			orientation_lock = OrientationLock.NONE
			orientation_lock_changed.emit(orientation_lock)
		return
	
	var prograde_angle = rad_to_deg(relative_velocity.angle())
	var target_angle: float
	
	if orientation_lock == OrientationLock.PROGRADE:
		target_angle = prograde_angle + 180.0
	elif orientation_lock == OrientationLock.RETROGRADE:
		target_angle = prograde_angle
	else:
		return
	
	target_angle = fmod(target_angle + 360.0, 360.0)
	
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
	
	thrust_angle = fmod(thrust_angle + 360.0, 360.0)


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


# =============================================================================
# PUBLIC API (for compatibility)
# =============================================================================

## Legacy function - returns SOI for a given mass
func calculate_sphere_of_influence_for_body(planet_mass: float) -> float:
	return OrbitalMechanics.calculate_soi(planet_mass, gravitational_constant)


## Legacy function - returns default SOI
func calculate_sphere_of_influence() -> float:
	return OrbitalMechanics.calculate_soi(20.0, gravitational_constant)


## Toggle prograde lock (public API)
func toggle_prograde_lock() -> void:
	_toggle_prograde_lock()


## Toggle retrograde lock (public API)
func toggle_retrograde_lock() -> void:
	_toggle_retrograde_lock()

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
var show_sphere_of_influence: bool = true
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

## Cached SOI encounter data (only recalculate when orbit changes)
var _cached_soi_encounter: Dictionary = {}
var _cached_soi_encounter_body: Node2D = null
var _cached_soi_encounter_soi: float = 0.0

## Compatibility property - exposes reference body from patched conics state
var _cached_orbit_ref_body: Node2D:
	get:
		return _patched_conics_state.reference_body if _patched_conics_state else null

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
		_cached_soi_encounter = {}  # Clear cached encounter


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
		_cached_soi_encounter = {}  # Clear cached encounter when thrusting


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
	
	# Draw the Keplerian trajectory (ellipse or hyperbola)
	if _cached_orbital_elements != null and _cached_orbital_elements.is_valid:
		if _cached_orbital_elements.eccentricity < 1.0:
			_draw_trajectory_ellipse()
		else:
			_draw_trajectory_hyperbola()
		
		# Draw predicted SOI encounter points with moving bodies
		_draw_soi_encounter_predictions()


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


## Draw a hyperbolic trajectory (eccentricity >= 1)
func _draw_trajectory_hyperbola() -> void:
	if _cached_orbital_elements == null or not _cached_orbital_elements.is_valid:
		return
	
	var ref_body = _patched_conics_state.reference_body
	if ref_body == null:
		return
	
	var elements = _cached_orbital_elements
	var ref_pos = ref_body.global_position
	
	var a = elements.semi_major_axis  # Negative for hyperbolic orbits
	var e = elements.eccentricity
	var omega = elements.argument_of_periapsis
	
	if not is_finite(a) or not is_finite(e):
		return
	
	var soi_radius = _patched_conics_state.reference_soi
	
	# For hyperbolic orbits, a is negative. Use |a| for calculations.
	var a_abs = abs(a)
	
	# Semi-latus rectum: p = a(1 - e²) = |a|(e² - 1) for hyperbola
	var p = a_abs * (e * e - 1.0)
	
	if p <= 0:
		return
	
	# Find the true anomaly range where the trajectory is within the SOI
	# r = p / (1 + e·cos(θ))
	# At SOI boundary: soi_radius = p / (1 + e·cos(θ_exit))
	# cos(θ_exit) = (p / soi_radius - 1) / e
	
	var cos_exit = (p / soi_radius - 1.0) / e
	cos_exit = clamp(cos_exit, -1.0, 1.0)
	var exit_anomaly = acos(cos_exit)
	
	# For hyperbola, the asymptote angle limits the valid range
	# The asymptotes are at θ = ±acos(-1/e)
	var asymptote_limit = acos(-1.0 / e) if e > 1.0 else PI * 0.99
	
	# Use the smaller of exit_anomaly and asymptote limit
	var max_anomaly = min(exit_anomaly, asymptote_limit * 0.98)
	
	# Determine if we're on the incoming or outgoing branch
	var rel_pos = global_position - ref_pos
	var rel_vel = OrbitalMechanics.get_relative_velocity(velocity, ref_body)
	var radial_velocity = rel_pos.normalized().dot(rel_vel)
	
	var start_anomaly: float
	var end_anomaly: float
	
	# Draw from current position through periapsis to exit
	if radial_velocity < 0:
		# Approaching periapsis (incoming)
		start_anomaly = -max_anomaly
		end_anomaly = max_anomaly
	else:
		# Moving away from periapsis (outgoing)
		start_anomaly = -max_anomaly
		end_anomaly = max_anomaly
	
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
		var r = p / (1.0 + e * cos(true_anomaly))
		
		# Skip invalid points (behind focus for hyperbola)
		if r <= 0 or not is_finite(r):
			continue
		
		var world_point = ref_pos + Vector2(r * cos(true_anomaly + omega), r * sin(true_anomaly + omega))
		points.append(to_local(world_point))
	
	# Draw the trajectory
	for i in range(points.size() - 1):
		draw_line(points[i], points[i + 1], orbit_color, line_width)
	
	# Draw periapsis marker
	var periapsis_color = Color(1.0, 0.5, 0.3, 0.9)
	var periapsis_pos = ref_pos + Vector2(elements.periapsis, 0).rotated(omega)
	var periapsis_local = to_local(periapsis_pos)
	var periapsis_dir = periapsis_local.normalized() if periapsis_local.length() > 1 else Vector2.RIGHT
	_draw_apsis_marker(periapsis_local, periapsis_dir, periapsis_color, "Pe", draw_scale)
	
	# Draw SOI exit markers
	var exit_color = Color(1.0, 0.3, 0.3, 0.9)
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


## Draw predicted SOI encounter points with moving bodies
func _draw_soi_encounter_predictions() -> void:
	var ref_body = _patched_conics_state.reference_body if _patched_conics_state else null
	if ref_body == null:
		return
	
	if _cached_orbital_elements == null or not _cached_orbital_elements.is_valid:
		return
	
	var draw_scale = _get_draw_scale()
	
	# Only recalculate encounter when orbit changes (thrusting)
	var should_recalc = _orbit_needs_recalc or _cached_soi_encounter.is_empty()
	
	# Check each body that orbits around our reference body
	for body in central_bodies:
		if body == null or body == ref_body:
			continue
		
		# Only check bodies that orbit around our current reference body
		var body_orbits = body.orbits_around if "orbits_around" in body else null
		if body_orbits != ref_body:
			continue
		
		var body_mass = body.mass if "mass" in body else 0.0
		var body_soi = OrbitalMechanics.calculate_soi(body_mass, gravitational_constant)
		
		# Get body's orbital elements
		if not "get_orbital_elements" in body:
			continue
		var body_elements = body.get_orbital_elements()
		if body_elements == null or not body_elements.is_valid:
			continue
		
		# Use cached encounter or find new one
		var encounter: Dictionary
		if should_recalc or _cached_soi_encounter_body != body:
			encounter = _find_soi_encounter(body, body_elements, body_soi)
			if not encounter.is_empty():
				_cached_soi_encounter = encounter
				_cached_soi_encounter_body = body
				_cached_soi_encounter_soi = body_soi
		else:
			encounter = _cached_soi_encounter
		
		if encounter.is_empty():
			continue
		
		# Draw encounter relative to REFERENCE BODY's current position
		# ship_pos and target_pos are relative to reference body at encounter time
		# Use reference body's current position to anchor the drawing
		var ship_pos_rel: Vector2 = encounter["ship_pos"]
		var target_pos_rel: Vector2 = encounter["target_pos"]
		var encounter_world_pos = ref_body.global_position + ship_pos_rel
		var target_center_world = ref_body.global_position + target_pos_rel
		var encounter_local = to_local(encounter_world_pos)
		
		# Draw encounter point (green star)
		var encounter_color = Color(0.3, 1.0, 0.5, 0.9)
		draw_circle(encounter_local, 8.0 * draw_scale, encounter_color)
		
		# Draw the hyperbolic trajectory around the target body
		_draw_encounter_hyperbola(encounter, body_soi, target_center_world, draw_scale, encounter_color)
		
		# Draw label with time to encounter
		var label_pos = encounter_local + Vector2.UP * 25.0 * draw_scale
		var label_text = "%.0fs" % encounter["time"]
		
		draw_set_transform(label_pos, -rotation, Vector2(draw_scale, draw_scale))
		draw_string(ThemeDB.fallback_font, Vector2(-12, 4), label_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 12, encounter_color)
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)


## Draw the hyperbolic trajectory around the encountered body
## The hyperbola shape is defined by the cached encounter geometry (rel_pos, rel_vel)
## target_center_world is where the target will be, relative to reference body's current position
func _draw_encounter_hyperbola(encounter: Dictionary, target_soi: float, target_center_world: Vector2, draw_scale: float, color: Color) -> void:
	# Use cached encounter geometry (defines the shape of the hyperbola)
	if not "rel_pos" in encounter or not "rel_vel" in encounter or not "target_mu" in encounter:
		return
	var rel_pos: Vector2 = encounter["rel_pos"]
	var rel_vel: Vector2 = encounter["rel_vel"]
	var mu: float = encounter["target_mu"]
	
	if mu <= 0:
		return
	
	var r = rel_pos.length()
	var v = rel_vel.length()
	
	if r < 0.1 or v < 0.001:
		return
	
	# Specific orbital energy: ε = v²/2 - μ/r
	var energy = (v * v / 2.0) - (mu / r)
	
	# For hyperbolic encounter, energy should be positive
	# Semi-major axis: a = -μ/(2ε)
	if abs(energy) < 0.0001:
		return  # Parabolic - edge case
	
	var a = -mu / (2.0 * energy)
	
	# Angular momentum: h = r × v (2D cross product gives scalar)
	var h = rel_pos.x * rel_vel.y - rel_pos.y * rel_vel.x
	var h_mag = abs(h)
	
	# Eccentricity vector using the correct formula:
	# e_vec = (1/μ) * ((v² - μ/r) * r - (r·v) * v)
	var v_sq = v * v
	var r_dot_v = rel_pos.dot(rel_vel)
	var e_vec = ((v_sq - mu / r) * rel_pos - r_dot_v * rel_vel) / mu
	var e = e_vec.length()
	
	# Fallback eccentricity calculation using vis-viva
	if e < 0.01 or not is_finite(e):
		# e = sqrt(1 + 2*ε*h²/μ²)
		e = sqrt(max(0, 1.0 + 2.0 * energy * h_mag * h_mag / (mu * mu)))
	
	# Argument of periapsis (angle of eccentricity vector)
	var omega = atan2(e_vec.y, e_vec.x) if e > 0.01 else 0.0
	
	# Semi-latus rectum
	var p: float
	if e < 1.0:
		p = abs(a) * (1.0 - e * e)  # Elliptical (shouldn't happen for flyby but just in case)
	else:
		p = abs(a) * (e * e - 1.0)  # Hyperbolic
	
	if p <= 0 or not is_finite(p):
		return
	
	# Calculate true anomaly range within SOI
	# r = p / (1 + e·cos(θ))
	# At SOI: cos(θ) = (p/soi - 1) / e
	var cos_exit = (p / target_soi - 1.0) / e if e > 0.01 else 0.0
	cos_exit = clamp(cos_exit, -1.0, 1.0)
	var exit_anomaly = acos(cos_exit)
	
	# For hyperbola, limit by asymptote angle
	var asymptote_limit = acos(-1.0 / e) if e > 1.0 else PI * 0.99
	var max_anomaly = min(exit_anomaly, asymptote_limit * 0.98)
	
	# Determine orbital direction from angular momentum sign
	var direction = sign(h) if h != 0 else 1.0
	
	# Generate trajectory points - start from entry and go through periapsis to exit
	var points: PackedVector2Array = []
	var num_points = 64
	
	# Determine start and end anomalies based on entry point and orbital direction
	var start_anomaly: float
	var end_anomaly: float
	
	if direction >= 0:
		# Counter-clockwise orbit: entry is at negative anomaly, exit at positive
		start_anomaly = -max_anomaly
		end_anomaly = max_anomaly
	else:
		# Clockwise orbit: entry is at positive anomaly, exit at negative
		start_anomaly = max_anomaly
		end_anomaly = -max_anomaly
	
	# Draw from entry through periapsis to exit
	for i in range(num_points + 1):
		var t = float(i) / float(num_points)
		# Sweep from start_anomaly to end_anomaly
		var true_anomaly = start_anomaly + t * (end_anomaly - start_anomaly)
		
		var denom = 1.0 + e * cos(true_anomaly)
		if abs(denom) < 0.01:
			continue
		var r_point = p / denom
		if r_point <= 0 or not is_finite(r_point):
			continue
		
		# Position relative to target body center
		var angle = true_anomaly + omega
		var point_rel = Vector2(r_point * cos(angle), r_point * sin(angle))
		
		# Convert to world coordinates at the static encounter position
		var point_world = target_center_world + point_rel
		points.append(to_local(point_world))
	
	# Draw the hyperbola
	var hyperbola_color = Color(color.r, color.g, color.b, 0.6)
	var line_width = 1.5 * draw_scale
	
	for i in range(points.size() - 1):
		draw_line(points[i], points[i + 1], hyperbola_color, line_width)
	
	# Draw periapsis marker
	var periapsis_dist = p / (1.0 + e) if e >= 0 else abs(a)
	var periapsis_world = target_center_world + Vector2(periapsis_dist, 0).rotated(omega)
	var periapsis_local = to_local(periapsis_world)
	var target_local = to_local(target_center_world)
	var pe_direction = (periapsis_local - target_local).normalized() if periapsis_local.distance_to(target_local) > 1 else Vector2.RIGHT
	
	var pe_color = Color(1.0, 0.6, 0.3, 0.9)
	draw_circle(periapsis_local, 5.0 * draw_scale, pe_color)
	
	# Draw Pe label
	var pe_label_pos = periapsis_local + pe_direction * 20.0 * draw_scale
	draw_set_transform(pe_label_pos, -rotation, Vector2(draw_scale, draw_scale))
	draw_string(ThemeDB.fallback_font, Vector2(-8, 4), "Pe", HORIZONTAL_ALIGNMENT_CENTER, -1, 10, pe_color)
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)


## Find SOI encounter with a moving body
## Returns dictionary with encounter info or empty if no encounter found
func _find_soi_encounter(target_body: Node2D, target_elements: OrbitalMechanics.OrbitalElements, target_soi: float) -> Dictionary:
	var max_time = 120.0  # Check 2 minutes ahead
	var num_samples = 240
	var dt = max_time / num_samples
	
	var ref_body = _patched_conics_state.reference_body
	if ref_body == null:
		return {}
	
	# IMPORTANT: Calculate FRESH orbital elements from current position/velocity
	var ship_rel_pos = global_position - ref_body.global_position
	var ship_rel_vel = velocity - ref_body.velocity
	var mu = gravitational_constant * ref_body.mass
	var ship_elements = OrbitalMechanics.calculate_orbital_elements(ship_rel_pos, ship_rel_vel, mu)
	
	if ship_elements == null or not ship_elements.is_valid:
		return {}
	
	# Determine orbital direction from angular momentum (h = r x v in 2D)
	var ship_h = ship_rel_pos.x * ship_rel_vel.y - ship_rel_pos.y * ship_rel_vel.x
	var ship_direction = 1.0 if ship_h >= 0 else -1.0
	
	# Target orbital direction
	var target_rel_pos = target_body.global_position - ref_body.global_position
	var target_rel_vel = target_body.velocity - ref_body.velocity if "velocity" in target_body else Vector2.ZERO
	var target_h = target_rel_pos.x * target_rel_vel.y - target_rel_pos.y * target_rel_vel.x
	var target_direction = 1.0 if target_h >= 0 else -1.0
	
	# Ship orbital parameters
	var ship_a = ship_elements.semi_major_axis
	var ship_e = ship_elements.eccentricity
	var ship_omega = ship_elements.argument_of_periapsis
	var ship_nu = ship_elements.true_anomaly
	var ship_n = ship_elements.mean_motion * ship_direction
	
	# For elliptical orbits: p = a(1-e^2), for hyperbolic: p = |a|(e^2-1)
	var ship_p: float
	if ship_e < 1.0:
		ship_p = ship_a * (1.0 - ship_e * ship_e)
	else:
		ship_p = abs(ship_a) * (ship_e * ship_e - 1.0)
	
	var ship_M0 = _true_to_mean_anomaly(ship_nu, ship_e) if ship_e < 1.0 else 0.0
	
	# Target orbital parameters
	var target_a = target_elements.semi_major_axis
	var target_e = target_elements.eccentricity
	var target_omega = target_elements.argument_of_periapsis
	var target_nu = target_elements.true_anomaly
	var target_n = target_elements.mean_motion * target_direction
	var target_p = target_a * (1.0 - target_e * target_e)
	var target_M0 = _true_to_mean_anomaly(target_nu, target_e)
	
	var was_outside = true
	
	for i in range(num_samples + 1):
		var t = float(i) * dt
		
		# Ship position at time t (relative to reference body)
		var ship_pos: Vector2
		
		if ship_e < 1.0:
			# Elliptical orbit: propagate via mean anomaly
			var ship_M = ship_M0 + ship_n * t
			var ship_nu_t = _mean_to_true_anomaly(ship_M, ship_e)
			var denom = 1.0 + ship_e * cos(ship_nu_t)
			if abs(denom) < 0.001:
				continue
			var ship_r = ship_p / denom
			if ship_r <= 0 or not is_finite(ship_r):
				continue
			var ship_angle = ship_nu_t + ship_omega
			ship_pos = Vector2(ship_r * cos(ship_angle), ship_r * sin(ship_angle))
		else:
			# Hyperbolic orbit: use linear approximation
			ship_pos = ship_rel_pos + ship_rel_vel * t
		
		# Target position at time t (relative to reference body)
		var target_M = target_M0 + target_n * t
		var target_nu_t = _mean_to_true_anomaly(target_M, target_e)
		var target_denom = 1.0 + target_e * cos(target_nu_t)
		if abs(target_denom) < 0.001:
			continue
		var target_r = target_p / target_denom
		var target_angle = target_nu_t + target_omega
		var target_pos = Vector2(target_r * cos(target_angle), target_r * sin(target_angle))
		
		# Distance between ship and target
		var dist = (ship_pos - target_pos).length()
		var is_inside = dist < target_soi
		
		if is_inside and was_outside:
			# Found entry - refine with binary search
			var target_mass = target_body.mass if "mass" in target_body else 1.0
			var target_mu = gravitational_constant * target_mass
			var refined = _refine_soi_entry(
				t - dt, t,
				ship_M0, ship_n, ship_e, ship_p, ship_omega,
				target_M0, target_n, target_e, target_p, target_omega,
				target_soi, ship_rel_pos, ship_rel_vel, ref_body.global_position, target_mu, mu
			)
			return refined
		
		was_outside = not is_inside
	
	return {}


## Refine SOI entry point using binary search
func _refine_soi_entry(
	t_low: float, t_high: float,
	ship_M0: float, ship_n: float, ship_e: float, ship_p: float, ship_omega: float,
	target_M0: float, target_n: float, target_e: float, target_p: float, target_omega: float,
	target_soi: float, ship_rel_pos: Vector2 = Vector2.ZERO, ship_rel_vel: Vector2 = Vector2.ZERO,
	ref_body_pos: Vector2 = Vector2.ZERO, target_mu: float = 1.0, ref_mu: float = 1.0
) -> Dictionary:
	for _iter in range(15):
		var t_mid = (t_low + t_high) / 2.0
		
		# Ship position at t_mid
		var ship_pos: Vector2
		if ship_e < 1.0:
			var ship_M = ship_M0 + ship_n * t_mid
			var ship_nu_t = _mean_to_true_anomaly(ship_M, ship_e)
			var ship_r = ship_p / (1.0 + ship_e * cos(ship_nu_t)) if abs(1.0 + ship_e * cos(ship_nu_t)) > 0.001 else INF
			var ship_angle = ship_nu_t + ship_omega
			ship_pos = Vector2(ship_r * cos(ship_angle), ship_r * sin(ship_angle))
		else:
			# Hyperbolic: linear approximation
			ship_pos = ship_rel_pos + ship_rel_vel * t_mid
		
		# Target position at t_mid
		var target_M = target_M0 + target_n * t_mid
		var target_nu_t = _mean_to_true_anomaly(target_M, target_e)
		var target_r = target_p / (1.0 + target_e * cos(target_nu_t))
		var target_angle = target_nu_t + target_omega
		var target_pos = Vector2(target_r * cos(target_angle), target_r * sin(target_angle))
		
		var dist = (ship_pos - target_pos).length()
		
		if dist < target_soi:
			t_high = t_mid  # Entry is before this point
		else:
			t_low = t_mid  # Entry is after this point
		
		if abs(t_high - t_low) < 0.05:
			break
	
	var t_entry = (t_low + t_high) / 2.0
	
	# Calculate final positions and velocities using proper orbital mechanics
	var ship_pos: Vector2
	var ship_vel: Vector2
	if ship_e < 1.0:
		var ship_M = ship_M0 + ship_n * t_entry
		var ship_nu_t = _mean_to_true_anomaly(ship_M, ship_e)
		var ship_r = ship_p / (1.0 + ship_e * cos(ship_nu_t)) if abs(1.0 + ship_e * cos(ship_nu_t)) > 0.001 else INF
		var ship_angle = ship_nu_t + ship_omega
		ship_pos = Vector2(ship_r * cos(ship_angle), ship_r * sin(ship_angle))
		
		# Calculate velocity using mu/h approach (preserves orbital direction)
		# h = sqrt(mu * p) with sign from orbital direction
		var ship_h = sqrt(ref_mu * ship_p) * sign(ship_n)
		if abs(ship_h) > 0.001:
			# v_r = (μ/h) * e * sin(ν)
			# v_t = (μ/h) * (1 + e*cos(ν))
			var v_r = (ref_mu / ship_h) * ship_e * sin(ship_nu_t)
			var v_t = (ref_mu / ship_h) * (1.0 + ship_e * cos(ship_nu_t))
			
			var radial_dir = Vector2(cos(ship_angle), sin(ship_angle))
			var tangent_dir = Vector2(-sin(ship_angle), cos(ship_angle))
			ship_vel = radial_dir * v_r + tangent_dir * v_t
		else:
			ship_vel = ship_rel_vel
	else:
		# Hyperbolic: linear approximation
		ship_pos = ship_rel_pos + ship_rel_vel * t_entry
		ship_vel = ship_rel_vel  # Constant velocity for linear approximation
	
	# Target position and velocity at t_entry
	var target_M = target_M0 + target_n * t_entry
	var target_nu_t = _mean_to_true_anomaly(target_M, target_e)
	var target_r = target_p / (1.0 + target_e * cos(target_nu_t))
	var target_angle = target_nu_t + target_omega
	var target_pos = Vector2(target_r * cos(target_angle), target_r * sin(target_angle))
	
	# Calculate target velocity using mu/h approach
	var target_h = sqrt(ref_mu * target_p) * sign(target_n)
	var target_vel: Vector2 = Vector2.ZERO
	if abs(target_h) > 0.001:
		var target_v_r = (ref_mu / target_h) * target_e * sin(target_nu_t)
		var target_v_t = (ref_mu / target_h) * (1.0 + target_e * cos(target_nu_t))
		
		var target_radial_dir = Vector2(cos(target_angle), sin(target_angle))
		var target_tangent_dir = Vector2(-sin(target_angle), cos(target_angle))
		target_vel = target_radial_dir * target_v_r + target_tangent_dir * target_v_t
	
	# Calculate world positions (static - captured at calculation time)
	var encounter_world_pos = ref_body_pos + ship_pos
	var rel_pos = ship_pos - target_pos  # Ship pos relative to target
	var rel_vel = ship_vel - target_vel  # Ship vel relative to target
	
	# CRITICAL: Normalize relative position to exactly the SOI boundary
	# This ensures the encounter point is precisely on the SOI edge
	var actual_distance = rel_pos.length()
	if actual_distance > 0.1:
		rel_pos = rel_pos.normalized() * target_soi
		# Adjust ship_pos to match the normalized entry point
		ship_pos = target_pos + rel_pos
		encounter_world_pos = ref_body_pos + ship_pos
	
	var target_center_world = encounter_world_pos - rel_pos
	
	return {
		"time": t_entry,
		"ship_pos": ship_pos,
		"ship_vel": ship_vel,
		"target_pos": target_pos,
		"target_vel": target_vel,
		"encounter_world_pos": encounter_world_pos,
		"target_center_world": target_center_world,
		"rel_pos": rel_pos,
		"rel_vel": rel_vel,
		"target_mu": target_mu
	}


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


# =============================================================================
# ANOMALY CONVERSION UTILITIES
# =============================================================================

## Convert true anomaly to mean anomaly (for elliptical orbits)
func _true_to_mean_anomaly(true_anomaly: float, eccentricity: float) -> float:
	var e = eccentricity
	var nu = true_anomaly
	
	# Eccentric anomaly: tan(E/2) = sqrt((1-e)/(1+e)) * tan(nu/2)
	var half_nu = nu / 2.0
	var tan_half_nu = tan(half_nu)
	var factor = sqrt((1.0 - e) / (1.0 + e)) if e < 1.0 else 1.0
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
	for i in range(10):
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
	var factor = sqrt((1.0 + e) / (1.0 - e)) if e < 1.0 else 1.0
	var tan_half_nu = factor * tan_half_E
	var nu = 2.0 * atan(tan_half_nu)
	
	return nu

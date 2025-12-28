# scripts/trajectory_visualization.gd
class_name TrajectoryVisualization
extends RefCounted

## Trajectory Visualization Manager
## Handles all trajectory drawing: Keplerian ellipses/hyperbolas, n-body perturbed paths, SOI encounters

# =============================================================================
# CONFIGURATION
# =============================================================================

var show_trajectory: bool = true
var show_perturbed_trajectory: bool = true
var gravitational_constant: float = 100.0
var trajectory_color: Color = Color(0.0, 1.0, 1.0, 0.5)
var trajectory_points: int = 100
var trajectory_prediction_time: float = 30.0
var parent_gravity_attenuation: float = 0.2
var marker_base_radius: float = 4.0  # Base radius for all markers (Pe, Ap, encounter, exit)

# =============================================================================
# STATE
# =============================================================================

var _cached_orbital_elements: OrbitalMechanics.OrbitalElements = null
var _orbit_needs_recalc: bool = true
var _cached_soi_encounter: Dictionary = {}
var _cached_soi_encounter_body: Node2D = null
var _cached_soi_encounter_soi: float = 0.0
var _cached_soi_encounter_timestamp: float = 0.0
var _nbody_trajectory: PackedVector2Array = []
var _nbody_trajectory_color: Color = Color(1.0, 1.0, 0.0, 0.7)
var _nbody_trajectory_ref_body: Node2D = null  # Track which body the trajectory is relative to
var _was_thrusting: bool = false  # Track previous thrust state to detect when thrust stops

# =============================================================================
# MAIN DRAW FUNCTION
# =============================================================================

## Mark orbit for recalculation (call when SOI changes or thrust changes)
func mark_for_recalculation() -> void:
	_orbit_needs_recalc = true
	_cached_soi_encounter = {}


## Main drawing entry point - called from ship's _draw()
func draw_trajectories(
	ship: Node2D,
	ship_position: Vector2,
	ship_velocity: Vector2,
	patched_conics_state,
	central_bodies: Array,
	is_thrusting: bool,
	gravity_mode: int,
	boundary_left: float,
	boundary_top: float,
	boundary_right: float,
	boundary_bottom: float
) -> void:
	if not show_trajectory:
		return
	
	# Detect thrust state changes
	var thrust_just_stopped = _was_thrusting and not is_thrusting
	
	# Only recalculate orbital elements when needed
	if _orbit_needs_recalc or is_thrusting or thrust_just_stopped:
		_update_orbital_elements(ship_position, ship_velocity, patched_conics_state)
		_orbit_needs_recalc = false
	
	if is_thrusting:
		_orbit_needs_recalc = true
	
	_was_thrusting = is_thrusting
	
	if _cached_orbital_elements != null and _cached_orbital_elements.is_valid:
		if _cached_orbital_elements.eccentricity < 1.0:
			_draw_trajectory_ellipse(ship, patched_conics_state)
		else:
			_draw_trajectory_hyperbola(ship, patched_conics_state)
	
	_draw_soi_encounter_predictions(ship, ship_position, ship_velocity, patched_conics_state, central_bodies)
	
	if show_perturbed_trajectory and gravity_mode == 1:  # HYBRID
		# Get current reference body
		var current_ref_body = patched_conics_state.reference_body if patched_conics_state else null
		if current_ref_body == null:
			current_ref_body = _find_closest_body(ship_position, central_bodies)
		
		# Recalculate if orbit changed, trajectory is empty, or reference body changed
		var ref_body_changed = current_ref_body != _nbody_trajectory_ref_body
		if _orbit_needs_recalc or _nbody_trajectory.is_empty() or ref_body_changed:
			_calculate_nbody_trajectory(ship_position, ship_velocity, patched_conics_state, central_bodies, boundary_left, boundary_top, boundary_right, boundary_bottom)
			_nbody_trajectory_ref_body = current_ref_body
		_draw_nbody_trajectory(ship, patched_conics_state, central_bodies)


## Update cached orbital elements
func _update_orbital_elements(ship_position: Vector2, ship_velocity: Vector2, patched_conics_state) -> void:
	var ref_body = patched_conics_state.reference_body if patched_conics_state else null
	if ref_body == null:
		_cached_orbital_elements = null
		return
	
	var rel_pos = OrbitalMechanics.get_relative_position(ship_position, ref_body)
	var rel_vel = OrbitalMechanics.get_relative_velocity(ship_velocity, ref_body)
	var mu = gravitational_constant * ref_body.mass
	
	_cached_orbital_elements = OrbitalMechanics.calculate_orbital_elements(rel_pos, rel_vel, mu)


## Draw elliptical trajectory
func _draw_trajectory_ellipse(ship: Node2D, patched_conics_state) -> void:
	if _cached_orbital_elements == null or not _cached_orbital_elements.is_valid:
		return
	
	var ref_body = patched_conics_state.reference_body
	if ref_body == null:
		return
	
	var elements = _cached_orbital_elements
	var ref_pos = ref_body.global_position
	var a = elements.semi_major_axis
	var e = elements.eccentricity
	var omega = elements.argument_of_periapsis
	
	if a <= 0 or not is_finite(a) or a > 20000.0:
		return
	
	var soi_radius = patched_conics_state.reference_soi
	var apoapsis = elements.apoapsis
	var exits_soi = apoapsis > soi_radius and e > 0.01
	
	var start_anomaly: float = 0.0
	var end_anomaly: float = TAU
	
	if exits_soi:
		var p = a * (1.0 - e * e)
		var cos_exit = (p / soi_radius - 1.0) / e
		cos_exit = clamp(cos_exit, -1.0, 1.0)
		var exit_anomaly = acos(cos_exit)
		start_anomaly = -exit_anomaly
		end_anomaly = exit_anomaly
	
	var draw_scale = _get_draw_scale(ship)
	var line_width = 3.0 * draw_scale
	var alpha = 0.7
	var orbit_color = Color(trajectory_color.r, trajectory_color.g, trajectory_color.b, alpha)
	
	var points: PackedVector2Array = []
	var num_points = trajectory_points
	
	# Adaptive sampling: distribute points based on radius (more points where r is larger)
	# First pass: calculate cumulative arc-length proxy (using radius as weight)
	var angle_range = end_anomaly - start_anomaly
	var cumulative_weights: PackedFloat32Array = [0.0]
	var total_weight = 0.0
	var temp_samples = 200  # Temporary high-res sampling to measure distribution
	
	for i in range(1, temp_samples + 1):
		var t = float(i) / float(temp_samples)
		var true_anomaly = start_anomaly + t * angle_range
		var p = a * (1.0 - e * e)
		var r = p / (1.0 + e * cos(true_anomaly))
		total_weight += r
		cumulative_weights.append(total_weight)
	
	# Second pass: sample at evenly-spaced cumulative weights
	for i in range(num_points + 1):
		var target_weight = (float(i) / float(num_points)) * total_weight
		
		# Find the segment containing target_weight
		var idx = temp_samples - 1  # Default to last segment
		for j in range(cumulative_weights.size() - 1):
			if target_weight >= cumulative_weights[j] and target_weight <= cumulative_weights[j + 1]:
				idx = j
				break
		
		# Clamp idx to valid range
		idx = clamp(idx, 0, temp_samples - 1)
		
		# Interpolate within the segment
		var t_interp = float(idx) / float(temp_samples)
		if idx < cumulative_weights.size() - 1:
			var weight_diff = cumulative_weights[idx + 1] - cumulative_weights[idx]
			if weight_diff > 0.0:
				var frac = (target_weight - cumulative_weights[idx]) / weight_diff
				t_interp = (float(idx) + frac) / float(temp_samples)
		
		var true_anomaly = start_anomaly + t_interp * angle_range
		var p = a * (1.0 - e * e)
		var r = p / (1.0 + e * cos(true_anomaly))
		var world_point = ref_pos + Vector2(r * cos(true_anomaly + omega), r * sin(true_anomaly + omega))
		points.append(ship.to_local(world_point))
	
	for i in range(num_points):
		ship.draw_line(points[i], points[i + 1], orbit_color, line_width)
	
	var periapsis_color = Color(1.0, 0.5, 0.3, 0.9)
	# Calculate periapsis distance using orbital mechanics formula: r = p / (1 + e)
	var semi_latus_rectum = a * (1.0 - e * e)
	var periapsis_distance = semi_latus_rectum / (1.0 + e)
	var periapsis_pos = ref_pos + Vector2(periapsis_distance, 0).rotated(omega)
	var periapsis_local = ship.to_local(periapsis_pos)
	var periapsis_dir = periapsis_local.normalized() if periapsis_local.length() > 1 else Vector2.RIGHT
	_draw_apsis_marker(ship, periapsis_local, periapsis_dir, periapsis_color, "Pe", draw_scale)
	
	if not exits_soi:
		var apoapsis_color = Color(0.3, 0.5, 1.0, 0.9)
		var apoapsis_pos = ref_pos + Vector2(-apoapsis, 0).rotated(omega)
		var apoapsis_local = ship.to_local(apoapsis_pos)
		var apoapsis_dir = apoapsis_local.normalized() if apoapsis_local.length() > 1 else Vector2.LEFT
		_draw_apsis_marker(ship, apoapsis_local, apoapsis_dir, apoapsis_color, "Ap", draw_scale)
	else:
		var exit_color = Color(1.0, 0.3, 0.3, 0.9)
		var p = a * (1.0 - e * e)
		var cos_exit = (p / soi_radius - 1.0) / e
		cos_exit = clamp(cos_exit, -1.0, 1.0)
		var exit_anomaly = acos(cos_exit)
		var exit_pos1 = ref_pos + Vector2(soi_radius * cos(exit_anomaly + omega), soi_radius * sin(exit_anomaly + omega))
		var exit_pos2 = ref_pos + Vector2(soi_radius * cos(-exit_anomaly + omega), soi_radius * sin(-exit_anomaly + omega))
		ship.draw_circle(ship.to_local(exit_pos1), marker_base_radius * draw_scale, exit_color)
		ship.draw_circle(ship.to_local(exit_pos2), marker_base_radius * draw_scale, exit_color)


## Draw hyperbolic trajectory
func _draw_trajectory_hyperbola(ship: Node2D, patched_conics_state) -> void:
	if _cached_orbital_elements == null or not _cached_orbital_elements.is_valid:
		return
	
	var ref_body = patched_conics_state.reference_body
	if ref_body == null:
		return
	
	var elements = _cached_orbital_elements
	var ref_pos = ref_body.global_position
	var a = elements.semi_major_axis
	var e = elements.eccentricity
	var omega = elements.argument_of_periapsis
	
	if not is_finite(a) or not is_finite(e):
		return
	
	var soi_radius = patched_conics_state.reference_soi
	var a_abs = abs(a)
	var p = a_abs * (e * e - 1.0)
	
	if p <= 0:
		return
	
	var cos_exit = (p / soi_radius - 1.0) / e
	cos_exit = clamp(cos_exit, -1.0, 1.0)
	var exit_anomaly = acos(cos_exit)
	var asymptote_limit = acos(-1.0 / e) if e > 1.0 else PI * 0.99
	var max_anomaly = min(exit_anomaly, asymptote_limit * 0.98)
	
	var rel_pos = ship.global_position - ref_pos
	var rel_vel = OrbitalMechanics.get_relative_velocity(ship.velocity, ref_body)
	
	var start_anomaly = -max_anomaly
	var end_anomaly = max_anomaly
	
	var draw_scale = _get_draw_scale(ship)
	var line_width = 3.0 * draw_scale
	var alpha = 0.7
	var orbit_color = Color(trajectory_color.r, trajectory_color.g, trajectory_color.b, alpha)
	
	var points: PackedVector2Array = []
	var num_points = trajectory_points
	
	for i in range(num_points + 1):
		var t = float(i) / float(num_points)
		var true_anomaly = start_anomaly + t * (end_anomaly - start_anomaly)
		var r = p / (1.0 + e * cos(true_anomaly))
		
		if r <= 0 or not is_finite(r):
			continue
		
		var world_point = ref_pos + Vector2(r * cos(true_anomaly + omega), r * sin(true_anomaly + omega))
		points.append(ship.to_local(world_point))
	
	for i in range(points.size() - 1):
		ship.draw_line(points[i], points[i + 1], orbit_color, line_width)
	
	var periapsis_color = Color(1.0, 0.5, 0.3, 0.9)
	# Calculate periapsis distance using orbital mechanics formula: r = p / (1 + e)
	var periapsis_distance = p / (1.0 + e)
	var periapsis_pos = ref_pos + Vector2(periapsis_distance, 0).rotated(omega)
	var periapsis_local = ship.to_local(periapsis_pos)
	var periapsis_dir = periapsis_local.normalized() if periapsis_local.length() > 1 else Vector2.RIGHT
	_draw_apsis_marker(ship, periapsis_local, periapsis_dir, periapsis_color, "Pe", draw_scale)
	
	var exit_color = Color(1.0, 0.3, 0.3, 0.9)
	var exit_pos1 = ref_pos + Vector2(soi_radius * cos(exit_anomaly + omega), soi_radius * sin(exit_anomaly + omega))
	var exit_pos2 = ref_pos + Vector2(soi_radius * cos(-exit_anomaly + omega), soi_radius * sin(-exit_anomaly + omega))
	ship.draw_circle(ship.to_local(exit_pos1), marker_base_radius * draw_scale, exit_color)
	ship.draw_circle(ship.to_local(exit_pos2), marker_base_radius * draw_scale, exit_color)


## Draw apsis marker
func _draw_apsis_marker(ship: Node2D, pos: Vector2, direction: Vector2, color: Color, label: String, draw_scale: float = 1.0) -> void:
	var marker_radius = marker_base_radius * draw_scale
	
	# Draw the point
	ship.draw_circle(pos, marker_radius, color)
	
	# Fixed 11 o'clock position for label (counter-rotate by ship rotation to keep screen-fixed)
	# 11 o'clock is roughly -45 degrees from vertical (-135 degrees from horizontal)
	var eleven_oclock = Vector2(-0.7071, -0.7071)  # Normalized diagonal up-left in screen space
	# Counter-rotate by negative ship rotation to keep it fixed on screen
	var screen_fixed_offset = eleven_oclock.rotated(-ship.rotation)
	var label_offset_dist = 25.0 * draw_scale
	var label_pos = pos + screen_fixed_offset * label_offset_dist
	
	ship.draw_set_transform(label_pos, -ship.rotation, Vector2(draw_scale, draw_scale))
	ship.draw_string(ThemeDB.fallback_font, Vector2(-8, 4), label, HORIZONTAL_ALIGNMENT_CENTER, -1, 14, color)
	ship.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)


## Draw SOI encounter predictions
func _draw_soi_encounter_predictions(ship: Node2D, ship_position: Vector2, ship_velocity: Vector2, patched_conics_state, central_bodies: Array) -> void:
	var ref_body = patched_conics_state.reference_body if patched_conics_state else null
	if ref_body == null or _cached_orbital_elements == null or not _cached_orbital_elements.is_valid:
		return
	
	var draw_scale = _get_draw_scale(ship)
	var should_recalc = _orbit_needs_recalc or _cached_soi_encounter.is_empty()
	
	for body in central_bodies:
		if body == null or body == ref_body:
			continue
		
		var body_orbits = body.orbits_around if "orbits_around" in body else null
		if body_orbits != ref_body:
			continue
		
		var body_mass = body.mass if "mass" in body else 0.0
		var body_soi = OrbitalMechanics.calculate_soi(body_mass, gravitational_constant)
		
		if not "get_orbital_elements" in body:
			continue
		var body_elements = body.get_orbital_elements()
		if body_elements == null or not body_elements.is_valid:
			continue
		
		var encounter: Dictionary
		if should_recalc or _cached_soi_encounter_body != body:
			encounter = _find_soi_encounter(ship, ship_position, ship_velocity, body, body_elements, body_soi, ref_body)
			if not encounter.is_empty():
				_cached_soi_encounter = encounter
				_cached_soi_encounter_body = body
				_cached_soi_encounter_soi = body_soi
				_cached_soi_encounter_timestamp = Time.get_ticks_msec() / 1000.0
			else:
				# Clear cached encounter if no encounter found
				_cached_soi_encounter = {}
				_cached_soi_encounter_body = null
		else:
			encounter = _cached_soi_encounter
		
		if encounter.is_empty():
			continue
		
		var ship_pos_rel: Vector2 = encounter["ship_pos"]
		var target_pos_rel: Vector2 = encounter["target_pos"]
		var encounter_world_pos = ref_body.global_position + ship_pos_rel
		var target_center_world = ref_body.global_position + target_pos_rel
		var encounter_local = ship.to_local(encounter_world_pos)
		
		var encounter_color = Color(0.3, 1.0, 0.5, 0.9)
		ship.draw_circle(encounter_local, marker_base_radius * draw_scale, encounter_color)
		
		_draw_encounter_hyperbola(ship, encounter, body_soi, target_center_world, draw_scale, encounter_color)
		
		var elapsed_time = (Time.get_ticks_msec() / 1000.0) - _cached_soi_encounter_timestamp
		var time_remaining = max(0.0, encounter["time"] - elapsed_time)
		# Fixed 11 o'clock position for time label (counter-rotate by ship rotation to keep screen-fixed)
		var eleven_oclock = Vector2(-0.7071, -0.7071)  # Normalized diagonal up-left in screen space
		# Counter-rotate by negative ship rotation to keep it fixed on screen
		var screen_fixed_offset = eleven_oclock.rotated(-ship.rotation)
		var label_pos = encounter_local + screen_fixed_offset * 20.0 * draw_scale
		var label_text = "%.0fs" % time_remaining
		
		ship.draw_set_transform(label_pos, -ship.rotation, Vector2(draw_scale, draw_scale))
		ship.draw_string(ThemeDB.fallback_font, Vector2(-12, 4), label_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 12, encounter_color)
		ship.draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)


## Find SOI encounter with moving body
func _find_soi_encounter(_ship: Node2D, ship_position: Vector2, ship_velocity: Vector2, target_body: Node2D, target_elements: OrbitalMechanics.OrbitalElements, target_soi: float, ref_body: Node2D) -> Dictionary:
	var max_time = 120.0
	var num_samples = 240
	var dt = max_time / num_samples
	
	if ref_body == null:
		return {}
	
	var ship_rel_pos = ship_position - ref_body.global_position
	var ship_rel_vel = ship_velocity - ref_body.velocity
	var mu = gravitational_constant * ref_body.mass
	var ship_elements = OrbitalMechanics.calculate_orbital_elements(ship_rel_pos, ship_rel_vel, mu)
	
	if ship_elements == null or not ship_elements.is_valid:
		return {}
	
	var ship_h = ship_rel_pos.x * ship_rel_vel.y - ship_rel_pos.y * ship_rel_vel.x
	var ship_direction = 1.0 if ship_h >= 0 else -1.0
	
	var target_rel_pos = target_body.global_position - ref_body.global_position
	var target_rel_vel = target_body.velocity - ref_body.velocity if "velocity" in target_body else Vector2.ZERO
	var target_h = target_rel_pos.x * target_rel_vel.y - target_rel_pos.y * target_rel_vel.x
	var target_direction = 1.0 if target_h >= 0 else -1.0
	
	var ship_a = ship_elements.semi_major_axis
	var ship_e = ship_elements.eccentricity
	var ship_omega = ship_elements.argument_of_periapsis
	var ship_nu = ship_elements.true_anomaly
	var ship_n = ship_elements.mean_motion * ship_direction
	
	var ship_p: float
	if ship_e < 1.0:
		ship_p = ship_a * (1.0 - ship_e * ship_e)
	else:
		ship_p = abs(ship_a) * (ship_e * ship_e - 1.0)
	
	var ship_M0 = _true_to_mean_anomaly(ship_nu, ship_e) if ship_e < 1.0 else 0.0
	
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
		
		var ship_pos: Vector2
		if ship_e < 1.0:
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
			ship_pos = ship_rel_pos + ship_rel_vel * t
		
		var target_M = target_M0 + target_n * t
		var target_nu_t = _mean_to_true_anomaly(target_M, target_e)
		var target_denom = 1.0 + target_e * cos(target_nu_t)
		if abs(target_denom) < 0.001:
			continue
		var target_r = target_p / target_denom
		var target_angle = target_nu_t + target_omega
		var target_pos = Vector2(target_r * cos(target_angle), target_r * sin(target_angle))
		
		var dist = (ship_pos - target_pos).length()
		var is_inside = dist < target_soi
		
		if is_inside and was_outside:
			var target_mass = target_body.mass if "mass" in target_body else 1.0
			var target_mu = gravitational_constant * target_mass
			var refined = _refine_soi_entry(
				t - dt, t, ship_M0, ship_n, ship_e, ship_p, ship_omega,
				target_M0, target_n, target_e, target_p, target_omega,
				target_soi, ship_rel_pos, ship_rel_vel, ref_body.global_position, target_mu, mu
			)
			return refined
		
		was_outside = not is_inside
	
	return {}


## Refine SOI entry point
func _refine_soi_entry(t_low: float, t_high: float, ship_M0: float, ship_n: float, ship_e: float, ship_p: float, ship_omega: float, target_M0: float, target_n: float, target_e: float, target_p: float, target_omega: float, target_soi: float, ship_rel_pos: Vector2, ship_rel_vel: Vector2, ref_body_pos: Vector2, target_mu: float, ref_mu: float) -> Dictionary:
	for _iter in range(15):
		var t_mid = (t_low + t_high) / 2.0
		
		var ship_pos: Vector2
		if ship_e < 1.0:
			var ship_M = ship_M0 + ship_n * t_mid
			var ship_nu_t = _mean_to_true_anomaly(ship_M, ship_e)
			var ship_r = ship_p / (1.0 + ship_e * cos(ship_nu_t)) if abs(1.0 + ship_e * cos(ship_nu_t)) > 0.001 else INF
			var ship_angle = ship_nu_t + ship_omega
			ship_pos = Vector2(ship_r * cos(ship_angle), ship_r * sin(ship_angle))
		else:
			ship_pos = ship_rel_pos + ship_rel_vel * t_mid
		
		var target_M = target_M0 + target_n * t_mid
		var target_nu_t = _mean_to_true_anomaly(target_M, target_e)
		var target_r = target_p / (1.0 + target_e * cos(target_nu_t))
		var target_angle = target_nu_t + target_omega
		var target_pos = Vector2(target_r * cos(target_angle), target_r * sin(target_angle))
		
		var dist = (ship_pos - target_pos).length()
		
		if dist < target_soi:
			t_high = t_mid
		else:
			t_low = t_mid
		
		if abs(t_high - t_low) < 0.05:
			break
	
	var t_entry = (t_low + t_high) / 2.0
	
	var ship_pos: Vector2
	var ship_vel: Vector2
	if ship_e < 1.0:
		var ship_M = ship_M0 + ship_n * t_entry
		var ship_nu_t = _mean_to_true_anomaly(ship_M, ship_e)
		var ship_r = ship_p / (1.0 + ship_e * cos(ship_nu_t)) if abs(1.0 + ship_e * cos(ship_nu_t)) > 0.001 else INF
		var ship_angle = ship_nu_t + ship_omega
		ship_pos = Vector2(ship_r * cos(ship_angle), ship_r * sin(ship_angle))
		
		var ship_h = sqrt(ref_mu * ship_p) * sign(ship_n)
		if abs(ship_h) > 0.001:
			var v_r = (ref_mu / ship_h) * ship_e * sin(ship_nu_t)
			var v_t = (ref_mu / ship_h) * (1.0 + ship_e * cos(ship_nu_t))
			var radial_dir = Vector2(cos(ship_angle), sin(ship_angle))
			var tangent_dir = Vector2(-sin(ship_angle), cos(ship_angle))
			ship_vel = radial_dir * v_r + tangent_dir * v_t
		else:
			ship_vel = ship_rel_vel
	else:
		ship_pos = ship_rel_pos + ship_rel_vel * t_entry
		ship_vel = ship_rel_vel
	
	var target_M = target_M0 + target_n * t_entry
	var target_nu_t = _mean_to_true_anomaly(target_M, target_e)
	var target_r = target_p / (1.0 + target_e * cos(target_nu_t))
	var target_angle = target_nu_t + target_omega
	var target_pos = Vector2(target_r * cos(target_angle), target_r * sin(target_angle))
	
	var target_h = sqrt(ref_mu * target_p) * sign(target_n)
	var target_vel: Vector2 = Vector2.ZERO
	if abs(target_h) > 0.001:
		var target_v_r = (ref_mu / target_h) * target_e * sin(target_nu_t)
		var target_v_t = (ref_mu / target_h) * (1.0 + target_e * cos(target_nu_t))
		var target_radial_dir = Vector2(cos(target_angle), sin(target_angle))
		var target_tangent_dir = Vector2(-sin(target_angle), cos(target_angle))
		target_vel = target_radial_dir * target_v_r + target_tangent_dir * target_v_t
	
	var encounter_world_pos = ref_body_pos + ship_pos
	var rel_pos = ship_pos - target_pos
	var rel_vel = ship_vel - target_vel
	
	var actual_distance = rel_pos.length()
	if actual_distance > 0.1:
		rel_pos = rel_pos.normalized() * target_soi
		ship_pos = target_pos + rel_pos
		encounter_world_pos = ref_body_pos + ship_pos
	
	var target_center_world = encounter_world_pos - rel_pos
	
	return {
		"time": t_entry, "ship_pos": ship_pos, "ship_vel": ship_vel,
		"target_pos": target_pos, "target_vel": target_vel,
		"encounter_world_pos": encounter_world_pos, "target_center_world": target_center_world,
		"rel_pos": rel_pos, "rel_vel": rel_vel, "target_mu": target_mu
	}


## Draw encounter hyperbola
func _draw_encounter_hyperbola(ship: Node2D, encounter: Dictionary, target_soi: float, target_center_world: Vector2, draw_scale: float, color: Color) -> void:
	if not ("rel_pos" in encounter and "rel_vel" in encounter and "target_mu" in encounter):
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
	
	var energy = (v * v / 2.0) - (mu / r)
	if abs(energy) < 0.0001:
		return
	
	var a = -mu / (2.0 * energy)
	var h = rel_pos.x * rel_vel.y - rel_pos.y * rel_vel.x
	var h_mag = abs(h)
	
	var v_sq = v * v
	var r_dot_v = rel_pos.dot(rel_vel)
	var e_vec = ((v_sq - mu / r) * rel_pos - r_dot_v * rel_vel) / mu
	var e = e_vec.length()
	
	if e < 0.01 or not is_finite(e):
		e = sqrt(max(0, 1.0 + 2.0 * energy * h_mag * h_mag / (mu * mu)))
	
	var omega = atan2(e_vec.y, e_vec.x) if e > 0.01 else 0.0
	
	var p: float
	if e < 1.0:
		p = abs(a) * (1.0 - e * e)
	else:
		p = abs(a) * (e * e - 1.0)
	
	if p <= 0 or not is_finite(p):
		return
	
	var cos_exit = (p / target_soi - 1.0) / e if e > 0.01 else 0.0
	cos_exit = clamp(cos_exit, -1.0, 1.0)
	var exit_anomaly = acos(cos_exit)
	var asymptote_limit = acos(-1.0 / e) if e > 1.0 else PI * 0.99
	var max_anomaly = min(exit_anomaly, asymptote_limit * 0.98)
	
	var direction = sign(h) if h != 0 else 1.0
	var points: PackedVector2Array = []
	var num_points = 64
	
	var start_anomaly: float
	var end_anomaly: float
	
	if direction >= 0:
		start_anomaly = -max_anomaly
		end_anomaly = max_anomaly
	else:
		start_anomaly = max_anomaly
		end_anomaly = -max_anomaly
	
	for i in range(num_points + 1):
		var t = float(i) / float(num_points)
		var true_anomaly = start_anomaly + t * (end_anomaly - start_anomaly)
		var denom = 1.0 + e * cos(true_anomaly)
		if abs(denom) < 0.01:
			continue
		var r_point = p / denom
		if r_point <= 0 or not is_finite(r_point):
			continue
		var angle = true_anomaly + omega
		var point_rel = Vector2(r_point * cos(angle), r_point * sin(angle))
		var point_world = target_center_world + point_rel
		points.append(ship.to_local(point_world))
	
	var hyperbola_color = Color(color.r, color.g, color.b, 0.6)
	var line_width = 3.0 * draw_scale
	
	for i in range(points.size() - 1):
		ship.draw_line(points[i], points[i + 1], hyperbola_color, line_width)
	
	var periapsis_dist = p / (1.0 + e) if e >= 0 else abs(a)
	var periapsis_world = target_center_world + Vector2(periapsis_dist, 0).rotated(omega)
	var periapsis_local = ship.to_local(periapsis_world)
	var target_local = ship.to_local(target_center_world)
	var pe_direction = (periapsis_local - target_local).normalized() if periapsis_local.distance_to(target_local) > 1 else Vector2.RIGHT
	
	var pe_color = Color(1.0, 0.6, 0.3, 0.9)
	# Use consistent marker style with main apsis markers
	_draw_apsis_marker(ship, periapsis_local, pe_direction, pe_color, "Pe", draw_scale)


## Calculate n-body trajectory
func _calculate_nbody_trajectory(ship_position: Vector2, ship_velocity: Vector2, patched_conics_state, central_bodies: Array, boundary_left: float, boundary_top: float, boundary_right: float, boundary_bottom: float) -> void:
	_nbody_trajectory.clear()
	
	if central_bodies.is_empty():
		return
	
	var sim_pos = ship_position
	var sim_vel = ship_velocity
	var time_step = trajectory_prediction_time / trajectory_points
	
	var ref_body = patched_conics_state.reference_body if patched_conics_state else null
	if ref_body == null:
		ref_body = _find_closest_body(ship_position, central_bodies)
	
	if ref_body == null:
		return
	
	var ref_pos = ref_body.global_position
	_nbody_trajectory.append(sim_pos - ref_pos)
	
	for i in range(trajectory_points):
		var soi_body = _get_soi_body_at_position(sim_pos, central_bodies)
		
		var attenuated_bodies: Array = []
		if soi_body != null and "orbits_around" in soi_body and soi_body.orbits_around != null:
			attenuated_bodies.append(soi_body.orbits_around)
			if "orbits_around" in soi_body.orbits_around and soi_body.orbits_around.orbits_around != null:
				attenuated_bodies.append(soi_body.orbits_around.orbits_around)
		
		if soi_body != null and "orbits_around" in soi_body and soi_body.orbits_around != null:
			var parent_body = soi_body.orbits_around
			var dir_to_parent = parent_body.global_position - soi_body.global_position
			var dist_to_parent = dir_to_parent.length()
			if dist_to_parent > 1.0:
				var parent_mass = parent_body.mass if "mass" in parent_body else 1.0
				var parent_accel = (gravitational_constant * parent_mass) / (dist_to_parent * dist_to_parent)
				sim_vel += dir_to_parent.normalized() * parent_accel * time_step
			
			if "orbits_around" in parent_body and parent_body.orbits_around != null:
				var grandparent_body = parent_body.orbits_around
				var dir_to_grandparent = grandparent_body.global_position - parent_body.global_position
				var dist_to_grandparent = dir_to_grandparent.length()
				if dist_to_grandparent > 1.0:
					var grandparent_mass = grandparent_body.mass if "mass" in grandparent_body else 1.0
					var grandparent_accel = (gravitational_constant * grandparent_mass) / (dist_to_grandparent * dist_to_grandparent)
					sim_vel += dir_to_grandparent.normalized() * grandparent_accel * time_step
		
		var total_accel = Vector2.ZERO
		for body in central_bodies:
			if body == null:
				continue
			
			var direction_to_center = body.global_position - sim_pos
			var distance = direction_to_center.length()
			
			if distance <= 1.0:
				continue
			
			var body_mass = body.mass if "mass" in body else 1.0
			var body_soi = OrbitalMechanics.calculate_soi(body_mass, gravitational_constant)
			
			if distance > body_soi:
				continue
			
			var gravitational_acceleration = (gravitational_constant * body_mass) / (distance * distance)
			
			if body in attenuated_bodies:
				gravitational_acceleration *= parent_gravity_attenuation
			
			total_accel += direction_to_center.normalized() * gravitational_acceleration
		
		sim_vel += total_accel * time_step
		sim_pos += sim_vel * time_step
		
		var collision = false
		for body in central_bodies:
			if body == null:
				continue
			var body_radius = 156.0
			if (body.global_position - sim_pos).length() < (body_radius + body_radius):
				collision = true
				break
		
		if collision:
			_nbody_trajectory.append(sim_pos - ref_pos)
			break
		
		if sim_pos.x < boundary_left or sim_pos.x > boundary_right or sim_pos.y < boundary_top or sim_pos.y > boundary_bottom:
			break
		
		_nbody_trajectory.append(sim_pos - ref_pos)


## Get SOI body at position
func _get_soi_body_at_position(pos: Vector2, central_bodies: Array) -> Node2D:
	var closest_soi_body: Node2D = null
	var smallest_soi: float = INF
	
	for body in central_bodies:
		if body == null:
			continue
		
		if not ("orbits_around" in body and body.orbits_around != null):
			continue
		
		var distance = (body.global_position - pos).length()
		var body_mass = body.mass if "mass" in body else 1.0
		var body_soi = OrbitalMechanics.calculate_soi(body_mass, gravitational_constant)
		
		if distance <= body_soi and body_soi < smallest_soi:
			smallest_soi = body_soi
			closest_soi_body = body
	
	return closest_soi_body


## Draw n-body trajectory
func _draw_nbody_trajectory(ship: Node2D, patched_conics_state, central_bodies: Array) -> void:
	if _nbody_trajectory.size() < 2:
		return
	
	var ref_body = patched_conics_state.reference_body if patched_conics_state else null
	if ref_body == null and not central_bodies.is_empty():
		ref_body = _find_closest_body(ship.global_position, central_bodies)
	
	if ref_body == null:
		return
	
	var ref_body_pos = ref_body.global_position
	var point_count = _nbody_trajectory.size()
	var draw_scale = _get_draw_scale(ship)
	var line_width = 3.0 * draw_scale
	var dash_length = 3
	var gap_length = 2
	var pattern_length = dash_length + gap_length
	
	for i in range(point_count - 1):
		var pattern_pos = i % pattern_length
		if pattern_pos >= dash_length:
			continue
		
		var world_start = _nbody_trajectory[i] + ref_body_pos
		var world_end = _nbody_trajectory[i + 1] + ref_body_pos
		var start_local = ship.to_local(world_start)
		var end_local = ship.to_local(world_end)
		
		var t = float(i) / float(point_count)
		var alpha = 0.9 - t * 0.2
		var color = Color(_nbody_trajectory_color.r, _nbody_trajectory_color.g, _nbody_trajectory_color.b, alpha)
		
		ship.draw_line(start_local, end_local, color, line_width)


## Find closest body
func _find_closest_body(position: Vector2, central_bodies: Array) -> Node2D:
	var closest_body: Node2D = null
	var min_distance: float = INF
	
	for body in central_bodies:
		if body == null:
			continue
		
		var distance = (body.global_position - position).length()
		if distance < min_distance:
			min_distance = distance
			closest_body = body
	
	return closest_body


## Get draw scale
func _get_draw_scale(_ship: Node2D) -> float:
	var camera = _ship.get_viewport().get_camera_2d()
	if camera != null:
		# Scale inversely with zoom: at zoom 1.0, scale is 1.0; at zoom 0.5, scale is 2.0
		return 1.0 / camera.zoom.x
	return 1.0


## Anomaly conversions
func _true_to_mean_anomaly(true_anomaly: float, eccentricity: float) -> float:
	var e = eccentricity
	var nu = true_anomaly
	var half_nu = nu / 2.0
	var tan_half_nu = tan(half_nu)
	var factor = sqrt((1.0 - e) / (1.0 + e)) if e < 1.0 else 1.0
	var tan_half_E = factor * tan_half_nu
	var E = 2.0 * atan(tan_half_E)
	var M = E - e * sin(E)
	return M


func _mean_to_true_anomaly(mean_anomaly: float, eccentricity: float) -> float:
	var M = fmod(mean_anomaly, TAU)
	if M < 0:
		M += TAU
	var e = eccentricity
	var E = M
	for i in range(10):
		var f = E - e * sin(E) - M
		var f_prime = 1.0 - e * cos(E)
		if abs(f_prime) < 1e-10:
			break
		E = E - f / f_prime
		if abs(f) < 1e-10:
			break
	var half_E = E / 2.0
	var tan_half_E = tan(half_E)
	var factor = sqrt((1.0 + e) / (1.0 - e)) if e < 1.0 else 1.0
	var tan_half_nu = factor * tan_half_E
	var nu = 2.0 * atan(tan_half_nu)
	return nu

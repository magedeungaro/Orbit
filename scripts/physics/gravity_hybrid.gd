class_name GravityHybrid
extends RefCounted

## Hybrid N-Body + Patched Conics Gravity Calculator
## All bodies within their SOI affect the ship, with parent body attenuation
## Provides more realistic multi-body perturbations while maintaining SOI hierarchy

var gravitational_constant: float
var parent_gravity_attenuation: float

func _init(g_constant: float = 500000.0, parent_attenuation: float = 0.05):
	gravitational_constant = g_constant
	parent_gravity_attenuation = parent_attenuation


## Apply gravity using hybrid n-body + patched conics approach
## All bodies within their SOI affect the ship, but parent bodies are attenuated when inside child SOI
func apply_gravity(
	ship_position: Vector2,
	ship_velocity: Vector2,
	patched_conics_state: OrbitalMechanics.PatchedConicsState,
	central_bodies: Array,
	delta: float
) -> Vector2:
	var soi_body = patched_conics_state.reference_body if patched_conics_state else null
	
	# Build list of bodies to attenuate (parent bodies when inside child's SOI)
	var attenuated_bodies: Array = []
	if soi_body != null and "orbits_around" in soi_body and soi_body.orbits_around != null:
		attenuated_bodies.append(soi_body.orbits_around)
		# Also attenuate grandparent if exists (for moons orbiting planets orbiting sun)
		if "orbits_around" in soi_body.orbits_around and soi_body.orbits_around.orbits_around != null:
			attenuated_bodies.append(soi_body.orbits_around.orbits_around)
	
	# When inside a moving planet's SOI, make the ship "ride along" with the planet
	# by applying the same acceleration the planet experiences from its parent
	# This creates a more accurate two-body problem in the planet's reference frame
	if soi_body != null and "orbits_around" in soi_body and soi_body.orbits_around != null:
		var parent_body = soi_body.orbits_around
		var dir_to_parent = parent_body.global_position - soi_body.global_position
		var dist_to_parent = dir_to_parent.length()
		if dist_to_parent > 1.0:
			var parent_mass = parent_body.mass if "mass" in parent_body else 1.0
			var parent_accel = (gravitational_constant * parent_mass) / (dist_to_parent * dist_to_parent)
			# Apply same acceleration to ship that SOI body experiences
			ship_velocity += dir_to_parent.normalized() * parent_accel * delta
		
		# If the parent also orbits something (grandparent), apply that acceleration too
		# This is needed for moons: ship must also experience the planet's acceleration toward the sun
		if "orbits_around" in parent_body and parent_body.orbits_around != null:
			var grandparent_body = parent_body.orbits_around
			var dir_to_grandparent = grandparent_body.global_position - parent_body.global_position
			var dist_to_grandparent = dir_to_grandparent.length()
			if dist_to_grandparent > 1.0:
				var grandparent_mass = grandparent_body.mass if "mass" in grandparent_body else 1.0
				var grandparent_accel = (gravitational_constant * grandparent_mass) / (dist_to_grandparent * dist_to_grandparent)
				# Apply same acceleration to ship that the parent experiences from grandparent
				ship_velocity += dir_to_grandparent.normalized() * grandparent_accel * delta
	
	# Apply gravity from all bodies (with attenuation for parent bodies)
	for body in central_bodies:
		if body == null:
			continue
		
		var direction_to_center = body.global_position - ship_position
		var distance = direction_to_center.length()
		
		if distance <= 1.0:
			continue
		
		# Calculate SOI for this body
		var body_mass = body.mass if "mass" in body else 1.0
		var body_soi = OrbitalMechanics.calculate_soi(body_mass, gravitational_constant)
		
		# Only apply gravity if within SOI
		if distance > body_soi:
			continue
		
		var gravitational_acceleration = (gravitational_constant * body_mass) / (distance * distance)
		
		# Attenuate parent body gravity when inside child's SOI
		if body in attenuated_bodies:
			gravitational_acceleration *= parent_gravity_attenuation
		
		ship_velocity += direction_to_center.normalized() * gravitational_acceleration * delta
	
	return ship_velocity


## Update the patched conics state - determines current SOI and reference body
## Same as patched conics, but used for SOI determination in hybrid mode
func update_soi_hierarchy(
	ship_position: Vector2,
	central_bodies: Array
) -> OrbitalMechanics.PatchedConicsState:
	return OrbitalMechanics.build_soi_hierarchy(
		ship_position,
		central_bodies,
		gravitational_constant
	)

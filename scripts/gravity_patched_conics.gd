class_name GravityPatchedConics
extends RefCounted

## Pure Patched Conics Gravity Calculator
## Only the reference body (determined by SOI hierarchy) affects the ship
## Implements true two-body problem within each SOI

var gravitational_constant: float

func _init(g_constant: float = 500000.0):
	gravitational_constant = g_constant


## Apply gravity using patched conics approximation
## Only the reference body's gravity affects the ship
func apply_gravity(
	ship_position: Vector2,
	ship_velocity: Vector2,
	patched_conics_state: OrbitalMechanics.PatchedConicsState,
	delta: float
) -> Vector2:
	return OrbitalMechanics.apply_patched_conic_gravity(
		ship_position,
		ship_velocity,
		patched_conics_state,
		delta,
		gravitational_constant
	)


## Update the patched conics state - determines current SOI and reference body
func update_soi_hierarchy(
	ship_position: Vector2,
	central_bodies: Array
) -> OrbitalMechanics.PatchedConicsState:
	return OrbitalMechanics.build_soi_hierarchy(
		ship_position,
		central_bodies,
		gravitational_constant
	)

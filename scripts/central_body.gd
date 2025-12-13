@tool
extends Area2D
class_name Planet
## Planet that exerts gravitational pull on the ship.
## Configure mass and appearance in the editor.
## The gravitational sphere of influence is shown in the editor for level design.
## Uses Area2D for trigger-based collision detection with the ship.
## Can orbit around other planets to create solar system-like configurations.

@export_group("Physics")
@export var mass: float = 20.0:
	set(value):
		mass = value
		queue_redraw()

@export_group("Orbital Motion")
## If true, this planet will not move (ignores orbital mechanics)
@export var is_static: bool = false
## The path to the planet this body orbits around (leave empty for stationary planets like the Sun)
@export var orbits_around_path: NodePath = NodePath("")
## Initial velocity of the planet (used if not auto-calculating orbital velocity)
@export var initial_velocity: Vector2 = Vector2.ZERO
## Automatically calculate orbital velocity based on distance to parent
@export var auto_orbital_velocity: bool = true
## Gravitational constant for orbital calculations
@export var orbital_gravitational_constant: float = 500000.0
## Direction of orbit: true = counter-clockwise, false = clockwise
@export var orbit_counter_clockwise: bool = true

## The resolved planet reference (set at runtime from orbits_around_path)
var orbits_around: Planet = null

@export_group("Target")
## If true, this is the planet the player must orbit to win
@export var is_target: bool = false:
	set(value):
		is_target = value
		queue_redraw()

@export_group("Editor Visualization")
## Show the sphere of influence in the editor
@export var show_soi_in_editor: bool = true:
	set(value):
		show_soi_in_editor = value
		queue_redraw()
## Color of the SOI circle in editor
@export var soi_color: Color = Color(0.3, 0.6, 1.0, 0.15):
	set(value):
		soi_color = value
		queue_redraw()
## Color of the SOI border in editor
@export var soi_border_color: Color = Color(0.3, 0.6, 1.0, 0.5):
	set(value):
		soi_border_color = value
		queue_redraw()
## Gravitational constant (should match ship's value)
@export var gravitational_constant: float = 500000.0:
	set(value):
		gravitational_constant = value
		queue_redraw()
## SOI multiplier: SOI = multiplier * sqrt(G * mass / 10000)
@export var soi_multiplier: float = 50.0:
	set(value):
		soi_multiplier = value
		queue_redraw()

## Current velocity of the planet (for orbital motion)
var velocity: Vector2 = Vector2.ZERO
## All other planets in the scene (for multi-body gravitational interactions)
var other_planets: Array = []


func _ready() -> void:
	queue_redraw()
	# Connect to body_entered signal for collision detection
	if not Engine.is_editor_hint():
		body_entered.connect(_on_body_entered)
		# Resolve the orbits_around_path to a Planet reference
		_resolve_orbit_parent()
		_initialize_orbit()
		# Find all other planets in the scene for gravitational interactions
		call_deferred("_find_other_planets")


func _resolve_orbit_parent() -> void:
	if orbits_around_path != NodePath(""):
		var node = get_node_or_null(orbits_around_path)
		if node is Planet:
			orbits_around = node
		else:
			push_warning("Planet '%s': orbits_around_path does not point to a valid Planet node" % name)


func _on_body_entered(body: Node2D) -> void:
	# Check if it's the ship (has the orbiting_body script)
	if body.has_method("trigger_explosion"):
		body.trigger_explosion(self)


func _find_other_planets() -> void:
	other_planets.clear()
	var root = get_tree().root
	other_planets = _find_all_planets(root)
	# Remove self from the list
	other_planets.erase(self)


func _find_all_planets(node: Node) -> Array:
	var result: Array = []
	if node is Planet:
		result.append(node)
	for child in node.get_children():
		result.append_array(_find_all_planets(child))
	return result


func _initialize_orbit() -> void:
	if orbits_around != null and auto_orbital_velocity:
		# Calculate circular orbital velocity
		var direction_to_parent = orbits_around.global_position - global_position
		var distance = direction_to_parent.length()
		
		if distance > 0:
			# v = sqrt(G * M / r) for circular orbit
			var orbital_speed = sqrt(orbital_gravitational_constant * orbits_around.mass / distance)
			
			# Calculate perpendicular direction for orbital velocity
			var perpendicular = direction_to_parent.normalized().rotated(PI / 2 if orbit_counter_clockwise else -PI / 2)
			velocity = perpendicular * orbital_speed
	else:
		velocity = initial_velocity


func _process(_delta: float) -> void:
	# Continuously redraw in editor to ensure visualization is updated
	if Engine.is_editor_hint():
		queue_redraw()


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	
	# Static planets don't move
	if is_static:
		return
	
	# Apply gravitational forces from all other planets
	_apply_gravity(delta)
	
	# Update position based on velocity
	if velocity.length() > 0:
		global_position += velocity * delta


func _apply_gravity(delta: float) -> void:
	# Apply gravity ONLY from parent body (two-body problem)
	# This keeps planetary orbits stable and predictable
	# The ship handles multi-body gravity with SOI-based attenuation separately
	if orbits_around != null:
		var direction_to_parent = orbits_around.global_position - global_position
		var distance = direction_to_parent.length()
		
		if distance > 1.0:
			var gravitational_acceleration = (orbital_gravitational_constant * orbits_around.mass) / (distance * distance)
			velocity += direction_to_parent.normalized() * gravitational_acceleration * delta
	
	# NOTE: n-body perturbations from other planets are disabled for stability
	# Each planet only orbits its designated parent, creating predictable orbital paths
	# The ship experiences all gravitational influences via its own physics system


func _draw() -> void:
	# Only draw in editor when show_soi_in_editor is enabled
	if not Engine.is_editor_hint():
		return
	
	if not show_soi_in_editor:
		return
	
	var soi = _calculate_soi()
	
	# Draw gradient SOI visualization - opacity increases with gravity strength (closer = stronger)
	# Gravity falls off with 1/r², so we use inverse square for opacity
	var num_rings = 20
	for i in range(num_rings, 0, -1):
		var ring_ratio = float(i) / float(num_rings)
		var ring_radius = soi * ring_ratio
		
		# Calculate opacity based on inverse square law (gravity strength)
		# At the edge (ring_ratio = 1), opacity is minimal
		# At the center (ring_ratio -> 0), opacity is maximal
		# Using 1/r² relationship but clamped for visual appeal
		var gravity_strength = 1.0 / (ring_ratio * ring_ratio) if ring_ratio > 0.1 else 100.0
		var normalized_strength = clamp(gravity_strength / 100.0, 0.02, 0.4)
		
		var ring_color = Color(soi_color.r, soi_color.g, soi_color.b, normalized_strength)
		draw_circle(Vector2.ZERO, ring_radius, ring_color)
	
	# Draw SOI border
	draw_arc(Vector2.ZERO, soi, 0, TAU, 64, soi_border_color, 2.0)
	
	# Draw target indicator if this is the target planet
	if is_target:
		var target_color = Color(0.0, 1.0, 0.3, 0.3)
		var target_border = Color(0.0, 1.0, 0.3, 0.8)
		draw_circle(Vector2.ZERO, soi * 0.1, target_color)
		draw_arc(Vector2.ZERO, soi * 0.1, 0, TAU, 32, target_border, 3.0)


func _calculate_soi() -> float:
	# SOI scales with sqrt(G * mass) - reflects how gravity falls off with 1/r²
	# At distance r where gravitational force equals a threshold, r ∝ sqrt(mass)
	return soi_multiplier * sqrt(gravitational_constant * mass / 10000.0)


## Calculate the orbital velocity needed for a circular orbit at a given distance from a parent body
static func calculate_orbital_velocity(parent_mass: float, distance: float, g_constant: float = 500000.0) -> float:
	if distance <= 0:
		return 0.0
	return sqrt(g_constant * parent_mass / distance)


## Get current orbital velocity magnitude
func get_orbital_speed() -> float:
	return velocity.length()


## Check if this planet is in a stable orbit
func is_orbiting() -> bool:
	return orbits_around != null and velocity.length() > 0
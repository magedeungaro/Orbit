extends Node2D
## OrbitalMechanics script that simulates two circular bodies with one orbiting the other
## The orbiting body's angular velocity can be controlled via input

# Central body properties
@export var central_body_radius: float = 50.0
@export var central_body_color: Color = Color.GRAY
@export var central_body_mass: float = 1000.0  # Mass of central body

# Orbiting body properties
@export var orbiting_body_radius: float = 25.0
@export var orbiting_body_color: Color = Color.GRAY
@export var orbiting_body_mass: float = 10.0  # Mass of orbiting body

# Orbital properties
@export var orbit_radius: float = 200.0  # Distance from center of central body to center of orbiting body
@export var initial_angular_velocity: float = 1.0  # radians per second
@export var angular_acceleration: float = 0.5  # How fast angular velocity changes with input
@export var gravitational_constant: float = 100.0  # Gravitational constant (scaled for game)
@export var enable_gravity: bool = true  # Toggle gravity simulation

# Internal state
var current_angle: float = 0.0  # Current angle in radians
var current_angular_velocity: float = 0.0  # Current angular velocity in radians per second
var central_body_position: Vector2
var orbiting_body_position: Vector2
var orbiting_body_velocity: Vector2 = Vector2.ZERO  # Velocity of orbiting body
var current_orbit_radius: float = 200.0  # Current distance from center (can change due to gravity)


func _ready() -> void:
	# Set initial angular velocity
	current_angular_velocity = initial_angular_velocity
	
	# Position the central body at the center of the viewport
	central_body_position = get_viewport_rect().size / 2.0
	
	# Initialize current orbit radius
	current_orbit_radius = orbit_radius
	
	# Initialize orbiting body position
	orbiting_body_position = central_body_position + Vector2(orbit_radius, 0)
	
	# Calculate initial tangential velocity for circular orbit
	calculate_orbital_velocity()
	
	print("Orbit Controller initialized with gravity")
	print("Central body mass: %.2f" % central_body_mass)
	print("Orbiting body mass: %.2f" % orbiting_body_mass)
	print("Controls: UP/DOWN arrows to increase/decrease angular velocity")
	print("Current angular velocity: %.2f rad/s" % current_angular_velocity)


func _process(delta: float) -> void:
	# Handle input for angular velocity control
	handle_input(delta)
	
	# Update orbit using gravity or angle-based system
	if enable_gravity:
		apply_gravity(delta)
	else:
		update_orbit(delta)
	
	# Update node positions
	update_node_positions()
	
	# Redraw the scene
	queue_redraw()


func calculate_orbital_velocity() -> void:
	# Calculate the velocity needed for a circular orbit
	# v = sqrt(G * M / r)
	if current_orbit_radius > 0:
		var orbital_speed = sqrt((gravitational_constant * central_body_mass) / current_orbit_radius)
		
		# Direction perpendicular to the radius vector (tangential)
		var direction = Vector2(
			cos(current_angle + PI/2),
			sin(current_angle + PI/2)
		)
		
		orbiting_body_velocity = direction * orbital_speed


func apply_gravity(delta: float) -> void:
	# Calculate gravitational force
	var distance_vector = central_body_position - orbiting_body_position
	var distance = distance_vector.length()
	
	if distance > 0:
		# F = G * m1 * m2 / r^2
		var force_magnitude = (gravitational_constant * central_body_mass * orbiting_body_mass) / (distance * distance)
		
		# Acceleration = F / m
		var acceleration = force_magnitude / orbiting_body_mass
		
		# Direction of acceleration (toward central body)
		var acceleration_vector = distance_vector.normalized() * acceleration
		
		# Update velocity
		orbiting_body_velocity += acceleration_vector * delta
		
		# Update position
		orbiting_body_position += orbiting_body_velocity * delta
		
		# Update angle and radius based on new position
		var relative_pos = orbiting_body_position - central_body_position
		current_orbit_radius = relative_pos.length()
		current_angle = atan2(relative_pos.y, relative_pos.x)


func handle_input(delta: float) -> void:
	if enable_gravity:
		# When gravity is enabled, adjust the velocity tangentially
		var tangent_direction = Vector2(
			cos(current_angle + PI/2),
			sin(current_angle + PI/2)
		)
		
		if Input.is_action_pressed("ui_up"):
			orbiting_body_velocity += tangent_direction * angular_acceleration * delta
		
		if Input.is_action_pressed("ui_down"):
			orbiting_body_velocity -= tangent_direction * angular_acceleration * delta
		
		if Input.is_action_just_pressed("ui_select"):
			calculate_orbital_velocity()
	else:
		# When gravity is disabled, adjust angular velocity
		if Input.is_action_pressed("ui_up"):
			current_angular_velocity += angular_acceleration * delta
		
		if Input.is_action_pressed("ui_down"):
			current_angular_velocity -= angular_acceleration * delta
		
		if Input.is_action_just_pressed("ui_select"):
			current_angular_velocity = initial_angular_velocity
			print("Angular velocity reset to: %.2f rad/s" % current_angular_velocity)


func update_orbit(delta: float) -> void:
	# Update the current angle based on angular velocity
	current_angle += current_angular_velocity * delta
	
	# Wrap angle to 0-2PI range to prevent overflow
	if current_angle > TAU:
		current_angle -= TAU
	elif current_angle < 0:
		current_angle += TAU
	
	# Calculate the position of the orbiting body using circular orbit formula
	# x = center_x + radius * cos(angle)
	# y = center_y + radius * sin(angle)
	orbiting_body_position = central_body_position + Vector2(
		cos(current_angle) * orbit_radius,
		sin(current_angle) * orbit_radius
	)


func update_node_positions() -> void:
	# Get references to the scene nodes
	var central_circle = get_node("CentralCircle")
	var orbiting_circle = get_node("OrbitingCircle")
	
	# Update central body position
	central_circle.position = central_body_position
	
	# Update orbiting body position
	orbiting_circle.position = orbiting_body_position


func _draw() -> void:
	# Draw orbit path (dark gray circle - for reference)
	draw_arc(central_body_position, orbit_radius, 0, TAU, 64, Color.GRAY, 1.0)
	
	# Draw line connecting central body to orbiting body
	draw_line(central_body_position, orbiting_body_position, Color.GRAY, 1.0)
	
	# Draw central body circle visualization
	draw_circle(central_body_position, central_body_radius, central_body_color)
	
	# Draw orbiting body circle visualization
	draw_circle(orbiting_body_position, orbiting_body_radius, orbiting_body_color)
	
	# Draw debug info
	draw_debug_info()


func draw_debug_info() -> void:
	# Build debug text based on gravity state
	var debug_text: String
	
	if enable_gravity:
		var velocity_magnitude = orbiting_body_velocity.length()
		debug_text = "GRAVITY MODE\nOrbit Radius: %.1f\nVelocity: %.2f\nAngle: %.1f°\nUP/DOWN to adjust velocity" % [
			current_orbit_radius,
			velocity_magnitude,
			current_angle * 180.0 / PI
		]
	else:
		debug_text = "ANGULAR MODE\nAngular Velocity: %.2f rad/s\nAngle: %.2f rad (%.1f deg)\nUP/DOWN arrows to control" % [
			current_angular_velocity,
			current_angle,
			current_angle * 180.0 / PI
		]
	
	# We'll use a label for debug info instead of draw_string (which is deprecated)
	var label_node: Label
	if not has_node("DebugLabel"):
		label_node = Label.new()
		label_node.name = "DebugLabel"
		add_child(label_node)
	else:
		label_node = get_node("DebugLabel")
	
	label_node.text = debug_text
	label_node.position = Vector2(10, 10)
	label_node.add_theme_font_size_override("font_size", 14)
	label_node.add_theme_color_override("font_color", Color.BLACK)

extends CharacterBody2D
## Physics-based orbit controller using Godot's built-in physics engine
## The orbiting body is controlled via arrow key thrust
## The central body exerts gravity on the orbiting body

@export var thrust_force: float = 200.0  # Force applied by thrust input
@export var gravitational_constant: float = 100000.0  # Gravitational constant
@export var gravity_adjustment_rate: float = 5000.0  # How much gravity changes per keystroke
@export var base_sphere_of_influence: float = 500.0  # Base radius of gravitational influence
@export var show_sphere_of_influence: bool = true  # Draw the sphere of influence
@export var mass: float = 10.0  # Mass of this body
@export var show_velocity_vector: bool = true  # Draw velocity vector
@export var bounce_coefficient: float = 0.8  # How much velocity is retained after bounce (0-1)
@export var body_radius: float = 15.0  # Radius of the body for collision detection
@export var show_orbit_trail: bool = true  # Draw the orbit trail
@export var orbit_trail_color: Color = Color.BLUE  # Color of the orbit trail
@export var trail_max_points: int = 500  # Maximum points to store for trail
@export var use_escape_velocity_thrust: bool = true  # Scale thrust to achieve escape velocity

var central_body: CharacterBody2D
var orbit_trail: PackedVector2Array = []  # Stores positions along the orbit
var trail_update_counter: int = 0  # Counter to sample every N frames


func _ready() -> void:
	# Get reference to central body
	central_body = get_parent().get_node("CentralBody")
	
	if central_body == null:
		print("Error: Could not find CentralBody node!")
	else:
		print("Orbiting body initialized")
		print("Controls:")
		print("  Arrow keys - Apply thrust")
		print("  W - Increase gravity")
		print("  S - Decrease gravity")


func _physics_process(delta: float) -> void:
	# Handle thrust input
	handle_thrust_input(delta)
	
	# Handle gravity control input
	handle_gravity_input()
	
	# Apply gravity from central body
	if central_body != null:
		apply_gravity_from_central_body(delta)
	
	# Move the body using velocity
	move_and_slide()
	
	# Handle bouncing off screen edges
	handle_screen_bounce()
	
	# Update orbit trail
	update_orbit_trail()
	
	# Queue redraw for debug visualization
	queue_redraw()


func handle_thrust_input(delta: float) -> void:
	# Get thrust direction from arrow keys
	var thrust_direction = Vector2.ZERO
	
	if Input.is_action_pressed("ui_right"):
		thrust_direction.x += 1
	if Input.is_action_pressed("ui_left"):
		thrust_direction.x -= 1
	if Input.is_action_pressed("ui_down"):
		thrust_direction.y += 1
	if Input.is_action_pressed("ui_up"):
		thrust_direction.y -= 1
	
	# Normalize to avoid faster diagonal movement
	if thrust_direction.length() > 0:
		thrust_direction = thrust_direction.normalized()
		# Debug: Print thrust direction and resulting velocity change
		var velocity_change = (thrust_direction * thrust_force) * delta
		print("Thrust: %s, Velocity change: %s, Current velocity: %s" % [thrust_direction, velocity_change, velocity])
	
	# Determine the effective thrust force
	var effective_thrust = thrust_force
	if use_escape_velocity_thrust:
		effective_thrust = calculate_escape_velocity_thrust()
	
	# Apply thrust directly to velocity
	# F = ma, so a = F/m, and v += a*dt
	velocity += (thrust_direction * effective_thrust) * delta


func handle_gravity_input() -> void:
	# Increase gravity with W key
	if Input.is_key_pressed(KEY_W):
		gravitational_constant += gravity_adjustment_rate * get_physics_process_delta_time()
		print("Gravity increased to: %.0f" % gravitational_constant)
	
	# Decrease gravity with S key
	if Input.is_key_pressed(KEY_S):
		gravitational_constant = max(0, gravitational_constant - gravity_adjustment_rate * get_physics_process_delta_time())
		print("Gravity decreased to: %.0f" % gravitational_constant)


func calculate_sphere_of_influence() -> float:
	# Sphere of influence increases with gravitational constant
	# Formula: SOI = base * sqrt(G_current / G_base)
	var base_gravity = 100000.0  # Reference gravity value
	var gravity_ratio = gravitational_constant / base_gravity
	return base_sphere_of_influence * sqrt(gravity_ratio)


func calculate_escape_velocity_thrust() -> float:
	# Calculate the required thrust to achieve escape velocity
	# Escape velocity: v_escape = sqrt(2 * G * M / r)
	# At current distance, calculate the required acceleration
	
	if central_body == null:
		return thrust_force
	
	var direction_to_center = central_body.global_position - global_position
	var distance = direction_to_center.length()
	
	if distance < 1.0:
		return thrust_force
	
	# Calculate escape velocity at current distance
	var escape_velocity = sqrt((2.0 * gravitational_constant * central_body.mass) / distance)
	
	# Calculate the thrust needed to reach escape velocity from current velocity
	# We want thrust that allows gradual acceleration toward escape velocity
	# Scaled so it takes about 5 seconds to reach escape velocity from rest
	var required_acceleration = escape_velocity / 5.0
	
	# Convert acceleration to thrust force: F = m * a
	return required_acceleration * mass


func calculate_current_escape_velocity() -> float:
	# Get the escape velocity at current position
	if central_body == null:
		return 0.0
	
	var direction_to_center = central_body.global_position - global_position
	var distance = direction_to_center.length()
	
	if distance < 1.0:
		return 0.0
	
	return sqrt((2.0 * gravitational_constant * central_body.mass) / distance)


func apply_gravity_from_central_body(delta: float) -> void:
	# Get direction and distance to central body
	var direction_to_center = central_body.global_position - global_position
	var distance = direction_to_center.length()
	
	# Calculate current sphere of influence
	var soi = calculate_sphere_of_influence()
	
	# Only apply gravity if within sphere of influence
	if distance > 1.0 and distance <= soi:  # Avoid division by zero and check SOI
		# Calculate gravitational acceleration: a = G * M / r^2
		var gravitational_acceleration = (gravitational_constant * central_body.mass) / (distance * distance)
		
		# Apply acceleration toward central body
		var gravity_acceleration = direction_to_center.normalized() * gravitational_acceleration
		velocity += gravity_acceleration * delta


func handle_screen_bounce() -> void:
	# Get viewport size
	var viewport_rect = get_viewport_rect()
	var viewport_width = viewport_rect.size.x
	var viewport_height = viewport_rect.size.y
	
	# Check left and right boundaries
	if global_position.x - body_radius < 0:
		global_position.x = body_radius
		velocity.x = abs(velocity.x) * bounce_coefficient
		print("Bounced off left wall")
	elif global_position.x + body_radius > viewport_width:
		global_position.x = viewport_width - body_radius
		velocity.x = -abs(velocity.x) * bounce_coefficient
		print("Bounced off right wall")
	
	# Check top and bottom boundaries
	if global_position.y - body_radius < 0:
		global_position.y = body_radius
		velocity.y = abs(velocity.y) * bounce_coefficient
		print("Bounced off top wall")
	elif global_position.y + body_radius > viewport_height:
		global_position.y = viewport_height - body_radius
		velocity.y = -abs(velocity.y) * bounce_coefficient
		print("Bounced off bottom wall")


func update_orbit_trail() -> void:
	# Update trail every few frames to reduce memory usage
	trail_update_counter += 1
	
	# Only add point every 2 frames
	if trail_update_counter >= 2:
		trail_update_counter = 0
		
		# Add current global position to trail
		orbit_trail.append(global_position)
		
		# Keep trail size limited
		if orbit_trail.size() > trail_max_points:
			orbit_trail.remove_at(0)


func _draw() -> void:
	if show_velocity_vector and velocity.length() > 0:
		# Draw velocity vector
		draw_line(Vector2.ZERO, velocity.normalized() * 50, Color.RED, 2.0)
		
		# Draw velocity magnitude text
		var speed_text = "Speed: %.1f" % velocity.length()
		
		# Get or create speed label
		var speed_label: Label
		if not has_node("SpeedLabel"):
			speed_label = Label.new()
			speed_label.name = "SpeedLabel"
			add_child(speed_label)
		else:
			speed_label = get_node("SpeedLabel")
		
		speed_label.text = speed_text
		speed_label.position = Vector2(10, -30)
		speed_label.add_theme_font_size_override("font_size", 12)
		speed_label.add_theme_color_override("font_color", Color.BLACK)
	
	# Display gravity info
	var soi = calculate_sphere_of_influence()
	var escape_vel = calculate_current_escape_velocity()
	var current_speed = velocity.length()
	var escape_percentage = (current_speed / escape_vel * 100.0) if escape_vel > 0 else 0.0
	var gravity_text = "Gravity: %.0f\nSOI: %.0f\nEscape V: %.1f (%.0f%%)\n(W/S to adjust)" % [gravitational_constant, soi, escape_vel, escape_percentage]
	var gravity_label: Label
	if not has_node("GravityLabel"):
		gravity_label = Label.new()
		gravity_label.name = "GravityLabel"
		add_child(gravity_label)
	else:
		gravity_label = get_node("GravityLabel")
	
	gravity_label.text = gravity_text
	gravity_label.position = Vector2(10, -60)
	gravity_label.add_theme_font_size_override("font_size", 12)
	gravity_label.add_theme_color_override("font_color", Color.BLACK)

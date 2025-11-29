extends Camera2D
## Camera that follows the orbiting body

@export var follow_speed: float = 0.1  # Smoothing factor for camera following (0-1, lower = smoother)
@export var zoom_level: float = 0.8  # Camera zoom level

var orbiting_body: CharacterBody2D


func _ready() -> void:
	# Get reference to orbiting body
	orbiting_body = get_parent().get_node("OrbitingBody")
	
	if orbiting_body == null:
		print("Error: Could not find OrbitingBody node!")
	else:
		print("Camera initialized - following orbiting body")
	
	# Set initial zoom
	zoom = Vector2(zoom_level, zoom_level)


func _process(_delta: float) -> void:
	if orbiting_body != null:
		# Smoothly follow the orbiting body
		var target_position = orbiting_body.global_position
		global_position = global_position.lerp(target_position, follow_speed)

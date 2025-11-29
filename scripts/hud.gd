extends CanvasLayer
## HUD that displays ship information in a fixed screen position

var orbiting_body: CharacterBody2D
var speed_label: Label
var info_label: Label


func _ready() -> void:
	# Get reference to orbiting body
	orbiting_body = get_tree().root.find_child("OrbitingBody", true, false)
	
	if orbiting_body == null:
		print("HUD Error: Could not find OrbitingBody node!")
		return
	
	print("HUD initialized - tracking orbiting body")
	
	# Create the UI container
	var margin = MarginContainer.new()
	margin.name = "MarginContainer"
	margin.set_anchors_preset(Control.PRESET_TOP_LEFT)
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 20)
	add_child(margin)
	
	# Create vertical container for labels
	var vbox = VBoxContainer.new()
	vbox.name = "VBoxContainer"
	margin.add_child(vbox)
	
	# Create speed label
	speed_label = Label.new()
	speed_label.name = "SpeedLabel"
	speed_label.add_theme_font_size_override("font_size", 16)
	speed_label.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(speed_label)
	
	# Create info label
	info_label = Label.new()
	info_label.name = "InfoLabel"
	info_label.add_theme_font_size_override("font_size", 14)
	info_label.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(info_label)
	
	# Add a panel background for readability
	var panel = Panel.new()
	panel.name = "BackgroundPanel"
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.modulate = Color(0, 0, 0, 0.5)
	# Insert panel behind the margin container
	move_child(margin, 1)
	add_child(panel)
	move_child(panel, 0)


func _process(_delta: float) -> void:
	if orbiting_body == null:
		return
	
	# Update speed display
	var current_speed = orbiting_body.velocity.length()
	speed_label.text = "Speed: %.1f" % current_speed
	
	# Get values from orbiting body
	var gravity = orbiting_body.gravitational_constant
	var soi = orbiting_body.calculate_sphere_of_influence()
	var escape_vel = orbiting_body.calculate_current_escape_velocity()
	var escape_percentage = (current_speed / escape_vel * 100.0) if escape_vel > 0 else 0.0
	var thrust_angle = orbiting_body.thrust_angle
	
	# Update info display
	info_label.text = "Gravity: %.0f | SOI: %.0f\nEscape V: %.1f (%.0f%%)\nThrust Angle: %.0f°\n\nControls:\nLEFT/RIGHT - Rotate\nSPACE - Thrust\nW/S - Adjust Gravity" % [
		gravity, soi, escape_vel, escape_percentage, thrust_angle
	]

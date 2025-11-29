extends CanvasLayer
## HUD that displays ship information in a fixed screen position

var orbiting_body: CharacterBody2D
var speed_label: Label
var info_label: Label
var fuel_label: Label
var fuel_bar: ProgressBar


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
	
	# Create fuel label
	fuel_label = Label.new()
	fuel_label.name = "FuelLabel"
	fuel_label.add_theme_font_size_override("font_size", 16)
	fuel_label.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(fuel_label)
	
	# Create fuel bar
	fuel_bar = ProgressBar.new()
	fuel_bar.name = "FuelBar"
	fuel_bar.custom_minimum_size = Vector2(200, 20)
	fuel_bar.max_value = 100
	fuel_bar.value = 100
	fuel_bar.show_percentage = false
	
	# Style the fuel bar
	var bar_style = StyleBoxFlat.new()
	bar_style.bg_color = Color(0.2, 0.2, 0.2, 0.8)
	bar_style.corner_radius_top_left = 3
	bar_style.corner_radius_top_right = 3
	bar_style.corner_radius_bottom_left = 3
	bar_style.corner_radius_bottom_right = 3
	fuel_bar.add_theme_stylebox_override("background", bar_style)
	
	var fill_style = StyleBoxFlat.new()
	fill_style.bg_color = Color(0.0, 0.8, 0.2, 1.0)  # Green when full
	fill_style.corner_radius_top_left = 3
	fill_style.corner_radius_top_right = 3
	fill_style.corner_radius_bottom_left = 3
	fill_style.corner_radius_bottom_right = 3
	fuel_bar.add_theme_stylebox_override("fill", fill_style)
	
	vbox.add_child(fuel_bar)
	
	# Add spacer
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	vbox.add_child(spacer)
	
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


func _process(_delta: float) -> void:
	if orbiting_body == null:
		return
	
	# Update fuel display
	var fuel_percent = orbiting_body.get_fuel_percentage()
	fuel_label.text = "FUEL: %.0f%%" % fuel_percent
	fuel_bar.value = fuel_percent
	
	# Change fuel bar color based on level
	var fill_style = fuel_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if fill_style:
		if fuel_percent > 50:
			fill_style.bg_color = Color(0.0, 0.8, 0.2, 1.0)  # Green
		elif fuel_percent > 25:
			fill_style.bg_color = Color(1.0, 0.8, 0.0, 1.0)  # Yellow
		else:
			fill_style.bg_color = Color(1.0, 0.2, 0.2, 1.0)  # Red
	
	# Update speed display
	var current_speed = orbiting_body.velocity.length()
	speed_label.text = "Speed: %.1f" % current_speed
	
	# Get values from orbiting body
	var escape_vel = orbiting_body.calculate_current_escape_velocity()
	var escape_percentage = (current_speed / escape_vel * 100.0) if escape_vel > 0 else 0.0
	var thrust_angle = orbiting_body.thrust_angle
	
	# Update info display
	info_label.text = "Escape V: %.1f (%.0f%%)\nThrust Angle: %.0f°\n\nControls:\nLEFT/RIGHT - Rotate\nSPACE - Thrust" % [
		escape_vel, escape_percentage, thrust_angle
	]

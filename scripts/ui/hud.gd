extends CanvasLayer

var orbiting_body: CharacterBody2D
var speed_label: Label
var relative_speed_label: Label
var reference_body_label: Label
var info_label: Label
var fuel_label: Label
var fuel_bar: ProgressBar
var goal_indicator: Control
var target_body: Node2D = null
var camera: Camera2D = null

var audiowide_font: Font


func _ready() -> void:
	audiowide_font = load("res://Assets/fonts/Audiowide/Audiowide-Regular.ttf")
	_create_ui()


## Update the ship reference (called when ship is replaced)
func set_ship(ship: CharacterBody2D) -> void:
	orbiting_body = ship
	if orbiting_body:
		target_body = orbiting_body.target_body
	else:
		target_body = null


func _create_ui() -> void:
	var margin = MarginContainer.new()
	margin.name = "MarginContainer"
	margin.set_anchors_preset(Control.PRESET_TOP_LEFT)
	margin.add_theme_constant_override("margin_left", 30)
	margin.add_theme_constant_override("margin_top", 30)
	add_child(margin)
	
	var vbox = VBoxContainer.new()
	vbox.name = "VBoxContainer"
	# Set a fixed minimum width to prevent resizing when numbers change
	vbox.custom_minimum_size = Vector2(300, 0)
	margin.add_child(vbox)
	
	fuel_label = Label.new()
	fuel_label.name = "FuelLabel"
	fuel_label.add_theme_font_override("font", audiowide_font)
	fuel_label.add_theme_font_size_override("font_size", 24)
	fuel_label.add_theme_color_override("font_color", Color.WHITE)
	fuel_label.custom_minimum_size = Vector2(280, 0)
	vbox.add_child(fuel_label)
	
	fuel_bar = ProgressBar.new()
	fuel_bar.name = "FuelBar"
	fuel_bar.custom_minimum_size = Vector2(280, 28)
	fuel_bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	fuel_bar.max_value = 100
	fuel_bar.value = 100
	fuel_bar.show_percentage = false
	
	var bar_style = StyleBoxFlat.new()
	bar_style.bg_color = Color(0.2, 0.2, 0.2, 0.8)
	bar_style.corner_radius_top_left = 3
	bar_style.corner_radius_top_right = 3
	bar_style.corner_radius_bottom_left = 3
	bar_style.corner_radius_bottom_right = 3
	fuel_bar.add_theme_stylebox_override("background", bar_style)
	
	var fill_style = StyleBoxFlat.new()
	fill_style.bg_color = Color(0.0, 0.8, 0.2, 1.0)
	fill_style.corner_radius_top_left = 3
	fill_style.corner_radius_top_right = 3
	fill_style.corner_radius_bottom_left = 3
	fill_style.corner_radius_bottom_right = 3
	fuel_bar.add_theme_stylebox_override("fill", fill_style)
	vbox.add_child(fuel_bar)
	
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 15)
	vbox.add_child(spacer)
	
	speed_label = Label.new()
	speed_label.name = "SpeedLabel"
	speed_label.add_theme_font_override("font", audiowide_font)
	speed_label.add_theme_font_size_override("font_size", 24)
	speed_label.add_theme_color_override("font_color", Color.WHITE)
	speed_label.custom_minimum_size = Vector2(280, 0)
	vbox.add_child(speed_label)
	
	relative_speed_label = Label.new()
	relative_speed_label.name = "RelativeSpeedLabel"
	relative_speed_label.add_theme_font_override("font", audiowide_font)
	relative_speed_label.add_theme_font_size_override("font_size", 24)
	relative_speed_label.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0))
	relative_speed_label.custom_minimum_size = Vector2(280, 0)
	vbox.add_child(relative_speed_label)
	
	reference_body_label = Label.new()
	reference_body_label.name = "ReferenceBodyLabel"
	reference_body_label.add_theme_font_override("font", audiowide_font)
	reference_body_label.add_theme_font_size_override("font_size", 20)
	reference_body_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	reference_body_label.custom_minimum_size = Vector2(280, 0)
	vbox.add_child(reference_body_label)
	
	info_label = Label.new()
	info_label.name = "InfoLabel"
	info_label.add_theme_font_override("font", audiowide_font)
	info_label.add_theme_font_size_override("font_size", 20)
	info_label.add_theme_color_override("font_color", Color.WHITE)
	info_label.custom_minimum_size = Vector2(280, 0)
	vbox.add_child(info_label)
	
	goal_indicator = GoalIndicator.new()
	goal_indicator.name = "GoalIndicator"
	goal_indicator.set_anchors_preset(Control.PRESET_FULL_RECT)
	goal_indicator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	goal_indicator.hud = self
	add_child(goal_indicator)


func _process(_delta: float) -> void:
	if orbiting_body == null or fuel_label == null:
		return
	
	var fuel_percent = orbiting_body.get_fuel_percentage()
	fuel_label.text = "FUEL: %.0f%%" % fuel_percent
	fuel_bar.value = fuel_percent
	
	var fill_style = fuel_bar.get_theme_stylebox("fill") as StyleBoxFlat
	if fill_style:
		if fuel_percent > 50:
			fill_style.bg_color = Color(0.0, 0.8, 0.2, 1.0)
		elif fuel_percent > 25:
			fill_style.bg_color = Color(1.0, 0.8, 0.0, 1.0)
		else:
			fill_style.bg_color = Color(1.0, 0.2, 0.2, 1.0)
	
	var current_speed = orbiting_body.velocity.length()
	speed_label.text = "Speed: %.1f" % current_speed
	
	# Calculate and display relative velocity and reference body
	var ref_body = orbiting_body._cached_orbit_ref_body
	var relative_velocity = orbiting_body.velocity
	var ref_body_name = "None"
	
	if ref_body != null:
		ref_body_name = ref_body.name
		if "velocity" in ref_body:
			relative_velocity = orbiting_body.velocity - ref_body.velocity
	
	relative_speed_label.text = "Relative Speed: %.1f" % relative_velocity.length()
	reference_body_label.text = "Reference: %s" % ref_body_name
	
	var thrust_angle = orbiting_body.thrust_angle
	var orientation_mode = orbiting_body.get_orientation_lock_name()
	
	info_label.text = "Thrust Angle: %.0f°\nOrientation: %s" % [
		thrust_angle, orientation_mode
	]
	
	if target_body == null and orbiting_body.target_body != null:
		target_body = orbiting_body.target_body
	
	if goal_indicator:
		goal_indicator.queue_redraw()


class GoalIndicator extends Control:
	var hud: CanvasLayer
	
	func _draw() -> void:
		if hud == null or hud.orbiting_body == null or hud.target_body == null:
			return
		
		var viewport_size = get_viewport_rect().size
		var screen_center = viewport_size / 2
		
		var ship_pos = hud.orbiting_body.global_position
		var target_pos = hud.target_body.global_position
		var to_target = target_pos - ship_pos
		var direction = to_target.normalized()
		
		var camera = hud.camera
		if camera == null:
			return
		
		var camera_pos = camera.global_position
		var zoom = camera.zoom
		var half_size = viewport_size / (2.0 * zoom)
		
		var target_relative = target_pos - camera_pos
		var is_on_screen = abs(target_relative.x) < half_size.x and abs(target_relative.y) < half_size.y
		
		var arrow_color = Color(0.3, 1.0, 0.5, 0.9)
		
		if is_on_screen:
			# Draw small arrow pointing to target center
			var screen_pos = screen_center + (target_relative * zoom)
			var arrow_length = 25.0
			var arrow_head_size = 8.0
			
			# Get planet radius from collision shape
			var planet_radius = 156.0  # Default
			for child in hud.target_body.get_children():
				if child is CollisionShape2D and child.shape is CircleShape2D:
					planet_radius = child.shape.radius
					break
			
			# Convert planet radius to screen space and add small gap
			var screen_radius = planet_radius * zoom.x
			var gap = 10.0  # Small gap between planet edge and arrow
			var offset_from_center = screen_radius + gap + arrow_length
			
			# Arrow points toward the planet center, starting from outside the planet
			var arrow_start = screen_pos - direction * offset_from_center
			var arrow_tip = screen_pos - direction * (screen_radius + gap)
			
			draw_line(arrow_start, arrow_tip, arrow_color, 2.0)
			
			var perp = Vector2(-direction.y, direction.x)
			var head_left = arrow_tip - direction * arrow_head_size + perp * (arrow_head_size * 0.5)
			var head_right = arrow_tip - direction * arrow_head_size - perp * (arrow_head_size * 0.5)
			var arrow_head = PackedVector2Array([arrow_tip, head_left, head_right])
			draw_colored_polygon(arrow_head, arrow_color)
		else:
			# Draw arrow on screen edge pointing to off-screen target
			var margin = 60.0
			
			var arrow_pos = screen_center
			var screen_bounds = Rect2(
				Vector2(margin, margin),
				viewport_size - Vector2(margin * 2, margin * 2)
			)
			
			var t_min = INF
			
			if direction.x > 0:
				var t = (screen_bounds.end.x - screen_center.x) / direction.x
				if t > 0 and t < t_min:
					var y = screen_center.y + direction.y * t
					if y >= screen_bounds.position.y and y <= screen_bounds.end.y:
						t_min = t
						arrow_pos = Vector2(screen_bounds.end.x, y)
			if direction.x < 0:
				var t = (screen_bounds.position.x - screen_center.x) / direction.x
				if t > 0 and t < t_min:
					var y = screen_center.y + direction.y * t
					if y >= screen_bounds.position.y and y <= screen_bounds.end.y:
						t_min = t
						arrow_pos = Vector2(screen_bounds.position.x, y)
			if direction.y > 0:
				var t = (screen_bounds.end.y - screen_center.y) / direction.y
				if t > 0 and t < t_min:
					var x = screen_center.x + direction.x * t
					if x >= screen_bounds.position.x and x <= screen_bounds.end.x:
						t_min = t
						arrow_pos = Vector2(x, screen_bounds.end.y)
			if direction.y < 0:
				var t = (screen_bounds.position.y - screen_center.y) / direction.y
				if t > 0 and t < t_min:
					var x = screen_center.x + direction.x * t
					if x >= screen_bounds.position.x and x <= screen_bounds.end.x:
						t_min = t
						arrow_pos = Vector2(x, screen_bounds.position.y)
			
			var arrow_size = 25.0
			var arrow_head_size = 15.0
			
			var arrow_base = arrow_pos - direction * arrow_size
			draw_line(arrow_base, arrow_pos, arrow_color, 4.0)
			
			var perp = Vector2(-direction.y, direction.x)
			var head_left = arrow_pos - direction * arrow_head_size + perp * (arrow_head_size * 0.6)
			var head_right = arrow_pos - direction * arrow_head_size - perp * (arrow_head_size * 0.6)
			var arrow_head = PackedVector2Array([arrow_pos, head_left, head_right])
			draw_colored_polygon(arrow_head, arrow_color)

extends CanvasLayer

var orbiting_body: CharacterBody2D
var speed_label: Label
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
	margin.add_child(vbox)
	
	fuel_label = Label.new()
	fuel_label.name = "FuelLabel"
	fuel_label.add_theme_font_override("font", audiowide_font)
	fuel_label.add_theme_font_size_override("font_size", 24)
	fuel_label.add_theme_color_override("font_color", Color.WHITE)
	vbox.add_child(fuel_label)
	
	fuel_bar = ProgressBar.new()
	fuel_bar.name = "FuelBar"
	fuel_bar.custom_minimum_size = Vector2(280, 28)
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
	vbox.add_child(speed_label)
	
	info_label = Label.new()
	info_label.name = "InfoLabel"
	info_label.add_theme_font_override("font", audiowide_font)
	info_label.add_theme_font_size_override("font_size", 20)
	info_label.add_theme_color_override("font_color", Color.WHITE)
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
		var distance = to_target.length()
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
		var margin = 60.0
		
		if is_on_screen:
			var screen_pos = screen_center + (target_relative * zoom)
			draw_arc(screen_pos, 40, 0, TAU, 32, arrow_color, 3.0)
			var dist_text = "%.0f" % distance
			draw_string(ThemeDB.fallback_font, screen_pos + Vector2(-20, -50), dist_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 16, arrow_color)
			draw_string(ThemeDB.fallback_font, screen_pos + Vector2(-30, -35), "GOAL", HORIZONTAL_ALIGNMENT_CENTER, -1, 14, arrow_color)
		else:
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
			
			var text_offset = -direction * 45
			var dist_text = "%.0f" % distance
			draw_string(ThemeDB.fallback_font, arrow_base + text_offset + Vector2(-15, 5), dist_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 14, arrow_color)

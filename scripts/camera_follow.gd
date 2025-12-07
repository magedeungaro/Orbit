extends Camera2D

@export var follow_speed: float = 0.1
@export var zoom_level: float = 0.8
@export var min_zoom: float = 0.3
@export var max_zoom: float = 2.0
@export var zoom_speed: float = 0.3
@export var pinch_zoom_sensitivity: float = 0.01

var orbiting_body: CharacterBody2D
var touch_points: Dictionary = {}
var initial_pinch_distance: float = 0.0
var initial_zoom: float = 0.0


func _ready() -> void:
	orbiting_body = get_tree().root.find_child("Ship", true, false)
	zoom = Vector2(zoom_level, zoom_level)


func _process(delta: float) -> void:
	if orbiting_body != null:
		var target_position = orbiting_body.global_position
		global_position = global_position.lerp(target_position, follow_speed)
	
	_handle_keyboard_zoom(delta)


func _input(event: InputEvent) -> void:
	_handle_mouse_wheel_zoom(event)
	_handle_pinch_zoom(event)


func _handle_keyboard_zoom(delta: float) -> void:
	if Input.is_action_pressed("zoom_in"):
		adjust_zoom(zoom_speed * delta * 3.0)
	if Input.is_action_pressed("zoom_out"):
		adjust_zoom(-zoom_speed * delta * 3.0)


func _handle_mouse_wheel_zoom(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			adjust_zoom(zoom_speed)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			adjust_zoom(-zoom_speed)


func _handle_pinch_zoom(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			touch_points[event.index] = event.position
			if touch_points.size() == 2:
				var points = touch_points.values()
				initial_pinch_distance = points[0].distance_to(points[1])
				initial_zoom = zoom.x
		else:
			touch_points.erase(event.index)
	
	elif event is InputEventScreenDrag:
		touch_points[event.index] = event.position
		if touch_points.size() == 2:
			var points = touch_points.values()
			var current_distance = points[0].distance_to(points[1])
			if initial_pinch_distance > 0:
				var zoom_factor = current_distance / initial_pinch_distance
				var new_zoom = clampf(initial_zoom * zoom_factor, min_zoom, max_zoom)
				zoom = Vector2(new_zoom, new_zoom)
				
				if Events:
					Events.camera_zoom_changed.emit(new_zoom)


func adjust_zoom(amount: float) -> void:
	var new_zoom = clampf(zoom.x + amount, min_zoom, max_zoom)
	zoom = Vector2(new_zoom, new_zoom)
	
	if Events:
		Events.camera_zoom_changed.emit(new_zoom)

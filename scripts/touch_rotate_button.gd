extends TextureButton

@export var action_name: String = "rotate_left"

var tracked_touches: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	
	if event is InputEventScreenTouch:
		var touch_event = event as InputEventScreenTouch
		if touch_event.pressed:
			if _is_point_inside(touch_event.position):
				tracked_touches[touch_event.index] = true
				Input.action_press(action_name)
		else:
			if tracked_touches.has(touch_event.index):
				tracked_touches.erase(touch_event.index)
				if tracked_touches.is_empty():
					Input.action_release(action_name)
	
	elif event is InputEventScreenDrag:
		var drag_event = event as InputEventScreenDrag
		var was_inside = tracked_touches.has(drag_event.index)
		var is_inside = _is_point_inside(drag_event.position)
		
		if is_inside and not was_inside:
			tracked_touches[drag_event.index] = true
			Input.action_press(action_name)
		elif not is_inside and was_inside:
			tracked_touches.erase(drag_event.index)
			if tracked_touches.is_empty():
				Input.action_release(action_name)


func _is_point_inside(point: Vector2) -> bool:
	return get_global_rect().has_point(point)


func _exit_tree() -> void:
	if not tracked_touches.is_empty():
		Input.action_release(action_name)
		tracked_touches.clear()

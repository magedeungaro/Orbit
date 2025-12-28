extends TextureButton

@export var action_name: String = "toggle_prograde"
@export var active_modulate: Color = Color(0.5, 1.0, 0.5, 1.0)
@export var inactive_modulate: Color = Color(1.0, 1.0, 1.0, 1.0)

var is_active: bool = false
var was_pressed: bool = false
var orbiting_body: CharacterBody2D = null


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	update_visual_state()
	
	await get_tree().process_frame
	orbiting_body = get_tree().root.find_child("Ship", true, false)
	if orbiting_body and orbiting_body.has_signal("orientation_lock_changed"):
		orbiting_body.connect("orientation_lock_changed", _on_orientation_lock_changed)


func _on_orientation_lock_changed(lock_type: int) -> void:
	if action_name == "toggle_prograde":
		is_active = (lock_type == 1)
	elif action_name == "toggle_retrograde":
		is_active = (lock_type == 2)
	update_visual_state()


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return
	
	if event is InputEventScreenTouch:
		var touch_event = event as InputEventScreenTouch
		if touch_event.pressed:
			if _is_point_inside(touch_event.position):
				if not was_pressed:
					was_pressed = true
					Input.action_press(action_name)
					Input.action_release(action_name)
		else:
			if was_pressed:
				was_pressed = false


func _is_point_inside(point: Vector2) -> bool:
	var local_point = get_global_transform().affine_inverse() * point
	var rect = Rect2(Vector2.ZERO, size)
	return rect.has_point(local_point)


func set_active(active: bool) -> void:
	is_active = active
	update_visual_state()


func update_visual_state() -> void:
	modulate = active_modulate if is_active else inactive_modulate

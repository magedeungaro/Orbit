extends TextureButton
## Touch button that toggles an action on press (single press toggle)
## Used for prograde/retrograde lock buttons

@export var action_name: String = "toggle_prograde"
@export var active_modulate: Color = Color(0.5, 1.0, 0.5, 1.0)  # Green tint when active
@export var inactive_modulate: Color = Color(1.0, 1.0, 1.0, 1.0)  # Normal color when inactive

var is_active: bool = false
var was_pressed: bool = false
var orbiting_body: CharacterBody2D = null


func _ready() -> void:
	# Allow other controls to receive input
	mouse_filter = Control.MOUSE_FILTER_PASS
	update_visual_state()
	
	# Find orbiting body and connect to its signal
	await get_tree().process_frame  # Wait for scene to be ready
	orbiting_body = get_tree().root.find_child("OrbitingBody", true, false)
	if orbiting_body and orbiting_body.has_signal("orientation_lock_changed"):
		orbiting_body.connect("orientation_lock_changed", _on_orientation_lock_changed)


func _on_orientation_lock_changed(lock_type: int) -> void:
	# Update button state based on the orientation lock
	# lock_type: 0 = NONE, 1 = PROGRADE, 2 = RETROGRADE
	if action_name == "toggle_prograde":
		is_active = (lock_type == 1)
	elif action_name == "toggle_retrograde":
		is_active = (lock_type == 2)
	update_visual_state()


func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch_event = event as InputEventScreenTouch
		if touch_event.pressed:
			# Check if touch is within this button's area
			if _is_point_inside(touch_event.position):
				if not was_pressed:
					was_pressed = true
					# Trigger the toggle action
					Input.action_press(action_name)
					Input.action_release(action_name)
		else:
			# Reset was_pressed for this specific touch when released
			if was_pressed:
				was_pressed = false


func _is_point_inside(point: Vector2) -> bool:
	# Convert the touch point to local coordinates to handle rotation properly
	var local_point = get_global_transform().affine_inverse() * point
	var rect = Rect2(Vector2.ZERO, size)
	return rect.has_point(local_point)


func set_active(active: bool) -> void:
	is_active = active
	update_visual_state()


func update_visual_state() -> void:
	if is_active:
		modulate = active_modulate
	else:
		modulate = inactive_modulate

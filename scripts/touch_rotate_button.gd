extends TextureButton
## Touch button that triggers a rotate action while pressed

@export var action_name: String = "rotate_left"

var is_pressed_down: bool = false


func _ready() -> void:
	button_down.connect(_on_button_down)
	button_up.connect(_on_button_up)


func _on_button_down() -> void:
	is_pressed_down = true


func _on_button_up() -> void:
	is_pressed_down = false


func _process(_delta: float) -> void:
	if is_pressed_down:
		Input.action_press(action_name)
	else:
		Input.action_release(action_name)

extends TextureButton


func _ready() -> void:
	pressed.connect(_on_pressed)


func _on_pressed() -> void:
	if GameController:
		GameController.show_pause_screen()

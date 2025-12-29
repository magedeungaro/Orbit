extends TextureButton


func _ready() -> void:
	pressed.connect(_on_pressed)


func _on_pressed() -> void:
	# Try to find GameController (autoload) first
	if GameController and GameController.has_method("show_pause_screen"):
		GameController.show_pause_screen()
		return
	
	# Fallback to finding GameManager in scene tree
	var game_manager = get_tree().root.find_child("GameManager", true, false)
	if game_manager and game_manager.has_method("show_pause_screen"):
		game_manager.show_pause_screen()

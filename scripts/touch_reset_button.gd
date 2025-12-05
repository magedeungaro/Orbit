extends TextureButton
## Touch button that restarts the game when pressed


func _ready() -> void:
	pressed.connect(_on_pressed)


func _on_pressed() -> void:
	# Find the game manager and call restart
	var game_manager = get_tree().root.find_child("GameManager", true, false)
	if game_manager and game_manager.has_method("restart_game"):
		game_manager.restart_game()

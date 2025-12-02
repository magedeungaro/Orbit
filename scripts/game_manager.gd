extends CanvasLayer
## Game Manager - Handles start screen, game over, and game state

signal game_started
signal game_over
signal game_won

enum GameState { START_SCREEN, PLAYING, GAME_OVER, GAME_WON }

var current_state: GameState = GameState.START_SCREEN
var orbiting_body: CharacterBody2D

# UI Elements
var start_screen: Control
var game_over_screen: Control
var game_won_screen: Control
var start_button: Button
var restart_button: Button
var play_again_button: Button


func _ready() -> void:
	# Set layer to be on top of everything
	layer = 100
	
	# Get reference to orbiting body
	orbiting_body = get_tree().root.find_child("OrbitingBody", true, false)
	
	# Create the UI screens
	_create_start_screen()
	_create_game_over_screen()
	_create_game_won_screen()
	
	# Show start screen initially
	show_start_screen()


func _create_start_screen() -> void:
	start_screen = Control.new()
	start_screen.name = "StartScreen"
	start_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(start_screen)
	
	# Dark overlay
	var overlay = ColorRect.new()
	overlay.name = "Overlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.7)
	start_screen.add_child(overlay)
	
	# Center container
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	start_screen.add_child(center)
	
	# VBox for content
	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 30)
	center.add_child(vbox)
	
	# Title
	var title = Label.new()
	title.text = "ORBITAL MECHANICS"
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	
	# Subtitle
	var subtitle = Label.new()
	subtitle.text = "Navigate through space using gravity and thrust"
	subtitle.add_theme_font_size_override("font_size", 18)
	subtitle.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(subtitle)
	
	# Spacer
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(spacer)
	
	# Instructions
	var instructions = Label.new()
	instructions.text = "Controls:\nLEFT/RIGHT - Rotate ship\nSPACE - Thrust\nR - Restart | ESC - Menu\n\nUse gravity to conserve fuel!\nReach Earth 3 and establish a stable orbit!"
	instructions.add_theme_font_size_override("font_size", 16)
	instructions.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	instructions.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(instructions)
	
	# Another spacer
	var spacer2 = Control.new()
	spacer2.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(spacer2)
	
	# Start button
	start_button = Button.new()
	start_button.text = "START GAME"
	start_button.custom_minimum_size = Vector2(200, 50)
	start_button.add_theme_font_size_override("font_size", 20)
	start_button.pressed.connect(_on_start_pressed)
	vbox.add_child(start_button)


func _create_game_over_screen() -> void:
	game_over_screen = Control.new()
	game_over_screen.name = "GameOverScreen"
	game_over_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	game_over_screen.visible = false
	add_child(game_over_screen)
	
	# Dark overlay
	var overlay = ColorRect.new()
	overlay.name = "Overlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.8)
	game_over_screen.add_child(overlay)
	
	# Center container
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	game_over_screen.add_child(center)
	
	# VBox for content
	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 30)
	center.add_child(vbox)
	
	# Game Over title
	var title = Label.new()
	title.text = "OUT OF FUEL"
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	
	# Message
	var message = Label.new()
	message.text = "Your ship has run out of fuel.\nYou are now adrift in space..."
	message.add_theme_font_size_override("font_size", 18)
	message.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(message)
	
	# Spacer
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(spacer)
	
	# Restart button
	restart_button = Button.new()
	restart_button.text = "TRY AGAIN"
	restart_button.custom_minimum_size = Vector2(200, 50)
	restart_button.add_theme_font_size_override("font_size", 20)
	restart_button.pressed.connect(_on_restart_pressed)
	vbox.add_child(restart_button)


func _create_game_won_screen() -> void:
	game_won_screen = Control.new()
	game_won_screen.name = "GameWonScreen"
	game_won_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	game_won_screen.visible = false
	add_child(game_won_screen)
	
	# Dark overlay with green tint
	var overlay = ColorRect.new()
	overlay.name = "Overlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0.1, 0, 0.8)
	game_won_screen.add_child(overlay)
	
	# Center container
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	game_won_screen.add_child(center)
	
	# VBox for content
	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 30)
	center.add_child(vbox)
	
	# Victory title
	var title = Label.new()
	title.text = "🌍 STABLE ORBIT ACHIEVED! 🎉"
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	
	# Victory message
	var message = Label.new()
	message.text = "Congratulations!\nYou've successfully established\na stable orbit around Earth 3!"
	message.add_theme_font_size_override("font_size", 20)
	message.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(message)
	
	# Stats label (will be updated when shown)
	var stats = Label.new()
	stats.name = "StatsLabel"
	stats.text = ""
	stats.add_theme_font_size_override("font_size", 16)
	stats.add_theme_color_override("font_color", Color(0.7, 0.9, 0.7))
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(stats)
	
	# Spacer
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(spacer)
	
	# Play again button
	play_again_button = Button.new()
	play_again_button.text = "PLAY AGAIN"
	play_again_button.custom_minimum_size = Vector2(200, 50)
	play_again_button.add_theme_font_size_override("font_size", 20)
	play_again_button.pressed.connect(_on_restart_pressed)
	vbox.add_child(play_again_button)


func _process(_delta: float) -> void:
	# Check for game over/win conditions
	if current_state == GameState.PLAYING and orbiting_body != null:
		# Check for game over (out of fuel)
		if orbiting_body.current_fuel <= 0:
			show_game_over()
		# Check for win condition (stable orbit around Earth3)
		elif orbiting_body.is_in_stable_orbit():
			show_game_won()


func _unhandled_input(event: InputEvent) -> void:
	# Press R to restart at any time during gameplay
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_R and current_state == GameState.PLAYING:
			restart_game()
		# Press Escape to go back to start screen
		elif event.keycode == KEY_ESCAPE:
			if current_state == GameState.PLAYING:
				show_start_screen()
			elif current_state == GameState.GAME_OVER or current_state == GameState.GAME_WON:
				show_start_screen()


func show_start_screen() -> void:
	current_state = GameState.START_SCREEN
	start_screen.visible = true
	game_over_screen.visible = false
	game_won_screen.visible = false
	
	# Pause the game
	if orbiting_body != null:
		orbiting_body.set_physics_process(false)


func show_game_over() -> void:
	current_state = GameState.GAME_OVER
	start_screen.visible = false
	game_over_screen.visible = true
	game_won_screen.visible = false
	emit_signal("game_over")


func show_game_won() -> void:
	current_state = GameState.GAME_WON
	start_screen.visible = false
	game_over_screen.visible = false
	game_won_screen.visible = true
	
	# Update stats display
	var stats_label = game_won_screen.find_child("StatsLabel", true, false)
	if stats_label != null and orbiting_body != null:
		var fuel_remaining = orbiting_body.get_fuel_percentage()
		stats_label.text = "Fuel remaining: %.1f%%" % fuel_remaining
	
	# Pause the game
	if orbiting_body != null:
		orbiting_body.set_physics_process(false)
	
	emit_signal("game_won")


func start_game() -> void:
	current_state = GameState.PLAYING
	start_screen.visible = false
	game_over_screen.visible = false
	game_won_screen.visible = false
	
	# Resume the game
	if orbiting_body != null:
		orbiting_body.set_physics_process(true)
	
	emit_signal("game_started")


func restart_game() -> void:
	# Reset player state
	if orbiting_body != null:
		orbiting_body.current_fuel = orbiting_body.max_fuel
		orbiting_body.velocity = Vector2.ZERO
		orbiting_body.global_position = Vector2(300, 300)
		orbiting_body.thrust_angle = 0.0
		orbiting_body.orbit_trail.clear()
		# Reset orbit tracking
		orbiting_body.time_in_stable_orbit = 0.0
		orbiting_body.orbit_distance_samples.clear()
		orbiting_body.total_orbit_angle = 0.0
	
	start_game()


func _on_start_pressed() -> void:
	start_game()


func _on_restart_pressed() -> void:
	restart_game()


func is_game_active() -> bool:
	return current_state == GameState.PLAYING

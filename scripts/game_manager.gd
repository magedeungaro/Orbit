extends CanvasLayer
## Game Manager - Handles start screen, game over, and game state

signal game_started
signal game_over
signal game_won
signal ship_crashed

enum GameState { START_SCREEN, PLAYING, GAME_OVER, GAME_WON, CRASHED }

var current_state: GameState = GameState.START_SCREEN
var orbiting_body: CharacterBody2D

# UI Elements
var start_screen: Control
var game_over_screen: Control
var game_won_screen: Control
var crash_screen: Control
var options_screen: Control
var start_button: Button
var options_button: Button
var restart_button: Button
var play_again_button: Button
var crash_restart_button: Button
var back_button: Button
var touch_controls_button: Button

# Touch controls reference
var touch_controls_manager: Node


func _ready() -> void:
	# Set layer to be on top of everything
	layer = 100
	
	# Get reference to orbiting body
	orbiting_body = get_tree().root.find_child("OrbitingBody", true, false)
	
	# Get reference to touch controls manager
	touch_controls_manager = get_tree().root.find_child("TouchControls", true, false)
	
	# Create the UI screens
	_create_start_screen()
	_create_game_over_screen()
	_create_game_won_screen()
	_create_crash_screen()
	_create_options_screen()
	
	# Connect to ship explosion signal
	if orbiting_body != null:
		if orbiting_body.has_signal("ship_exploded"):
			orbiting_body.ship_exploded.connect(_on_ship_exploded)
	
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
	vbox.add_theme_constant_override("separation", 40)
	center.add_child(vbox)
	
	# Title
	var title = Label.new()
	title.text = "ORBITAL MECHANICS"
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	
	# Subtitle
	var subtitle = Label.new()
	subtitle.text = "Navigate through space using gravity and thrust"
	subtitle.add_theme_font_size_override("font_size", 28)
	subtitle.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(subtitle)
	
	# Spacer
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 30)
	vbox.add_child(spacer)
	
	# Instructions
	var instructions = Label.new()
	instructions.text = "Controls:\nLEFT/RIGHT - Rotate ship | SPACE - Thrust\nT - Prograde Lock | G - Retrograde Lock\nR - Restart | ESC - Menu\n\nUse gravity to conserve fuel!\nReach Earth 3 and establish a stable orbit!"
	instructions.add_theme_font_size_override("font_size", 24)
	instructions.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	instructions.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(instructions)
	
	# Another spacer
	var spacer2 = Control.new()
	spacer2.custom_minimum_size = Vector2(0, 30)
	vbox.add_child(spacer2)
	
	# Start button
	start_button = Button.new()
	start_button.text = "START GAME"
	start_button.custom_minimum_size = Vector2(300, 70)
	start_button.add_theme_font_size_override("font_size", 28)
	start_button.pressed.connect(_on_start_pressed)
	vbox.add_child(start_button)
	
	# Options button
	options_button = Button.new()
	options_button.text = "OPTIONS"
	options_button.custom_minimum_size = Vector2(300, 70)
	options_button.add_theme_font_size_override("font_size", 28)
	options_button.pressed.connect(_on_options_pressed)
	vbox.add_child(options_button)
	
	# Setup focus navigation for start screen
	start_button.focus_neighbor_bottom = options_button.get_path()
	options_button.focus_neighbor_top = start_button.get_path()
	start_button.focus_neighbor_top = options_button.get_path()
	options_button.focus_neighbor_bottom = start_button.get_path()


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
	vbox.add_theme_constant_override("separation", 40)
	center.add_child(vbox)
	
	# Game Over title
	var title = Label.new()
	title.text = "OUT OF FUEL"
	title.add_theme_font_size_override("font_size", 80)
	title.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	
	# Message
	var message = Label.new()
	message.text = "Your ship has run out of fuel.\nYou are now adrift in space..."
	message.add_theme_font_size_override("font_size", 28)
	message.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(message)
	
	# Spacer
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 30)
	vbox.add_child(spacer)
	
	# Restart button
	restart_button = Button.new()
	restart_button.text = "TRY AGAIN"
	restart_button.custom_minimum_size = Vector2(300, 70)
	restart_button.add_theme_font_size_override("font_size", 28)
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
	vbox.add_theme_constant_override("separation", 40)
	center.add_child(vbox)
	
	# Victory title
	var title = Label.new()
	title.text = "🌍 STABLE ORBIT ACHIEVED! 🎉"
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", Color(0.3, 1.0, 0.3))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	
	# Victory message
	var message = Label.new()
	message.text = "Congratulations!\nYou've successfully established\na stable orbit around Earth 3!"
	message.add_theme_font_size_override("font_size", 28)
	message.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(message)
	
	# Stats label (will be updated when shown)
	var stats = Label.new()
	stats.name = "StatsLabel"
	stats.text = ""
	stats.add_theme_font_size_override("font_size", 24)
	stats.add_theme_color_override("font_color", Color(0.7, 0.9, 0.7))
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(stats)
	
	# Spacer
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 30)
	vbox.add_child(spacer)
	
	# Play again button
	play_again_button = Button.new()
	play_again_button.text = "PLAY AGAIN"
	play_again_button.custom_minimum_size = Vector2(300, 70)
	play_again_button.add_theme_font_size_override("font_size", 28)
	play_again_button.pressed.connect(_on_restart_pressed)
	vbox.add_child(play_again_button)


func _create_crash_screen() -> void:
	crash_screen = Control.new()
	crash_screen.name = "CrashScreen"
	crash_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	crash_screen.visible = false
	add_child(crash_screen)
	
	# Dark overlay with red tint
	var overlay = ColorRect.new()
	overlay.name = "Overlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0.2, 0, 0, 0.85)
	crash_screen.add_child(overlay)
	
	# Center container
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	crash_screen.add_child(center)
	
	# VBox for content
	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 40)
	center.add_child(vbox)
	
	# Crash title
	var title = Label.new()
	title.text = "💥 SHIP DESTROYED! 💥"
	title.add_theme_font_size_override("font_size", 80)
	title.add_theme_color_override("font_color", Color(1.0, 0.4, 0.2))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	
	# Crash message
	var message = Label.new()
	message.text = "Your ship crashed into a planet!\nRemember: Gravity is both friend and foe."
	message.add_theme_font_size_override("font_size", 28)
	message.add_theme_color_override("font_color", Color(0.9, 0.8, 0.8))
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(message)
	
	# Spacer
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 30)
	vbox.add_child(spacer)
	
	# Restart button
	crash_restart_button = Button.new()
	crash_restart_button.text = "TRY AGAIN"
	crash_restart_button.custom_minimum_size = Vector2(300, 70)
	crash_restart_button.add_theme_font_size_override("font_size", 28)
	crash_restart_button.pressed.connect(_on_restart_pressed)
	vbox.add_child(crash_restart_button)


func _create_options_screen() -> void:
	options_screen = Control.new()
	options_screen.name = "OptionsScreen"
	options_screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	options_screen.visible = false
	add_child(options_screen)
	
	# Dark overlay
	var overlay = ColorRect.new()
	overlay.name = "Overlay"
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.8)
	options_screen.add_child(overlay)
	
	# Center container
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	options_screen.add_child(center)
	
	# VBox for content
	var vbox = VBoxContainer.new()
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 40)
	center.add_child(vbox)
	
	# Options title
	var title = Label.new()
	title.text = "OPTIONS"
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", Color.WHITE)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	
	# Spacer
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 40)
	vbox.add_child(spacer)
	
	# Touch Controls toggle button
	touch_controls_button = Button.new()
	touch_controls_button.name = "TouchControlsButton"
	touch_controls_button.custom_minimum_size = Vector2(400, 70)
	touch_controls_button.add_theme_font_size_override("font_size", 28)
	touch_controls_button.pressed.connect(_on_touch_controls_pressed)
	_update_touch_controls_button_text()
	vbox.add_child(touch_controls_button)
	
	# Another spacer
	var spacer2 = Control.new()
	spacer2.custom_minimum_size = Vector2(0, 30)
	vbox.add_child(spacer2)
	
	# Back button
	back_button = Button.new()
	back_button.text = "BACK"
	back_button.custom_minimum_size = Vector2(300, 70)
	back_button.add_theme_font_size_override("font_size", 28)
	back_button.pressed.connect(_on_back_pressed)
	vbox.add_child(back_button)
	
	# Setup focus navigation for options screen
	touch_controls_button.focus_neighbor_bottom = back_button.get_path()
	back_button.focus_neighbor_top = touch_controls_button.get_path()
	touch_controls_button.focus_neighbor_top = back_button.get_path()
	back_button.focus_neighbor_bottom = touch_controls_button.get_path()


func _update_touch_controls_button_text() -> void:
	if touch_controls_button == null:
		return
	
	var pref_text: String
	if touch_controls_manager != null and touch_controls_manager.has_method("get_preference"):
		var pref = touch_controls_manager.get_preference()
		match pref:
			-1:
				var auto_state = "ON" if touch_controls_manager.is_auto_touch_device() else "OFF"
				pref_text = "Auto (" + auto_state + ")"
			0:
				pref_text = "Off"
			1:
				pref_text = "On"
			_:
				pref_text = "Auto"
	else:
		pref_text = "N/A"
	
	touch_controls_button.text = "Touch Controls: " + pref_text


func _process(_delta: float) -> void:
	# Check for game over/win conditions
	if current_state == GameState.PLAYING and orbiting_body != null:
		# Check for crash (ship exploded)
		if orbiting_body.is_ship_exploded():
			show_crash_screen()
		# Check for game over (out of fuel)
		elif orbiting_body.current_fuel <= 0:
			show_game_over()
		# Check for win condition (stable orbit around Earth3)
		elif orbiting_body.is_in_stable_orbit():
			show_game_won()


func _unhandled_input(event: InputEvent) -> void:
	# Press R to restart at any time during gameplay
	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_R and current_state == GameState.PLAYING:
			restart_game()
		# Press Escape to go back to start screen or close options
		elif event.keycode == KEY_ESCAPE:
			if options_screen.visible:
				_on_back_pressed()
			elif current_state == GameState.PLAYING:
				show_start_screen()
			elif current_state == GameState.GAME_OVER or current_state == GameState.GAME_WON or current_state == GameState.CRASHED:
				show_start_screen()


func show_start_screen() -> void:
	current_state = GameState.START_SCREEN
	start_screen.visible = true
	game_over_screen.visible = false
	game_won_screen.visible = false
	crash_screen.visible = false
	options_screen.visible = false
	
	# Set initial focus for keyboard navigation
	if start_button:
		start_button.grab_focus()
	
	# Pause the game
	if orbiting_body != null:
		orbiting_body.set_physics_process(false)


func show_game_over() -> void:
	current_state = GameState.GAME_OVER
	start_screen.visible = false
	game_over_screen.visible = true
	game_won_screen.visible = false
	crash_screen.visible = false
	options_screen.visible = false
	
	# Set initial focus for keyboard navigation
	if restart_button:
		restart_button.grab_focus()
	
	emit_signal("game_over")


func show_game_won() -> void:
	current_state = GameState.GAME_WON
	start_screen.visible = false
	game_over_screen.visible = false
	game_won_screen.visible = true
	crash_screen.visible = false
	options_screen.visible = false
	
	# Update stats display
	var stats_label = game_won_screen.find_child("StatsLabel", true, false)
	if stats_label != null and orbiting_body != null:
		var fuel_remaining = orbiting_body.get_fuel_percentage()
		stats_label.text = "Fuel remaining: %.1f%%" % fuel_remaining
	
	# Set initial focus for keyboard navigation
	if play_again_button:
		play_again_button.grab_focus()
	
	# Pause the game
	if orbiting_body != null:
		orbiting_body.set_physics_process(false)
	
	emit_signal("game_won")


func show_crash_screen() -> void:
	current_state = GameState.CRASHED
	start_screen.visible = false
	game_over_screen.visible = false
	game_won_screen.visible = false
	crash_screen.visible = true
	options_screen.visible = false
	
	# Set initial focus for keyboard navigation
	if crash_restart_button:
		crash_restart_button.grab_focus()
	
	# Pause the game
	if orbiting_body != null:
		orbiting_body.set_physics_process(false)
	
	emit_signal("ship_crashed")


func _on_ship_exploded() -> void:
	# This is called immediately when ship explodes
	# The crash screen will be shown after explosion animation completes
	print("Ship explosion signal received")


func start_game() -> void:
	current_state = GameState.PLAYING
	start_screen.visible = false
	game_over_screen.visible = false
	game_won_screen.visible = false
	crash_screen.visible = false
	options_screen.visible = false
	
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
		# Reset explosion state
		orbiting_body.reset_explosion()
	
	start_game()


func _on_start_pressed() -> void:
	start_game()


func _on_restart_pressed() -> void:
	restart_game()


func _on_options_pressed() -> void:
	show_options_screen()


func _on_back_pressed() -> void:
	options_screen.visible = false
	start_screen.visible = true
	if start_button:
		start_button.grab_focus()


func _on_touch_controls_pressed() -> void:
	if touch_controls_manager != null and touch_controls_manager.has_method("cycle_preference"):
		touch_controls_manager.cycle_preference()
		_update_touch_controls_button_text()


func show_options_screen() -> void:
	start_screen.visible = false
	options_screen.visible = true
	_update_touch_controls_button_text()
	
	# Set initial focus for keyboard navigation
	if touch_controls_button:
		touch_controls_button.grab_focus()


func is_game_active() -> bool:
	return current_state == GameState.PLAYING

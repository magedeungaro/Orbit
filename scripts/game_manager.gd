extends CanvasLayer

enum GameState { START_SCREEN, PLAYING, PAUSED, GAME_OVER, GAME_WON, CRASHED, LEVEL_SELECT }

const StartScreenScene = preload("res://scenes/ui/start_screen.tscn")
const GameOverScreenScene = preload("res://scenes/ui/game_over_screen.tscn")
const GameWonScreenScene = preload("res://scenes/ui/game_won_screen.tscn")
const CrashScreenScene = preload("res://scenes/ui/crash_screen.tscn")
const OptionsScreenScene = preload("res://scenes/ui/options_screen.tscn")
const LevelSelectScreenScene = preload("res://scenes/ui/level_select_screen.tscn")
const PauseScreenScene = preload("res://scenes/ui/pause_screen.tscn")
const PlanetScene = preload("res://scenes/prefabs/planet.tscn")
const AudiowideFont = preload("res://Assets/fonts/Audiowide/Audiowide-Regular.ttf")

var current_state: GameState = GameState.START_SCREEN
var orbiting_body: CharacterBody2D
var touch_controls_manager: Node
var planets_container: Node2D

var start_screen: Control
var game_over_screen: Control
var game_won_screen: Control
var crash_screen: Control
var options_screen: Control
var level_select_screen: Control
var pause_screen: Control

var start_button: Button
var options_button: Button
var level_select_button: Button
var quit_button: Button
var restart_button: Button
var play_again_button: Button
var next_level_button: Button
var crash_restart_button: Button
var back_button: Button
var touch_controls_button: Button
var level_select_back_button: Button
var level_buttons: Array[Button] = []

# Pause screen buttons
var resume_button: Button
var pause_options_button: Button
var quit_to_menu_button: Button
var quit_to_desktop_button: Button

# Track where options was opened from
var _options_opened_from_pause: bool = false


func _ready() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS  # Allow processing while paused
	
	orbiting_body = get_tree().root.find_child("Ship", true, false)
	touch_controls_manager = get_tree().root.find_child("TouchControls", true, false)
	planets_container = get_tree().root.find_child("Planets", true, false)
	
	_setup_ui_screens()
	_connect_signals()
	
	show_start_screen()


func _setup_ui_screens() -> void:
	start_screen = StartScreenScene.instantiate()
	add_child(start_screen)
	start_button = start_screen.get_node("CenterContainer/VBoxContainer/StartButton")
	level_select_button = start_screen.get_node("CenterContainer/VBoxContainer/LevelSelectButton")
	options_button = start_screen.get_node("CenterContainer/VBoxContainer/OptionsButton")
	quit_button = start_screen.get_node("CenterContainer/VBoxContainer/QuitButton")
	start_button.pressed.connect(_on_start_pressed)
	level_select_button.pressed.connect(_on_level_select_pressed)
	options_button.pressed.connect(_on_options_pressed)
	quit_button.pressed.connect(_on_quit_to_desktop_pressed)
	_setup_focus_neighbors_four(start_button, level_select_button, options_button, quit_button)
	
	game_over_screen = GameOverScreenScene.instantiate()
	game_over_screen.visible = false
	add_child(game_over_screen)
	restart_button = game_over_screen.get_node("CenterContainer/VBoxContainer/RestartButton")
	restart_button.pressed.connect(_on_restart_pressed)
	
	game_won_screen = GameWonScreenScene.instantiate()
	game_won_screen.visible = false
	add_child(game_won_screen)
	play_again_button = game_won_screen.get_node("CenterContainer/VBoxContainer/PlayAgainButton")
	play_again_button.pressed.connect(_on_restart_pressed)
	_setup_next_level_button()
	
	crash_screen = CrashScreenScene.instantiate()
	crash_screen.visible = false
	add_child(crash_screen)
	crash_restart_button = crash_screen.get_node("CenterContainer/VBoxContainer/RestartButton")
	crash_restart_button.pressed.connect(_on_restart_pressed)
	
	options_screen = OptionsScreenScene.instantiate()
	options_screen.visible = false
	add_child(options_screen)
	touch_controls_button = options_screen.get_node("CenterContainer/VBoxContainer/TouchControlsButton")
	back_button = options_screen.get_node("CenterContainer/VBoxContainer/BackButton")
	touch_controls_button.pressed.connect(_on_touch_controls_pressed)
	back_button.pressed.connect(_on_back_pressed)
	_setup_focus_neighbors(touch_controls_button, back_button)
	
	_setup_pause_screen()
	_setup_level_select_screen()


func _setup_pause_screen() -> void:
	pause_screen = PauseScreenScene.instantiate()
	pause_screen.visible = false
	add_child(pause_screen)
	
	resume_button = pause_screen.get_node("CenterContainer/VBoxContainer/ResumeButton")
	pause_options_button = pause_screen.get_node("CenterContainer/VBoxContainer/OptionsButton")
	quit_to_menu_button = pause_screen.get_node("CenterContainer/VBoxContainer/QuitToMenuButton")
	quit_to_desktop_button = pause_screen.get_node("CenterContainer/VBoxContainer/QuitToDesktopButton")
	
	resume_button.pressed.connect(_on_resume_pressed)
	pause_options_button.pressed.connect(_on_pause_options_pressed)
	quit_to_menu_button.pressed.connect(_on_quit_to_menu_pressed)
	quit_to_desktop_button.pressed.connect(_on_quit_to_desktop_pressed)
	
	_setup_focus_neighbors_four(resume_button, pause_options_button, quit_to_menu_button, quit_to_desktop_button)


func _setup_focus_neighbors(button1: Button, button2: Button) -> void:
	button1.focus_neighbor_bottom = button2.get_path()
	button2.focus_neighbor_top = button1.get_path()
	button1.focus_neighbor_top = button2.get_path()
	button2.focus_neighbor_bottom = button1.get_path()


func _setup_focus_neighbors_three(button1: Button, button2: Button, button3: Button) -> void:
	button1.focus_neighbor_bottom = button2.get_path()
	button1.focus_neighbor_top = button3.get_path()
	button2.focus_neighbor_top = button1.get_path()
	button2.focus_neighbor_bottom = button3.get_path()
	button3.focus_neighbor_top = button2.get_path()
	button3.focus_neighbor_bottom = button1.get_path()


func _setup_focus_neighbors_four(button1: Button, button2: Button, button3: Button, button4: Button) -> void:
	button1.focus_neighbor_bottom = button2.get_path()
	button1.focus_neighbor_top = button4.get_path()
	button2.focus_neighbor_top = button1.get_path()
	button2.focus_neighbor_bottom = button3.get_path()
	button3.focus_neighbor_top = button2.get_path()
	button3.focus_neighbor_bottom = button4.get_path()
	button4.focus_neighbor_top = button3.get_path()
	button4.focus_neighbor_bottom = button1.get_path()


func _setup_level_select_screen() -> void:
	level_select_screen = LevelSelectScreenScene.instantiate()
	level_select_screen.visible = false
	add_child(level_select_screen)
	
	level_select_back_button = level_select_screen.get_node("CenterContainer/VBoxContainer/BackButton")
	level_select_back_button.pressed.connect(_on_level_select_back_pressed)
	
	_populate_level_buttons()


func _setup_next_level_button() -> void:
	var vbox = game_won_screen.get_node("CenterContainer/VBoxContainer")
	next_level_button = Button.new()
	next_level_button.name = "NextLevelButton"
	next_level_button.custom_minimum_size = Vector2(250, 55)
	next_level_button.add_theme_font_override("font", AudiowideFont)
	next_level_button.add_theme_font_size_override("font_size", 24)
	next_level_button.text = "NEXT LEVEL"
	next_level_button.pressed.connect(_on_next_level_pressed)
	
	# Insert before PlayAgainButton
	var play_again_index = play_again_button.get_index()
	vbox.add_child(next_level_button)
	vbox.move_child(next_level_button, play_again_index)


func _populate_level_buttons() -> void:
	var container = level_select_screen.get_node("CenterContainer/VBoxContainer/LevelButtonsContainer")
	
	# Clear existing buttons
	for child in container.get_children():
		child.queue_free()
	level_buttons.clear()
	
	if not LevelManager:
		return
	
	var levels = LevelManager.get_all_levels()
	for level in levels:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(350, 60)
		btn.add_theme_font_override("font", AudiowideFont)
		btn.add_theme_font_size_override("font_size", 20)
		
		var is_unlocked = LevelManager.is_level_unlocked(level.id)
		var best_score = LevelManager.get_best_score(level.id)
		
		var btn_text = "Level %d: %s" % [level.id, level.name]
		if best_score >= 0:
			btn_text += " (Best: %.0f%%)" % best_score
		elif not is_unlocked:
			btn_text = "Level %d: LOCKED" % level.id
		
		btn.text = btn_text
		btn.disabled = not is_unlocked
		btn.pressed.connect(_on_level_button_pressed.bind(level.id))
		container.add_child(btn)
		level_buttons.append(btn)
	
	# Setup focus navigation for level buttons
	for i in range(level_buttons.size()):
		var btn = level_buttons[i]
		if i > 0:
			btn.focus_neighbor_top = level_buttons[i - 1].get_path()
		else:
			btn.focus_neighbor_top = level_select_back_button.get_path()
		
		if i < level_buttons.size() - 1:
			btn.focus_neighbor_bottom = level_buttons[i + 1].get_path()
		else:
			btn.focus_neighbor_bottom = level_select_back_button.get_path()
	
	if level_buttons.size() > 0:
		level_select_back_button.focus_neighbor_top = level_buttons[level_buttons.size() - 1].get_path()
		level_select_back_button.focus_neighbor_bottom = level_buttons[0].get_path()


func _connect_signals() -> void:
	if orbiting_body and orbiting_body.has_signal("ship_exploded"):
		orbiting_body.ship_exploded.connect(_on_ship_exploded)


func _process(_delta: float) -> void:
	if current_state != GameState.PLAYING or orbiting_body == null:
		return
	
	if orbiting_body.is_ship_exploded():
		show_crash_screen()
	elif orbiting_body.current_fuel <= 0:
		show_game_over()
	elif orbiting_body.is_in_stable_orbit():
		show_game_won()


func _unhandled_input(event: InputEvent) -> void:
	# Handle restart action
	if Input.is_action_just_pressed("restart"):
		if current_state == GameState.PLAYING:
			restart_game()
		return
	
	# Handle pause action (Start button)
	if Input.is_action_just_pressed("pause"):
		if options_screen.visible:
			_on_back_pressed()
		elif level_select_screen.visible:
			_on_level_select_back_pressed()
		elif current_state == GameState.PAUSED:
			_on_resume_pressed()
		elif current_state == GameState.PLAYING:
			show_pause_screen()
		elif current_state in [GameState.GAME_OVER, GameState.GAME_WON, GameState.CRASHED]:
			show_start_screen()
		return
	
	# Handle cancel/back action (East button / B on Xbox)
	if Input.is_action_just_pressed("ui_cancel"):
		if options_screen.visible:
			_on_back_pressed()
		elif level_select_screen.visible:
			_on_level_select_back_pressed()
		elif current_state == GameState.PAUSED:
			_on_resume_pressed()
		return
	
	# Legacy keyboard support for ESC key
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_ESCAPE:
				if options_screen.visible:
					_on_back_pressed()
				elif level_select_screen.visible:
					_on_level_select_back_pressed()
				elif current_state == GameState.PAUSED:
					_on_resume_pressed()
				elif current_state == GameState.PLAYING:
					show_pause_screen()
				elif current_state in [GameState.GAME_OVER, GameState.GAME_WON, GameState.CRASHED]:
					show_start_screen()


func _hide_all_screens() -> void:
	start_screen.visible = false
	game_over_screen.visible = false
	game_won_screen.visible = false
	crash_screen.visible = false
	options_screen.visible = false
	level_select_screen.visible = false
	pause_screen.visible = false


func show_start_screen() -> void:
	get_tree().paused = false
	current_state = GameState.START_SCREEN
	_hide_all_screens()
	start_screen.visible = true
	start_button.grab_focus()
	
	if orbiting_body:
		orbiting_body.set_physics_process(false)


func show_game_over() -> void:
	current_state = GameState.GAME_OVER
	_hide_all_screens()
	game_over_screen.visible = true
	restart_button.grab_focus()
	
	if Events:
		Events.game_over.emit()


func show_game_won() -> void:
	current_state = GameState.GAME_WON
	_hide_all_screens()
	game_won_screen.visible = true
	
	var fuel_percent := 0.0
	if orbiting_body:
		fuel_percent = orbiting_body.get_fuel_percentage()
	
	var stats_label = game_won_screen.get_node("CenterContainer/VBoxContainer/StatsLabel")
	if stats_label and orbiting_body:
		stats_label.text = "Fuel remaining: %.1f%%" % fuel_percent
	
	# Complete level and handle progression
	if LevelManager:
		LevelManager.complete_level(fuel_percent)
		
		# Show/hide next level button based on availability
		if next_level_button:
			next_level_button.visible = LevelManager.has_next_level()
			if next_level_button.visible:
				next_level_button.grab_focus()
			else:
				play_again_button.grab_focus()
	else:
		play_again_button.grab_focus()
	
	if orbiting_body:
		orbiting_body.set_physics_process(false)
	
	if Events:
		Events.game_won.emit()


func show_crash_screen() -> void:
	current_state = GameState.CRASHED
	_hide_all_screens()
	crash_screen.visible = true
	crash_restart_button.grab_focus()
	
	if orbiting_body:
		orbiting_body.set_physics_process(false)


func show_pause_screen() -> void:
	current_state = GameState.PAUSED
	get_tree().paused = true
	_hide_all_screens()
	pause_screen.visible = true
	resume_button.grab_focus()
	
	if Events:
		Events.game_paused.emit()


func show_options_screen() -> void:
	_options_opened_from_pause = false
	start_screen.visible = false
	options_screen.visible = true
	_update_touch_controls_button_text()
	touch_controls_button.grab_focus()


func show_options_from_pause() -> void:
	_options_opened_from_pause = true
	pause_screen.visible = false
	options_screen.visible = true
	_update_touch_controls_button_text()
	touch_controls_button.grab_focus()


func show_level_select_screen() -> void:
	current_state = GameState.LEVEL_SELECT
	_hide_all_screens()
	level_select_screen.visible = true
	_populate_level_buttons()  # Refresh level buttons
	
	# Focus first unlocked button
	for btn in level_buttons:
		if not btn.disabled:
			btn.grab_focus()
			break


func start_game() -> void:
	get_tree().paused = false
	load_current_level()
	current_state = GameState.PLAYING
	_hide_all_screens()
	
	if orbiting_body:
		orbiting_body.set_physics_process(true)
	
	if Events:
		Events.game_started.emit()


func resume_game() -> void:
	get_tree().paused = false
	current_state = GameState.PLAYING
	_hide_all_screens()
	
	if orbiting_body:
		orbiting_body.set_physics_process(true)
	
	if Events:
		Events.game_resumed.emit()


func restart_game() -> void:
	get_tree().paused = false
	load_current_level()
	
	start_game()
	
	if Events:
		Events.game_restarted.emit()


func load_current_level() -> void:
	if not LevelManager:
		_reset_ship_default()
		return
	
	var level_config = LevelManager.get_current_level()
	if not level_config:
		_reset_ship_default()
		return
	
	# Clear existing planets
	if planets_container:
		for child in planets_container.get_children():
			child.queue_free()
		
		# Wait for planets to be freed
		await get_tree().process_frame
		
		# Spawn new planets
		var planet_index := 1
		for planet_config in level_config.planets:
			var planet_instance = PlanetScene.instantiate()
			planet_instance.name = "Planet%d" % planet_index
			planet_instance.position = planet_config.position
			planet_instance.mass = planet_config.mass
			
			planets_container.add_child(planet_instance)
			
			# Add sprite
			var sprite = Sprite2D.new()
			sprite.texture = load(planet_config.texture_path)
			planet_instance.add_child(sprite)
			
			# Mark target planet
			if planet_config.is_target:
				planet_instance.name = "Earth3"  # Keep compatibility with existing target detection
			
			planet_index += 1
	
	# Reset ship
	if orbiting_body:
		orbiting_body.current_fuel = level_config.max_fuel
		orbiting_body.max_fuel = level_config.max_fuel
		orbiting_body.stable_orbit_time_required = level_config.stable_orbit_time
		orbiting_body.velocity = level_config.ship_start_velocity
		orbiting_body.global_position = level_config.ship_start_position
		orbiting_body.thrust_angle = 0.0
		orbiting_body.orbit_trail.clear()
		orbiting_body.time_in_stable_orbit = 0.0
		orbiting_body.orbit_distance_samples.clear()
		orbiting_body.total_orbit_angle = 0.0
		orbiting_body.reset_explosion()
		
		# Re-find central bodies and target
		orbiting_body.central_bodies = _find_all_central_bodies()
		orbiting_body.target_body = _find_target_planet()
	
	if Events:
		Events.level_loaded.emit(level_config.id)


func _reset_ship_default() -> void:
	if orbiting_body:
		orbiting_body.current_fuel = orbiting_body.max_fuel
		orbiting_body.velocity = Vector2.ZERO
		orbiting_body.global_position = Vector2(300, 300)
		orbiting_body.thrust_angle = 0.0
		orbiting_body.orbit_trail.clear()
		orbiting_body.time_in_stable_orbit = 0.0
		orbiting_body.orbit_distance_samples.clear()
		orbiting_body.total_orbit_angle = 0.0
		orbiting_body.reset_explosion()


func _find_all_central_bodies() -> Array:
	var result: Array = []
	if planets_container:
		for child in planets_container.get_children():
			if child.get_script() != null:
				result.append(child)
	return result


func _find_target_planet() -> Node2D:
	if planets_container:
		for child in planets_container.get_children():
			if child.name == "Earth3":
				return child
	return null


func _update_touch_controls_button_text() -> void:
	if not touch_controls_button:
		return
	
	var pref_text := "N/A"
	if touch_controls_manager and touch_controls_manager.has_method("get_preference"):
		match touch_controls_manager.get_preference():
			-1:
				var auto_state = "ON" if touch_controls_manager.is_auto_touch_device() else "OFF"
				pref_text = "Auto (" + auto_state + ")"
			0:
				pref_text = "Off"
			1:
				pref_text = "On"
	
	touch_controls_button.text = "Touch Controls: " + pref_text


func _on_start_pressed() -> void:
	start_game()


func _on_restart_pressed() -> void:
	restart_game()


func _on_options_pressed() -> void:
	show_options_screen()


func _on_level_select_pressed() -> void:
	show_level_select_screen()


func _on_level_select_back_pressed() -> void:
	level_select_screen.visible = false
	start_screen.visible = true
	start_button.grab_focus()


func _on_level_button_pressed(level_id: int) -> void:
	if LevelManager:
		LevelManager.set_current_level(level_id)
	start_game()


func _on_next_level_pressed() -> void:
	if LevelManager and LevelManager.advance_to_next_level():
		start_game()


func _on_back_pressed() -> void:
	options_screen.visible = false
	if _options_opened_from_pause:
		pause_screen.visible = true
		resume_button.grab_focus()
	else:
		start_screen.visible = true
		start_button.grab_focus()


func _on_resume_pressed() -> void:
	resume_game()


func _on_pause_options_pressed() -> void:
	show_options_from_pause()


func _on_quit_to_menu_pressed() -> void:
	get_tree().paused = false
	show_start_screen()


func _on_quit_to_desktop_pressed() -> void:
	get_tree().quit()


func _on_touch_controls_pressed() -> void:
	if touch_controls_manager and touch_controls_manager.has_method("cycle_preference"):
		touch_controls_manager.cycle_preference()
		_update_touch_controls_button_text()


func _on_ship_exploded() -> void:
	pass


func is_game_active() -> bool:
	return current_state == GameState.PLAYING

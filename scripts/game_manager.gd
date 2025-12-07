extends CanvasLayer

enum GameState { START_SCREEN, PLAYING, GAME_OVER, GAME_WON, CRASHED }

const StartScreenScene = preload("res://scenes/ui/start_screen.tscn")
const GameOverScreenScene = preload("res://scenes/ui/game_over_screen.tscn")
const GameWonScreenScene = preload("res://scenes/ui/game_won_screen.tscn")
const CrashScreenScene = preload("res://scenes/ui/crash_screen.tscn")
const OptionsScreenScene = preload("res://scenes/ui/options_screen.tscn")

var current_state: GameState = GameState.START_SCREEN
var orbiting_body: CharacterBody2D
var touch_controls_manager: Node

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


func _ready() -> void:
	layer = 100
	
	orbiting_body = get_tree().root.find_child("Ship", true, false)
	touch_controls_manager = get_tree().root.find_child("TouchControls", true, false)
	
	_setup_ui_screens()
	_connect_signals()
	
	show_start_screen()


func _setup_ui_screens() -> void:
	start_screen = StartScreenScene.instantiate()
	add_child(start_screen)
	start_button = start_screen.get_node("CenterContainer/VBoxContainer/StartButton")
	options_button = start_screen.get_node("CenterContainer/VBoxContainer/OptionsButton")
	start_button.pressed.connect(_on_start_pressed)
	options_button.pressed.connect(_on_options_pressed)
	_setup_focus_neighbors(start_button, options_button)
	
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


func _setup_focus_neighbors(button1: Button, button2: Button) -> void:
	button1.focus_neighbor_bottom = button2.get_path()
	button2.focus_neighbor_top = button1.get_path()
	button1.focus_neighbor_top = button2.get_path()
	button2.focus_neighbor_bottom = button1.get_path()


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
	if not (event is InputEventKey and event.pressed):
		return
	
	match event.keycode:
		KEY_R:
			if current_state == GameState.PLAYING:
				restart_game()
		KEY_ESCAPE:
			if options_screen.visible:
				_on_back_pressed()
			elif current_state == GameState.PLAYING:
				show_start_screen()
			elif current_state in [GameState.GAME_OVER, GameState.GAME_WON, GameState.CRASHED]:
				show_start_screen()


func _hide_all_screens() -> void:
	start_screen.visible = false
	game_over_screen.visible = false
	game_won_screen.visible = false
	crash_screen.visible = false
	options_screen.visible = false


func show_start_screen() -> void:
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
	
	var stats_label = game_won_screen.get_node("CenterContainer/VBoxContainer/StatsLabel")
	if stats_label and orbiting_body:
		stats_label.text = "Fuel remaining: %.1f%%" % orbiting_body.get_fuel_percentage()
	
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


func show_options_screen() -> void:
	start_screen.visible = false
	options_screen.visible = true
	_update_touch_controls_button_text()
	touch_controls_button.grab_focus()


func start_game() -> void:
	current_state = GameState.PLAYING
	_hide_all_screens()
	
	if orbiting_body:
		orbiting_body.set_physics_process(true)
	
	if Events:
		Events.game_started.emit()


func restart_game() -> void:
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
	
	start_game()
	
	if Events:
		Events.game_restarted.emit()


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


func _on_back_pressed() -> void:
	options_screen.visible = false
	start_screen.visible = true
	start_button.grab_focus()


func _on_touch_controls_pressed() -> void:
	if touch_controls_manager and touch_controls_manager.has_method("cycle_preference"):
		touch_controls_manager.cycle_preference()
		_update_touch_controls_button_text()


func _on_ship_exploded() -> void:
	pass


func is_game_active() -> bool:
	return current_state == GameState.PLAYING

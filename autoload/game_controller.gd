extends Node
## Game Controller Singleton - Manages game state, UI, and level loading
## This is an autoload that persists across scene changes

enum GameState { START_SCREEN, PLAYING, PAUSED, GAME_OVER, GAME_WON, CRASHED, LEVEL_SELECT }

const StartScreenScene = preload("res://scenes/ui/start_screen.tscn")
const GameOverScreenScene = preload("res://scenes/ui/game_over_screen.tscn")
const GameWonScreenScene = preload("res://scenes/ui/game_won_screen.tscn")
const CrashScreenScene = preload("res://scenes/ui/crash_screen.tscn")
const OptionsScreenScene = preload("res://scenes/ui/options_screen.tscn")
const LevelSelectScreenScene = preload("res://scenes/ui/level_select_screen.tscn")
const PauseScreenScene = preload("res://scenes/ui/pause_screen.tscn")
const HUDScript = preload("res://scripts/ui/hud.gd")
const TouchControlsScene = preload("res://scenes/ui/touch_controls.tscn")
const AudiowideFont = preload("res://Assets/fonts/Audiowide/Audiowide-Regular.ttf")

var current_state: GameState = GameState.START_SCREEN

# References to current level components (found after level loads)
var current_level_root: Node2D = null
var orbiting_body: CharacterBody2D = null
var camera: Camera2D = null
var orbit_visualization: Node2D = null

# Persistent HUD and TouchControls (owned by GameController)
var hud: CanvasLayer = null
var touch_controls_manager: CanvasLayer = null

# UI layer for screens
var ui_layer: CanvasLayer

# UI Screens
var start_screen: Control
var game_over_screen: Control
var game_won_screen: Control
var crash_screen: Control
var options_screen: Control
var level_select_screen: Control
var pause_screen: Control

# Buttons
var start_button: Button
var options_button: Button
var level_select_button: Button
var discord_button: Button
var quit_button: Button
var restart_button: Button
var restart_level_button: Button
var play_again_button: Button
var next_level_button: Button
var crash_restart_button: Button
var back_button: Button
var touch_controls_button: Button
var soi_visibility_button: Button
var level_select_back_button: Button
var level_buttons: Array[Button] = []

# End game screen buttons
var game_over_select_level_button: Button
var game_over_quit_to_menu_button: Button
var crash_select_level_button: Button
var crash_quit_to_menu_button: Button
var game_won_select_level_button: Button
var game_won_quit_to_menu_button: Button

# Pause screen buttons
var resume_button: Button
var pause_options_button: Button
var pause_select_level_button: Button
var quit_to_menu_button: Button
var quit_to_desktop_button: Button

# Track where options was opened from
var _options_opened_from_pause: bool = false

# Track where level select was opened from
enum LevelSelectContext { MAIN_MENU, PAUSE, END_GAME }
var _level_select_context: LevelSelectContext = LevelSelectContext.MAIN_MENU

# Store initial ship position for restart
var _ship_start_position: Vector2
var _ship_start_velocity: Vector2

# Persistent camera zoom (survives level changes/restarts)
var _saved_zoom: float = 0.8  # Default zoom level

# SOI visibility setting
var soi_visible: bool = true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Connect to camera zoom events to persist zoom across levels
	if Events:
		Events.camera_zoom_changed.connect(_on_camera_zoom_changed)
	
	# Create UI layer for screens
	ui_layer = CanvasLayer.new()
	ui_layer.layer = 100
	add_child(ui_layer)
	
	# Create persistent HUD (layer 10, below UI screens)
	hud = CanvasLayer.new()
	hud.layer = 10
	hud.set_script(HUDScript)
	add_child(hud)
	
	# Create persistent TouchControls (layer 11)
	touch_controls_manager = TouchControlsScene.instantiate()
	touch_controls_manager.layer = 11
	add_child(touch_controls_manager)
	
	_setup_ui_screens()
	
	# Defer show_start_screen to ensure all autoloads are ready
	call_deferred("show_start_screen")


func _input(event: InputEvent) -> void:
	# Handle Enter/Space on level select screen to start selected level
	if current_state == GameState.LEVEL_SELECT and level_select_screen and level_select_screen.visible:
		if event.is_action_pressed("ui_accept") or (event is InputEventKey and event.pressed and event.keycode == KEY_SPACE):
			# Check if Play button or any level button has focus
			var play_button = level_select_screen.get_node("MainContainer/DetailPanel/MarginContainer/VBoxContainer/ButtonsContainer/PlayButton")
			var has_level_button_focus = false
			for btn in level_buttons:
				if btn.has_focus():
					has_level_button_focus = true
					break
			
			if selected_level_id > 0 and (play_button.has_focus() or has_level_button_focus):
				_on_level_play_button_pressed()
				get_viewport().set_input_as_handled()


func _setup_ui_screens() -> void:
	start_screen = StartScreenScene.instantiate()
	ui_layer.add_child(start_screen)
	start_button = start_screen.get_node("CenterContainer/VBoxContainer/StartButton")
	level_select_button = start_screen.get_node("CenterContainer/VBoxContainer/LevelSelectButton")
	options_button = start_screen.get_node("CenterContainer/VBoxContainer/OptionsButton")
	discord_button = start_screen.get_node("CenterContainer/VBoxContainer/DiscordButton")
	quit_button = start_screen.get_node("CenterContainer/VBoxContainer/QuitButton")
	# start_button.pressed.connect(_on_start_pressed)  # Disabled for Story Mode coming soon
	level_select_button.pressed.connect(_on_level_select_pressed)
	options_button.pressed.connect(_on_options_pressed)
	discord_button.pressed.connect(_on_discord_pressed)
	quit_button.pressed.connect(_on_quit_to_desktop_pressed)
	_setup_focus_neighbors_five(start_button, level_select_button, options_button, discord_button, quit_button)
	
	game_over_screen = GameOverScreenScene.instantiate()
	game_over_screen.visible = false
	ui_layer.add_child(game_over_screen)
	restart_button = game_over_screen.get_node("CenterContainer/VBoxContainer/RestartButton")
	restart_button.pressed.connect(_on_restart_pressed)
	game_over_select_level_button = game_over_screen.get_node("CenterContainer/VBoxContainer/SelectLevelButton")
	game_over_select_level_button.pressed.connect(_on_endgame_select_level_pressed)
	game_over_quit_to_menu_button = game_over_screen.get_node("CenterContainer/VBoxContainer/QuitToMenuButton")
	game_over_quit_to_menu_button.pressed.connect(_on_quit_to_menu_pressed)
	
	game_won_screen = GameWonScreenScene.instantiate()
	game_won_screen.visible = false
	ui_layer.add_child(game_won_screen)
	restart_level_button = game_won_screen.get_node("CenterContainer/VBoxContainer/PlayAgainButton")
	restart_level_button.pressed.connect(_on_restart_pressed)
	game_won_select_level_button = game_won_screen.get_node("CenterContainer/VBoxContainer/SelectLevelButton")
	game_won_select_level_button.pressed.connect(_on_endgame_select_level_pressed)
	game_won_quit_to_menu_button = game_won_screen.get_node("CenterContainer/VBoxContainer/QuitToMenuButton")
	game_won_quit_to_menu_button.pressed.connect(_on_quit_to_menu_pressed)
	_setup_next_level_button()
	_setup_play_again_button()
	
	crash_screen = CrashScreenScene.instantiate()
	crash_screen.visible = false
	ui_layer.add_child(crash_screen)
	crash_restart_button = crash_screen.get_node("CenterContainer/VBoxContainer/RestartButton")
	crash_restart_button.pressed.connect(_on_restart_pressed)
	crash_select_level_button = crash_screen.get_node("CenterContainer/VBoxContainer/SelectLevelButton")
	crash_select_level_button.pressed.connect(_on_endgame_select_level_pressed)
	crash_quit_to_menu_button = crash_screen.get_node("CenterContainer/VBoxContainer/QuitToMenuButton")
	crash_quit_to_menu_button.pressed.connect(_on_quit_to_menu_pressed)
	
	options_screen = OptionsScreenScene.instantiate()
	options_screen.visible = false
	ui_layer.add_child(options_screen)
	touch_controls_button = options_screen.get_node("CenterContainer/VBoxContainer/TouchControlsButton")
	soi_visibility_button = options_screen.get_node("CenterContainer/VBoxContainer/SOIVisibilityButton")
	back_button = options_screen.get_node("CenterContainer/VBoxContainer/BackButton")
	touch_controls_button.pressed.connect(_on_touch_controls_pressed)
	soi_visibility_button.pressed.connect(_on_soi_visibility_pressed)
	back_button.pressed.connect(_on_back_pressed)
	_setup_focus_neighbors_three(touch_controls_button, soi_visibility_button, back_button)
	
	_setup_pause_screen()
	_setup_level_select_screen()


func _setup_pause_screen() -> void:
	pause_screen = PauseScreenScene.instantiate()
	pause_screen.visible = false
	ui_layer.add_child(pause_screen)
	
	resume_button = pause_screen.get_node("CenterContainer/VBoxContainer/ResumeButton")
	pause_options_button = pause_screen.get_node("CenterContainer/VBoxContainer/OptionsButton")
	pause_select_level_button = pause_screen.get_node("CenterContainer/VBoxContainer/SelectLevelButton")
	quit_to_menu_button = pause_screen.get_node("CenterContainer/VBoxContainer/QuitToMenuButton")
	quit_to_desktop_button = pause_screen.get_node("CenterContainer/VBoxContainer/QuitToDesktopButton")
	
	resume_button.pressed.connect(_on_resume_pressed)
	pause_options_button.pressed.connect(_on_pause_options_pressed)
	pause_select_level_button.pressed.connect(_on_pause_select_level_pressed)
	quit_to_menu_button.pressed.connect(_on_quit_to_menu_pressed)
	quit_to_desktop_button.pressed.connect(_on_quit_to_desktop_pressed)
	
	_setup_focus_neighbors_five(resume_button, pause_options_button, pause_select_level_button, quit_to_menu_button, quit_to_desktop_button)


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


func _setup_focus_neighbors_five(button1: Button, button2: Button, button3: Button, button4: Button, button5: Button) -> void:
	button1.focus_neighbor_bottom = button2.get_path()
	button1.focus_neighbor_top = button5.get_path()
	button2.focus_neighbor_top = button1.get_path()
	button2.focus_neighbor_bottom = button3.get_path()
	button3.focus_neighbor_top = button2.get_path()
	button3.focus_neighbor_bottom = button4.get_path()
	button4.focus_neighbor_top = button3.get_path()
	button4.focus_neighbor_bottom = button5.get_path()
	button5.focus_neighbor_top = button4.get_path()
	button5.focus_neighbor_bottom = button1.get_path()


func _setup_level_select_screen() -> void:
	level_select_screen = LevelSelectScreenScene.instantiate()
	level_select_screen.visible = false
	ui_layer.add_child(level_select_screen)
	
	var play_button = level_select_screen.get_node("MainContainer/DetailPanel/MarginContainer/VBoxContainer/ButtonsContainer/PlayButton")
	play_button.pressed.connect(_on_level_play_button_pressed)
	
	level_select_back_button = level_select_screen.get_node("MainContainer/DetailPanel/MarginContainer/VBoxContainer/ButtonsContainer/BackButton")
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
	
	var restart_level_index = restart_level_button.get_index()
	vbox.add_child(next_level_button)
	vbox.move_child(next_level_button, restart_level_index)


func _setup_play_again_button() -> void:
	var vbox = game_won_screen.get_node("CenterContainer/VBoxContainer")
	play_again_button = Button.new()
	play_again_button.name = "PlayAgainButton"
	play_again_button.custom_minimum_size = Vector2(250, 55)
	play_again_button.add_theme_font_override("font", AudiowideFont)
	play_again_button.add_theme_font_size_override("font_size", 24)
	play_again_button.text = "PLAY AGAIN"
	play_again_button.pressed.connect(_on_play_again_pressed)
	
	# Add after restart level button
	var restart_level_index = restart_level_button.get_index()
	vbox.add_child(play_again_button)
	vbox.move_child(play_again_button, restart_level_index + 1)


var selected_level_id: int = 1

func _populate_level_buttons() -> void:
	var container = level_select_screen.get_node("MainContainer/LeftPanel/LevelCardsScroll/LevelCardsContainer")
	
	for child in container.get_children():
		child.queue_free()
	level_buttons.clear()
	
	if not LevelManager:
		return
	
	var level_ids = LevelManager.get_all_level_ids()
	for level_id in level_ids:
		var level = LevelManager.get_level(level_id)
		if not level:
			continue
		
		# Create level card
		var card = PanelContainer.new()
		card.custom_minimum_size = Vector2(0, 120)
		
		# Add margins to card
		var card_style = StyleBoxFlat.new()
		card_style.bg_color = Color(0.15, 0.15, 0.15, 0.9)
		card_style.content_margin_left = 20
		card_style.content_margin_right = 20
		card_style.content_margin_top = 15
		card_style.content_margin_bottom = 15
		card_style.corner_radius_top_left = 8
		card_style.corner_radius_top_right = 8
		card_style.corner_radius_bottom_left = 8
		card_style.corner_radius_bottom_right = 8
		card.add_theme_stylebox_override("panel", card_style)
		
		var card_vbox = VBoxContainer.new()
		card_vbox.add_theme_constant_override("separation", 8)
		card.add_child(card_vbox)
		
		# Level title and best score
		var title_hbox = HBoxContainer.new()
		card_vbox.add_child(title_hbox)
		
		var title_label = Label.new()
		title_label.add_theme_font_override("font", AudiowideFont)
		title_label.add_theme_font_size_override("font_size", 24)
		title_label.text = "Level %d: %s" % [level_id, level.level_name]
		title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title_hbox.add_child(title_label)
		
		var best_score = LevelManager.get_best_score(level_id)
		if best_score >= 0:
			var score_label = Label.new()
			score_label.add_theme_font_size_override("font_size", 18)
			score_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))
			score_label.text = "Best: %.0f%%" % best_score
			title_hbox.add_child(score_label)
		
		# Tags
		var tags_hbox = HBoxContainer.new()
		tags_hbox.add_theme_constant_override("separation", 8)
		card_vbox.add_child(tags_hbox)
		
		var tag_colors = {
			"Easy": Color(0.2, 0.8, 0.2),
			"Medium": Color(1.0, 0.8, 0.0),
			"Hard": Color(1.0, 0.4, 0.0),
			"Very Hard": Color(0.9, 0.1, 0.1),
			"Patched Conics": Color(0.4, 0.6, 1.0),
			"N-Body": Color(0.8, 0.4, 1.0),
			"Hybrid": Color(0.5, 0.9, 0.9),
		}
		
		for tag in level.tags:
			var tag_panel = PanelContainer.new()
			var tag_style = StyleBoxFlat.new()
			
			# Get color based on tag, default to gray
			var tag_color = tag_colors.get(tag, Color(0.4, 0.4, 0.4))
			tag_style.bg_color = tag_color
			
			# Make it pill-shaped
			tag_style.corner_radius_top_left = 10
			tag_style.corner_radius_top_right = 10
			tag_style.corner_radius_bottom_left = 10
			tag_style.corner_radius_bottom_right = 10
			tag_style.content_margin_left = 12
			tag_style.content_margin_right = 12
			tag_style.content_margin_top = 6
			tag_style.content_margin_bottom = 6
			tag_panel.add_theme_stylebox_override("panel", tag_style)
			
			var tag_label = Label.new()
			tag_label.add_theme_font_size_override("font_size", 13)
			tag_label.add_theme_color_override("font_color", Color(1, 1, 1))
			tag_label.text = tag
			tag_panel.add_child(tag_label)
			tags_hbox.add_child(tag_panel)
		
		# Make card clickable
		var btn = Button.new()
		btn.custom_minimum_size = Vector2(0, 120)
		btn.flat = true
		btn.pressed.connect(_on_level_card_selected.bind(level_id, level))
		btn.mouse_entered.connect(_update_level_detail_panel.bind(level))
		btn.focus_entered.connect(_on_level_card_focused.bind(level_id, level))
		
		var card_wrapper = Control.new()
		card_wrapper.custom_minimum_size = Vector2(0, 120)
		card_wrapper.add_child(card)
		card.set_anchors_preset(Control.PRESET_FULL_RECT)
		card_wrapper.add_child(btn)
		btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		
		container.add_child(card_wrapper)
		level_buttons.append(btn)
	
	if level_buttons.size() > 0:
		level_buttons[0].grab_focus()
		if level_ids.size() > 0:
			var first_level = LevelManager.get_level(level_ids[0])
			if first_level:
				_update_level_detail_panel(first_level)
				selected_level_id = level_ids[0]


func _on_level_card_selected(level_id: int, level: LevelConfig) -> void:
	selected_level_id = level_id
	_update_level_detail_panel(level)


func _on_level_card_focused(level_id: int, level: LevelConfig) -> void:
	selected_level_id = level_id
	_update_level_detail_panel(level)


func _on_level_play_button_pressed() -> void:
	if selected_level_id > 0:
		_on_level_button_pressed(selected_level_id)


func _update_level_detail_panel(level: LevelConfig) -> void:
	if not level or not level_select_screen:
		return
	
	var name_label = level_select_screen.get_node("MainContainer/DetailPanel/MarginContainer/VBoxContainer/LevelNameLabel")
	var desc_label = level_select_screen.get_node("MainContainer/DetailPanel/MarginContainer/VBoxContainer/DescriptionScroll/DescriptionLabel")
	var tags_container = level_select_screen.get_node("MainContainer/DetailPanel/MarginContainer/VBoxContainer/TagsContainer")
	var thumbnail_rect = level_select_screen.get_node("MainContainer/DetailPanel/MarginContainer/VBoxContainer/ThumbnailContainer/ThumbnailRect")
	
	name_label.text = level.level_name
	desc_label.text = level.description
	
	# Set thumbnail
	if level.thumbnail:
		thumbnail_rect.texture = level.thumbnail
	else:
		thumbnail_rect.texture = null
	
	# Clear and populate tags
	for child in tags_container.get_children():
		child.queue_free()
	
	var tag_colors = {
		"Easy": Color(0.2, 0.8, 0.2),
		"Medium": Color(1.0, 0.8, 0.0),
		"Hard": Color(1.0, 0.4, 0.0),
		"Very Hard": Color(0.9, 0.1, 0.1),
		"Patched Conics": Color(0.4, 0.6, 1.0),
		"N-Body": Color(0.8, 0.4, 1.0),
		"Hybrid": Color(0.5, 0.9, 0.9),
	}
	
	for tag in level.tags:
		var tag_panel = PanelContainer.new()
		var style = StyleBoxFlat.new()
		
		# Get color based on tag, default to gray
		var tag_color = tag_colors.get(tag, Color(0.4, 0.4, 0.4))
		style.bg_color = tag_color
		
		# Make it pill-shaped with large corner radius
		style.corner_radius_top_left = 12
		style.corner_radius_top_right = 12
		style.corner_radius_bottom_left = 12
		style.corner_radius_bottom_right = 12
		style.content_margin_left = 15
		style.content_margin_right = 15
		style.content_margin_top = 8
		style.content_margin_bottom = 8
		tag_panel.add_theme_stylebox_override("panel", style)
		
		var tag_label = Label.new()
		tag_label.add_theme_font_size_override("font_size", 16)
		tag_label.add_theme_color_override("font_color", Color(1, 1, 1))
		tag_label.text = tag
		tag_panel.add_child(tag_label)
		tags_container.add_child(tag_panel)


func _process(_delta: float) -> void:
	if current_state != GameState.PLAYING or orbiting_body == null:
		return
	
	if not is_instance_valid(orbiting_body):
		return
	
	if orbiting_body.is_ship_exploded():
		show_crash_screen()
	elif orbiting_body.current_fuel <= 0:
		show_game_over()
	elif orbiting_body.is_in_stable_orbit():
		show_game_won()


func _unhandled_input(event: InputEvent) -> void:
	if Input.is_action_just_pressed("restart"):
		if current_state == GameState.PLAYING:
			restart_game()
		return
	
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
	
	if Input.is_action_just_pressed("ui_cancel"):
		if options_screen.visible:
			_on_back_pressed()
		elif level_select_screen.visible:
			_on_level_select_back_pressed()
		elif current_state == GameState.PAUSED:
			_on_resume_pressed()
		return
	
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
	
	# Hide HUD and touch controls on menu
	if hud:
		hud.visible = false
	if touch_controls_manager:
		touch_controls_manager.visible = false
	
	# Reset to level 1 when returning to main menu
	if LevelManager:
		LevelManager.current_level_id = 1
	
	# Load level 1 as menu background
	_load_menu_background()


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
	if orbiting_body and is_instance_valid(orbiting_body):
		fuel_percent = orbiting_body.get_fuel_percentage()
	
	var stats_label = game_won_screen.get_node("CenterContainer/VBoxContainer/StatsLabel")
	if stats_label and orbiting_body:
		stats_label.text = "Fuel remaining: %.1f%%" % fuel_percent
	
	if LevelManager:
		LevelManager.complete_level(fuel_percent)
		
		if next_level_button:
			next_level_button.visible = LevelManager.has_next_level()
			if next_level_button.visible:
				next_level_button.grab_focus()
				if play_again_button:
					play_again_button.visible = false
			else:
				if play_again_button:
					play_again_button.visible = true
					play_again_button.grab_focus()
				else:
					restart_level_button.grab_focus()
	else:
		restart_level_button.grab_focus()
	
	if Events:
		Events.game_won.emit()


func show_crash_screen() -> void:
	current_state = GameState.CRASHED
	_hide_all_screens()
	crash_screen.visible = true
	crash_restart_button.grab_focus()


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
	_update_soi_visibility_button_text()
	touch_controls_button.grab_focus()


func show_options_from_pause() -> void:
	_options_opened_from_pause = true
	pause_screen.visible = false
	options_screen.visible = true
	_update_touch_controls_button_text()
	_update_soi_visibility_button_text()
	touch_controls_button.grab_focus()


func show_level_select_screen(context: LevelSelectContext = LevelSelectContext.MAIN_MENU) -> void:
	_level_select_context = context
	current_state = GameState.LEVEL_SELECT
	_hide_all_screens()
	level_select_screen.visible = true
	_populate_level_buttons()
	
	for btn in level_buttons:
		if not btn.disabled:
			btn.grab_focus()
			break


func _unload_current_level() -> void:
	if current_level_root and is_instance_valid(current_level_root):
		current_level_root.queue_free()
	current_level_root = null
	orbiting_body = null
	camera = null
	orbit_visualization = null


func _load_menu_background() -> void:
	# Unload any existing level first
	_unload_current_level()
	
	# Load level 1 as the menu background
	var level_scene_path = "res://scenes/levels/level_1.tscn"
	var level_scene = load(level_scene_path)
	if not level_scene:
		return
	
	current_level_root = level_scene.instantiate()
	get_tree().root.add_child(current_level_root)
	
	# Find and disable the ship (hide it, disable physics)
	var player_node = current_level_root.get_node_or_null("Player")
	if player_node:
		var ship = player_node.get_node_or_null("Ship")
		if ship:
			ship.visible = false
			ship.set_physics_process(false)
			ship.set_process(false)
	
	# Find camera and set it to a nice overview position
	camera = current_level_root.get_node_or_null("World/Camera2D")
	if camera:
		# Position camera to show a nice view of the level
		camera.global_position = Vector2(1500, 1000)
		camera.zoom = Vector2(0.4, 0.4)
		# Disable camera follow
		camera.set_process(false)


func start_game() -> void:
	get_tree().paused = false
	_load_current_level()
	
	# Release all input actions to prevent menu key presses from bleeding into gameplay
	# This prevents Space (ui_accept) from triggering thrust when starting from level select
	Input.action_release("thrust")
	Input.action_release("rotate_left")
	Input.action_release("rotate_right")
	Input.action_release("toggle_prograde")
	Input.action_release("toggle_retrograde")
	Input.action_release("toggle_orientation")
	
	current_state = GameState.PLAYING
	_hide_all_screens()
	
	# Show HUD and touch controls during gameplay
	if hud:
		hud.visible = true
	if touch_controls_manager:
		touch_controls_manager.visible = true
	
	if Events:
		Events.game_started.emit()


func resume_game() -> void:
	get_tree().paused = false
	
	# Release all input actions to prevent menu key presses from bleeding into gameplay
	Input.action_release("thrust")
	Input.action_release("rotate_left")
	Input.action_release("rotate_right")
	Input.action_release("toggle_prograde")
	Input.action_release("toggle_retrograde")
	Input.action_release("toggle_orientation")
	
	current_state = GameState.PLAYING
	_hide_all_screens()
	
	# Ensure HUD and touch controls are visible
	if hud:
		hud.visible = true
	if touch_controls_manager:
		touch_controls_manager.visible = true
	
	if Events:
		Events.game_resumed.emit()


func restart_game() -> void:
	get_tree().paused = false
	_load_current_level()
	
	# Release all input actions to prevent any stuck inputs
	Input.action_release("thrust")
	Input.action_release("rotate_left")
	Input.action_release("rotate_right")
	Input.action_release("toggle_prograde")
	Input.action_release("toggle_retrograde")
	Input.action_release("toggle_orientation")
	
	current_state = GameState.PLAYING
	_hide_all_screens()
	
	# Show HUD and touch controls during gameplay
	if hud:
		hud.visible = true
	if touch_controls_manager:
		touch_controls_manager.visible = true
	
	if Events:
		Events.game_restarted.emit()


func _load_current_level() -> void:
	# Unload existing level
	_unload_current_level()
	
	if not LevelManager:
		return
	
	var level_config = LevelManager.get_current_level()
	if not level_config:
		return
	
	# Load the level scene as the new current scene
	var level_scene_path = LevelManager.get_level_scene_path(LevelManager.current_level_id)
	if level_scene_path.is_empty():
		return
	
	var level_scene = load(level_scene_path)
	if not level_scene:
		return
	
	current_level_root = level_scene.instantiate()
	get_tree().root.add_child(current_level_root)
	
	# Find references in the loaded level
	_find_level_references()
	
	# Store starting position for restarts
	if orbiting_body:
		_ship_start_position = orbiting_body.global_position
		_ship_start_velocity = level_config.ship_start_velocity
	
	# Initialize ship with level settings
	_initialize_ship(level_config)
	
	# Connect signals
	_connect_ship_signals()
	
	if Events:
		Events.level_loaded.emit(level_config.level_id)


func _find_level_references() -> void:
	if not current_level_root:
		return
	
	# Find ship
	var player_node = current_level_root.get_node_or_null("Player")
	if player_node:
		orbiting_body = player_node.get_node_or_null("Ship")
	
	# Find other components from level scene
	camera = current_level_root.get_node_or_null("World/Camera2D")
	orbit_visualization = current_level_root.get_node_or_null("World/OrbitVisualization")
	
	# Find planets and set up ship references
	var planets_node = current_level_root.get_node_or_null("Planets")
	if planets_node and orbiting_body:
		var central_bodies: Array = []
		var target_body: Node2D = null
		
		for planet in planets_node.get_children():
			central_bodies.append(planet)
			if "is_target" in planet and planet.is_target:
				target_body = planet
		
		orbiting_body.central_bodies = central_bodies
		orbiting_body.target_body = target_body
	
	# Update HUD with new ship reference
	if hud and hud.has_method("set_ship"):
		hud.set_ship(orbiting_body)
	if hud and camera:
		hud.camera = camera
	
	# Update orbit visualization with new ship reference
	if orbit_visualization and orbit_visualization.has_method("set_ship"):
		orbit_visualization.set_ship(orbiting_body)
	
	# Update camera with new ship reference
	if camera and camera.has_method("set_follow_target"):
		camera.set_follow_target(orbiting_body)
	
	# Restore saved zoom level
	if camera:
		camera.zoom = Vector2(_saved_zoom, _saved_zoom)


func _initialize_ship(level_config: LevelConfig) -> void:
	if not orbiting_body:
		return
	
	orbiting_body.current_fuel = level_config.max_fuel
	orbiting_body.max_fuel = level_config.max_fuel
	orbiting_body.stable_orbit_time_required = level_config.stable_orbit_time
	# Use ship's own initial_velocity export instead of level config
	orbiting_body.velocity = orbiting_body.initial_velocity
	orbiting_body.thrust_angle = 0.0
	orbiting_body.time_in_stable_orbit = 0.0
	orbiting_body.orbit_distance_samples.clear()
	orbiting_body.total_orbit_angle = 0.0
	orbiting_body.reset_explosion()


func _connect_ship_signals() -> void:
	if orbiting_body and orbiting_body.has_signal("ship_exploded"):
		if orbiting_body.ship_exploded.is_connected(_on_ship_exploded):
			orbiting_body.ship_exploded.disconnect(_on_ship_exploded)
		orbiting_body.ship_exploded.connect(_on_ship_exploded)


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


func _update_soi_visibility_button_text() -> void:
	if not soi_visibility_button:
		return
	var state_text := "On" if soi_visible else "Off"
	soi_visibility_button.text = "SOI Display: " + state_text


func _on_start_pressed() -> void:
	start_game()


func _on_restart_pressed() -> void:
	restart_game()


func _on_play_again_pressed() -> void:
	if LevelManager:
		LevelManager.set_current_level(1)
	restart_game()


func _on_options_pressed() -> void:
	show_options_screen()


func _on_discord_pressed() -> void:
	OS.shell_open("https://discord.gg/S3Cg4ZEUyr")


func _on_level_select_pressed() -> void:
	show_level_select_screen(LevelSelectContext.MAIN_MENU)


func _on_level_select_back_pressed() -> void:
	level_select_screen.visible = false
	
	match _level_select_context:
		LevelSelectContext.MAIN_MENU:
			start_screen.visible = true
			start_button.grab_focus()
		LevelSelectContext.PAUSE:
			pause_screen.visible = true
			resume_button.grab_focus()
		LevelSelectContext.END_GAME:
			# Go back to main menu since the game ended
			get_tree().paused = false
			show_start_screen()


func _on_level_button_pressed(level_id: int) -> void:
	# Unpause if we came from pause or end game
	get_tree().paused = false
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


func _on_pause_select_level_pressed() -> void:
	show_level_select_screen(LevelSelectContext.PAUSE)


func _on_endgame_select_level_pressed() -> void:
	show_level_select_screen(LevelSelectContext.END_GAME)


func _on_quit_to_menu_pressed() -> void:
	get_tree().paused = false
	show_start_screen()


func _on_quit_to_desktop_pressed() -> void:
	get_tree().quit()


func _on_touch_controls_pressed() -> void:
	if touch_controls_manager and touch_controls_manager.has_method("cycle_preference"):
		touch_controls_manager.cycle_preference()
		_update_touch_controls_button_text()


func _on_soi_visibility_pressed() -> void:
	soi_visible = not soi_visible
	_update_soi_visibility_button_text()
	if Events:
		Events.soi_visibility_changed.emit(soi_visible)


func _on_camera_zoom_changed(zoom_level: float) -> void:
	_saved_zoom = zoom_level


func _on_ship_exploded() -> void:
	pass


func is_game_active() -> bool:
	return current_state == GameState.PLAYING

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

# Music tracks
const MUSIC_TRACKS: Array[AudioStream] = [
	preload("res://Assets/tracks/Star Drifter.wav"),
	preload("res://Assets/tracks/Travelling Space.wav")
]

var current_state: GameState = GameState.START_SCREEN

# Background music player
var music_player: AudioStreamPlayer = null

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
var global_rank_panel: PanelContainer  # For displaying player's global rank with pulsing effect
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
var music_button: Button
var player_name_label: Label
var player_name_edit: LineEdit
var save_name_button: Button
var random_name_button: Button
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
var _selected_level_id: int = -1  # Currently selected level for detail display
var _leaderboard_cache: Dictionary = {}  # Cache of leaderboards {level_id: entries_array}
var _cache_timestamp: Dictionary = {}  # Track when each cache entry was created
var _active_fetch_tasks: Dictionary = {}  # Track active fetch tasks {level_id: task_id}
const CACHE_EXPIRY_SECONDS: int = 300  # Cache expires after 5 minutes

# Store initial ship position for restart
var _ship_start_position: Vector2
var _ship_start_velocity: Vector2

# Persistent camera zoom (survives level changes/restarts)
var _saved_zoom: float = 0.8  # Default zoom level

# SOI visibility setting
var soi_visible: bool = true

# Music setting
var music_enabled: bool = true

# Level time tracking
var _level_start_time: float = 0.0
var _level_elapsed_time: float = 0.0

# Settings save path
const SETTINGS_SAVE_PATH := "user://game_settings.save"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Load saved settings
	_load_settings()
	
	# Clear all leaderboard caches on new game launch
	print("[GameController] _ready() - Clearing all caches on game launch")
	print("[GameController] Before clear - Cache size: ", _leaderboard_cache.size())
	_leaderboard_cache.clear()
	_cache_timestamp.clear()
	_active_fetch_tasks.clear()
	print("[GameController] After clear - Cache size: ", _leaderboard_cache.size())
	
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
	
	# Setup background music player
	_setup_music_player()
	
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
			
			if _selected_level_id > 0 and (play_button.has_focus() or has_level_button_focus):
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
	
	# Apply pulsing effect to "Coming soon" label
	var coming_soon_label = start_button.get_node("ComingSoonLabel")
	if coming_soon_label:
		start_scale_pulse([coming_soon_label], 1.1, 0.6)
	
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
	_setup_global_rank_panel()
	
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
	music_button = options_screen.get_node("CenterContainer/VBoxContainer/MusicButton")
	player_name_label = options_screen.get_node("CenterContainer/VBoxContainer/PlayerNameLabel")
	player_name_edit = options_screen.get_node("CenterContainer/VBoxContainer/PlayerNameEdit")
	save_name_button = options_screen.get_node("CenterContainer/VBoxContainer/NameButtonsContainer/SaveNameButton")
	random_name_button = options_screen.get_node("CenterContainer/VBoxContainer/NameButtonsContainer/RandomNameButton")
	back_button = options_screen.get_node("CenterContainer/VBoxContainer/BackButton")
	touch_controls_button.pressed.connect(_on_touch_controls_pressed)
	soi_visibility_button.pressed.connect(_on_soi_visibility_pressed)
	music_button.pressed.connect(_on_music_pressed)
	save_name_button.pressed.connect(_on_save_name_pressed)
	random_name_button.pressed.connect(_on_random_name_pressed)
	back_button.pressed.connect(_on_back_pressed)
	_update_player_name_display()
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


## Create leaderboard container in the detail panel
func _setup_leaderboard_container() -> void:
	var vbox = level_select_screen.get_node("MainContainer/DetailPanel/MarginContainer/VBoxContainer")
	
	# Create leaderboard section
	var leaderboard_container = VBoxContainer.new()
	leaderboard_container.name = "LeaderboardContainer"
	leaderboard_container.add_theme_constant_override("separation", 8)
	
	# Leaderboard title
	var title_label = Label.new()
	title_label.name = "LeaderboardTitle"
	title_label.text = "LEADERBOARD"
	title_label.add_theme_font_override("font", AudiowideFont)
	title_label.add_theme_font_size_override("font_size", 24)
	title_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.0))
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	leaderboard_container.add_child(title_label)
	
	# Add spacer before leaderboard
	var spacer = Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(spacer)
	
	vbox.add_child(leaderboard_container)


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


func _setup_global_rank_panel() -> void:
	var vbox = game_won_screen.get_node("CenterContainer/VBoxContainer")
	
	# Create panel container for global rank display
	global_rank_panel = PanelContainer.new()
	global_rank_panel.name = "GlobalRankPanel"
	global_rank_panel.custom_minimum_size = Vector2(500, 120)
	
	# Style the panel with vibrant colors
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.3, 0.95)  # Dark blue background
	style.border_color = Color(0.0, 0.8, 1.0)  # Bright cyan border
	style.border_width_left = 3
	style.border_width_right = 3
	style.border_width_top = 3
	style.border_width_bottom = 3
	style.corner_radius_top_left = 15
	style.corner_radius_top_right = 15
	style.corner_radius_bottom_left = 15
	style.corner_radius_bottom_right = 15
	style.content_margin_left = 20
	style.content_margin_right = 20
	style.content_margin_top = 15
	style.content_margin_bottom = 15
	global_rank_panel.add_theme_stylebox_override("panel", style)
	
	# Create VBox for content
	var content_vbox = VBoxContainer.new()
	content_vbox.name = "VBoxContainer"
	content_vbox.add_theme_constant_override("separation", 5)
	global_rank_panel.add_child(content_vbox)
	
	# Title label
	var title_label = Label.new()
	title_label.name = "TitleLabel"
	title_label.add_theme_font_override("font", AudiowideFont)
	title_label.add_theme_font_size_override("font_size", 20)
	title_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.text = "GLOBAL RANKING"
	content_vbox.add_child(title_label)
	
	# Rank label (large, pulsing with BBCode)
	var rank_label = RichTextLabel.new()
	rank_label.name = "RankLabel"
	rank_label.bbcode_enabled = true
	rank_label.fit_content = true
	rank_label.scroll_active = false
	rank_label.add_theme_font_override("normal_font", AudiowideFont)
	rank_label.add_theme_font_size_override("normal_font_size", 42)
	rank_label.add_theme_color_override("default_color", Color(0.0, 1.0, 0.8))  # Bright cyan/green
	rank_label.custom_minimum_size = Vector2(450, 60)
	rank_label.text = "[center]Loading...[/center]"
	content_vbox.add_child(rank_label)
	
	# Percentage label (medium, pulsing with BBCode)
	var percentage_label = RichTextLabel.new()
	percentage_label.name = "PercentageLabel"
	percentage_label.bbcode_enabled = true
	percentage_label.fit_content = true
	percentage_label.scroll_active = false
	percentage_label.add_theme_font_override("normal_font", AudiowideFont)
	percentage_label.add_theme_font_size_override("normal_font_size", 24)
	percentage_label.add_theme_color_override("default_color", Color(1.0, 0.85, 0.0))  # Gold
	percentage_label.custom_minimum_size = Vector2(450, 40)
	percentage_label.text = ""
	content_vbox.add_child(percentage_label)
	
	# Insert after stats label
	var stats_label = vbox.get_node_or_null("StatsLabel")
	if stats_label:
		var stats_index = stats_label.get_index()
		vbox.add_child(global_rank_panel)
		vbox.move_child(global_rank_panel, stats_index + 1)
	else:
		vbox.add_child(global_rank_panel)
	
	global_rank_panel.visible = true  # Always visible


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
		
		# Main horizontal layout: content on left, grade on right
		var card_hbox = HBoxContainer.new()
		card_hbox.add_theme_constant_override("separation", 20)
		card.add_child(card_hbox)
		
		var card_vbox = VBoxContainer.new()
		card_vbox.add_theme_constant_override("separation", 8)
		card_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card_hbox.add_child(card_vbox)
		
		# Level title and best score
		var title_hbox = HBoxContainer.new()
		card_vbox.add_child(title_hbox)
		
		var title_label = Label.new()
		title_label.add_theme_font_override("font", AudiowideFont)
		title_label.add_theme_font_size_override("font_size", 24)
		title_label.text = "Level %d: %s" % [level_id, level.level_name]
		title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		title_hbox.add_child(title_label)
		
		var best_score_data = LevelManager.get_best_score(level_id)
		if best_score_data["score"] > 0:
			var score_vbox = VBoxContainer.new()
			score_vbox.add_theme_constant_override("separation", 2)
			title_hbox.add_child(score_vbox)
			
			var score_label = Label.new()
			score_label.add_theme_font_size_override("font_size", 18)
			score_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))
			score_label.text = "Best: %d pts" % best_score_data["score"]
			score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			score_vbox.add_child(score_label)
			
			var details_label = Label.new()
			details_label.add_theme_font_size_override("font_size", 14)
			details_label.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))
			var time_str = ScoringSystem.format_time(best_score_data["time"])
			details_label.text = "%s | %.0f%% fuel" % [time_str, best_score_data["fuel"]]
			details_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			score_vbox.add_child(details_label)
			
			# Calculate grade from stored best score data
			var grade_score_data = ScoringSystem.calculate_score(
				best_score_data["time"],
				best_score_data["fuel"],
				level.s_rank_target_time,
				level.s_rank_target_fuel,
				level.max_fuel
			)
			var grade = grade_score_data["grade"]
			
			# Large grade display on the right
			var grade_container = CenterContainer.new()
			grade_container.custom_minimum_size = Vector2(100, 0)
			card_hbox.add_child(grade_container)
			
			# Wrapper control for absolute positioning
			var grade_wrapper = Control.new()
			grade_wrapper.custom_minimum_size = Vector2(80, 90)
			grade_container.add_child(grade_wrapper)
			
			# Grade letter (centered)
			var grade_label = Label.new()
			grade_label.add_theme_font_override("font", AudiowideFont)
			grade_label.add_theme_font_size_override("font_size", 64)
			grade_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			grade_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			grade_label.set_anchors_preset(Control.PRESET_FULL_RECT)
			
			# Color code grades
			var grade_color: Color
			match grade:
				"S":
					grade_color = Color(1.0, 0.85, 0.0)  # Gold
				"A+", "A", "A-":
					grade_color = Color(0.3, 1.0, 0.5)  # Green
				"B+", "B", "B-":
					grade_color = Color(0.4, 0.8, 1.0)  # Blue
				"C+", "C", "C-":
					grade_color = Color(1.0, 0.8, 0.4)  # Orange
				"D+", "D":
					grade_color = Color(1.0, 0.5, 0.3)  # Red-Orange
				_:
					grade_color = Color(0.6, 0.6, 0.6)  # Gray
			
			grade_label.add_theme_color_override("font_color", grade_color)
			grade_label.text = grade
			grade_wrapper.add_child(grade_label)
			
			# "Tier" label anchored at top center (added after so it renders on top)
			var tier_label = Label.new()
			tier_label.add_theme_font_override("font", AudiowideFont)
			tier_label.add_theme_font_size_override("font_size", 16)
			tier_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			tier_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
			tier_label.text = "Tier"
			tier_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
			tier_label.position.y = -5
			grade_wrapper.add_child(tier_label)
		
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
				_selected_level_id = level_ids[0]
				_update_level_detail_panel(first_level)


func _on_level_card_selected(level_id: int, level: LevelConfig) -> void:
	_selected_level_id = level_id
	_update_level_detail_panel(level)


func _on_level_card_focused(level_id: int, level: LevelConfig) -> void:
	_selected_level_id = level_id
	_update_level_detail_panel(level)


func _on_level_play_button_pressed() -> void:
	if _selected_level_id > 0:
		_on_level_button_pressed(_selected_level_id)


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
	
	# Fetch and display leaderboard for this level (only if screen is visible)
	if LootLockerManager and level_select_screen and level_select_screen.visible:
		_fetch_level_leaderboard(level.level_id)
		# DEBUG: Use mock leaderboard (uncomment below and comment above):
		# _load_mock_leaderboard(level.level_id)


## Generate mock leaderboard data for debugging (20 entries + player rank)
func _generate_mock_leaderboard(level_id: int) -> Dictionary:
	var entries = []
	var player_names = [
		"SpeedRunner", "OrbitMaster", "RocketAce", "StarPilot", "CosmicKing",
		"AstroNinja", "GravityGuru", "FuelSaver", "TimeLord", "SpaceNav",
		"OrbitalPro", "SkyWalker", "NovaHunter", "CelestialAce", "QuickOrbit",
		"ThunderBolt", "SolarFlare", "MoonDancer", "StarChaser", "NebulaDrift"
	]
	
	# Generate 20 top entries with decreasing scores
	var base_score = 10000
	var base_time = 60.0  # 1 minute
	var base_fuel = 95.0
	
	for i in range(20):
		var rank = i + 1
		var score = base_score - (i * 200) - randi() % 100
		var time = base_time + (i * 3.5) + randf() * 2.0
		var fuel = base_fuel - (i * 2.0) - randf() * 3.0
		
		entries.append({
			"rank": rank,
			"score": score,
			"member_id": player_names[i],
			"metadata": {
				"time": time,
				"fuel": max(0.0, fuel)
			}
		})
	
	# Generate player's rank data (outside top 20)
	var player_rank_data = {
		"success": true,
		"rank": 42,  # Player is ranked 42nd
		"score": base_score - 5000,
		"member_id": PlayerProfile.get_player_name(),
		"metadata": {
			"time": base_time + 85.0,
			"fuel": 45.0
		}
	}
	
	return {
		"entries": entries,
		"player_rank": player_rank_data
	}

## Load mock leaderboard for debugging
func _load_mock_leaderboard(level_id: int) -> void:
	# Set as selected level
	_selected_level_id = level_id
	
	var mock_data = _generate_mock_leaderboard(level_id)
	
	# Store in cache
	_leaderboard_cache[level_id] = mock_data
	_cache_timestamp[level_id] = Time.get_unix_time_from_system()
	
	# Display immediately
	_display_cached_leaderboard(level_id)

## Invalidate cached leaderboard for a specific level
func _invalidate_leaderboard_cache(level_id: int) -> void:
	if _leaderboard_cache.has(level_id):
		_leaderboard_cache.erase(level_id)
	if _cache_timestamp.has(level_id):
		_cache_timestamp.erase(level_id)

## Check if cached leaderboard is still valid
func _is_cache_valid(level_id: int) -> bool:
	if not _leaderboard_cache.has(level_id):
		return false
	
	var cache_age = Time.get_unix_time_from_system() - _cache_timestamp.get(level_id, 0)
	return cache_age < CACHE_EXPIRY_SECONDS

## Fetch and display leaderboard for a specific level
func _fetch_level_leaderboard(level_id: int) -> void:
	# Track which level is selected for display
	_selected_level_id = level_id
	
	# Get leaderboard container in side panel
	var leaderboard_container = level_select_screen.get_node_or_null("MainContainer/LeaderboardPanel/MarginContainer/VBoxContainer/LeaderboardScroll/LeaderboardEntries")
	if not leaderboard_container:
		return
	
	# Check if we have valid cached data for the current level
	print("[GameController] _fetch_level_leaderboard() - Checking cache for level ", level_id)
	print("[GameController] Total cache size: ", _leaderboard_cache.size())
	print("[GameController] Cache has level ", level_id, ": ", _leaderboard_cache.has(level_id))
	if _is_cache_valid(level_id):
		print("[GameController] Using VALID cache for level ", level_id)
		_display_cached_leaderboard(level_id)
		return
	
	# Show loading indicator immediately
	_show_loading_indicator(leaderboard_container)
	
	# Fetch current level with display
	await _fetch_leaderboard_with_display(level_id)


## Show loading indicator in leaderboard container
func _show_loading_indicator(container: Control) -> void:
	# Clear existing entries
	for child in container.get_children():
		child.queue_free()
	
	var loading_label = Label.new()
	loading_label.text = "Loading leaderboard..."
	loading_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(loading_label)


## Fetch leaderboard and display it (foreground task)
func _fetch_leaderboard_with_display(level_id: int) -> void:
	# Generate unique task ID
	var task_id = Time.get_ticks_msec()
	_active_fetch_tasks[level_id] = task_id
	
	# Fetch top 20 leaderboard entries
	print("[GameController] Fetching leaderboard from LootLocker for level ", level_id)
	LootLockerManager.fetch_leaderboard(level_id, 20)
	var result = await LootLockerManager.leaderboard_fetched
	
	# Check if this task is still active (not cancelled by a new selection)
	if not _active_fetch_tasks.has(level_id) or _active_fetch_tasks[level_id] != task_id:
		print("[GameController] Task cancelled for level ", level_id)
		return
	
	var success: bool = result[0]
	var returned_level_id: int = result[1]
	var entries: Array = result[2]
	
	print("[GameController] LootLocker fetch result - Success: ", success, ", Level: ", returned_level_id, ", Entries: ", entries.size())
	
	# Fetch player's rank
	var player_rank_data: Dictionary = {}
	if LootLockerManager.player_id > 0 and success:
		var rank_result = await LootLockerManager.fetch_player_rank(level_id)
		
		# Check again if task is still active after await
		if not _active_fetch_tasks.has(level_id) or _active_fetch_tasks[level_id] != task_id:
			return
		
		if rank_result["success"]:
			player_rank_data = rank_result
	
	# Store in cache if successful
	if success:
		print("[GameController] Storing ", entries.size(), " entries in cache for level ", returned_level_id)
		_leaderboard_cache[returned_level_id] = {
			"entries": entries,
			"player_rank": player_rank_data
		}
		_cache_timestamp[returned_level_id] = Time.get_unix_time_from_system()
		print("[GameController] Cache now has ", _leaderboard_cache.size(), " levels stored")
	
	# Only display if this is still the selected level
	if _selected_level_id != level_id:
		_active_fetch_tasks.erase(level_id)
		return
	
	# Display the leaderboard
	_display_cached_leaderboard(level_id)
	
	# Clean up task tracking
	_active_fetch_tasks.erase(level_id)


## Fetch and display player's global rank on game won screen
func _fetch_and_display_global_rank(level_id: int) -> void:
	if not global_rank_panel:
		push_error("[GameController] ERROR: global_rank_panel is null!")
		return
	
	# Get labels
	var rank_label = global_rank_panel.get_node("VBoxContainer/RankLabel")
	var percentage_label = global_rank_panel.get_node("VBoxContainer/PercentageLabel")
	
	if not rank_label or not percentage_label:
		push_error("[GameController] ERROR: Labels not found!")
		return
	
	# Check if LootLockerManager is available
	if not LootLockerManager:
		rank_label.text = "[center]Connect to Internet[/center]"
		percentage_label.text = "[center]to submit scores & compete![/center]"
		return
	
	# Show loading state
	rank_label.text = "[center]Loading...[/center]"
	percentage_label.text = ""
	
	# Wait a moment for score to be processed
	await get_tree().create_timer(0.5).timeout
	
	# Fetch player's rank
	var rank_result = await LootLockerManager.fetch_player_rank(level_id)
	
	if not rank_result["success"]:
		rank_label.text = "[center]Connect to Internet[/center]"
		percentage_label.text = "[center]to submit scores & compete![/center]"
		return
	
	var player_rank: int = rank_result.get("rank", 0)
	if player_rank == 0:
		rank_label.text = "[center]No Rank Yet[/center]"
		percentage_label.text = "[center]Complete more levels to rank![/center]"
		return
	
	# Fetch total number of players for percentage calculation
	LootLockerManager.fetch_leaderboard(level_id, 1)  # Just need metadata
	var leaderboard_result = await LootLockerManager.leaderboard_fetched
	var success: bool = leaderboard_result[0]
	
	if not success:
		print("[GameController] Failed to fetch leaderboard for total count")
		rank_label.text = "Connect to Internet"
		percentage_label.text = "to submit scores & compete!"
		return
	
	# Estimate total players (since LootLocker doesn't give us exact count, use rank as minimum)
	# In a real scenario, you'd get this from the API metadata
	var total_players: int = player_rank  # Conservative estimate
	
	# For better estimate, if we have cached data with many entries, use that
	if _leaderboard_cache.has(level_id):
		var entries = _leaderboard_cache[level_id].get("entries", [])
		if entries.size() > 0:
			var last_entry = entries[entries.size() - 1]
			if last_entry.has("rank"):
				total_players = max(total_players, last_entry["rank"])
	
	# Calculate percentage (lower is better)
	var percentage: float = (float(player_rank) / float(total_players)) * 100.0
	percentage = min(percentage, 100.0)  # Cap at 100%
	
	# Update labels with success
	rank_label.text = "[center]RANK #%d[/center]" % player_rank
	percentage_label.text = "[center]Top %.1f%% of players[/center]" % percentage
	
	# Start pulsing animation only on rank label
	start_scale_pulse([rank_label])


## Create synchronized scale pulsing animation for any controls
## Pass an array of controls to pulse together synchronously
func start_scale_pulse(controls: Array, scale_amount: float = 1.15, duration: float = 0.5) -> void:
	if controls.is_empty():
		return
	
	# Set pivot offset to center for each control to prevent shifting during scale
	for control in controls:
		if control:
			control.pivot_offset = control.size / 2.0
	
	# Create a single tween for synchronized pulsing
	var tween = create_tween()
	tween.set_loops()
	tween.set_parallel(true)  # All controls pulse at the same time
	
	# Pulse all controls from scale 1.0 to scale_amount
	for control in controls:
		if control:
			tween.tween_property(control, "scale", Vector2(scale_amount, scale_amount), duration).set_trans(Tween.TRANS_SINE)
	
	tween.set_parallel(false)
	
	# Pulse back to normal scale
	for control in controls:
		if control:
			tween.tween_property(control, "scale", Vector2(1.0, 1.0), duration).set_trans(Tween.TRANS_SINE)


## Show encouragement message when score isn't a new best
func _show_rank_encouragement_message(level_id: int) -> void:
	if not global_rank_panel:
		return
	
	# Get labels
	var rank_label = global_rank_panel.get_node("VBoxContainer/RankLabel")
	var percentage_label = global_rank_panel.get_node("VBoxContainer/PercentageLabel")
	
	if not rank_label or not percentage_label:
		return
	
	# Fetch current rank to show (not a new best, but still show current standing)
	if not LootLockerManager:
		rank_label.text = "[center]Connect to Internet[/center]"
		percentage_label.text = "[center]to submit scores & compete![/center]"
		return
	
	rank_label.text = "[center]Loading...[/center]"
	percentage_label.text = ""
	
	var rank_result = await LootLockerManager.fetch_player_rank(level_id)
	
	if not rank_result["success"]:
		rank_label.text = "[center]Connect to Internet[/center]"
		percentage_label.text = "[center]to submit scores & compete![/center]"
		return
	
	var player_rank: int = rank_result.get("rank", 0)
	if player_rank == 0:
		rank_label.text = "[center]No Rank Yet[/center]"
		percentage_label.text = "[center]Complete more levels![/center]"
		return
	
	# Get the player's best score from the rank result
	var best_score: int = rank_result.get("score", 0)
	
	# Show current rank and best score
	rank_label.text = "[center]Current: Rank #%d[/center]" % player_rank
	percentage_label.text = "[center]Your Best: %d pts | Beat it for a new rank![/center]" % best_score


## Reset global rank panel to loading state
func _reset_global_rank_panel() -> void:
	if not global_rank_panel:
		return
	
	var rank_label = global_rank_panel.get_node_or_null("VBoxContainer/RankLabel")
	var percentage_label = global_rank_panel.get_node_or_null("VBoxContainer/PercentageLabel")
	
	if rank_label:
		rank_label.text = "[center]Loading...[/center]"
		# Reset modulate to default
		rank_label.modulate = Color(1.0, 1.0, 1.0, 1.0)
	
	if percentage_label:
		percentage_label.text = ""
		# Reset modulate to default
		percentage_label.modulate = Color(1.0, 1.0, 1.0, 1.0)


## Display cached leaderboard data
func _display_cached_leaderboard(level_id: int) -> void:
	print("[GameController] _display_cached_leaderboard called for level ", level_id)
	
	var leaderboard_container = level_select_screen.get_node_or_null("MainContainer/LeaderboardPanel/MarginContainer/VBoxContainer/LeaderboardScroll/LeaderboardEntries")
	if not leaderboard_container:
		print("[GameController] ERROR: Leaderboard container not found!")
		return
	
	print("[GameController] Leaderboard container found, clearing existing entries")
	
	# Clear existing entries
	for child in leaderboard_container.get_children():
		child.queue_free()
	
	var cache_data: Dictionary = _leaderboard_cache.get(level_id, {})
	var entries: Array = cache_data.get("entries", [])
	var player_rank_data: Dictionary = cache_data.get("player_rank", {})
	
	print("[GameController] Cache lookup for level ", level_id, " - Found: ", _leaderboard_cache.has(level_id))
	print("[GameController] Retrieved ", entries.size(), " entries from cache data")
	
	if entries.is_empty():
		print("[GameController] No entries, showing placeholder")
		var no_data_label = Label.new()
		no_data_label.text = "No leaderboard data yet\nBe the first to complete this level!"
		no_data_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		no_data_label.add_theme_font_size_override("font_size", 18)
		no_data_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		no_data_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		no_data_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		no_data_label.custom_minimum_size = Vector2(340, 100)
		leaderboard_container.add_child(no_data_label)
		return
	
	print("[GameController] Creating ", entries.size(), " leaderboard entries")
	
	# Add player's rank at the top if available and not in top 20
	if player_rank_data.get("success", false):
		var player_rank = player_rank_data.get("rank", 0)
		if player_rank > 20:
			# Add "Your Rank" label
			var your_rank_label = Label.new()
			your_rank_label.text = "YOUR RANK"
			your_rank_label.add_theme_font_size_override("font_size", 14)
			your_rank_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
			your_rank_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			leaderboard_container.add_child(your_rank_label)
			
			# Add player's entry
			var player_entry = {
				"rank": player_rank,
				"score": player_rank_data.get("score", 0),
				"member_id": player_rank_data.get("member_id", "You"),
				"metadata": player_rank_data.get("metadata", {})
			}
			_create_leaderboard_entry(leaderboard_container, player_entry, true)
			
			# Add separator after player's entry
			var separator = HSeparator.new()
			leaderboard_container.add_child(separator)
	
	# Display top 20 entries
	for entry in entries:
		_create_leaderboard_entry(leaderboard_container, entry)


## Create a leaderboard entry UI element
func _create_leaderboard_entry(container: Control, entry: Dictionary, is_player: bool = false) -> void:
	var entry_panel = PanelContainer.new()
	entry_panel.custom_minimum_size = Vector2(0, 65)
	
	var panel_style = StyleBoxFlat.new()
	if is_player:
		# Highlight player's entry
		panel_style.bg_color = Color(0.2, 0.4, 0.2, 0.8)
	else:
		panel_style.bg_color = Color(0.15, 0.15, 0.15, 0.7)
	panel_style.corner_radius_top_left = 5
	panel_style.corner_radius_top_right = 5
	panel_style.corner_radius_bottom_left = 5
	panel_style.corner_radius_bottom_right = 5
	panel_style.content_margin_left = 12
	panel_style.content_margin_right = 12
	panel_style.content_margin_top = 8
	panel_style.content_margin_bottom = 8
	entry_panel.add_theme_stylebox_override("panel", panel_style)
	
	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	entry_panel.add_child(hbox)
	
	# Rank
	var rank_label = Label.new()
	rank_label.text = "#%d" % entry["rank"]
	rank_label.add_theme_font_size_override("font_size", 16)
	rank_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.0))
	rank_label.custom_minimum_size = Vector2(45, 0)
	rank_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(rank_label)
	
	# Player info (name + metadata)
	var info_vbox = VBoxContainer.new()
	info_vbox.add_theme_constant_override("separation", 3)
	info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(info_vbox)
	
	# Player name
	var name_label = Label.new()
	name_label.text = entry["member_id"]
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	info_vbox.add_child(name_label)
	
	# Time and fuel from metadata
	if entry["metadata"] and entry["metadata"].has("time") and entry["metadata"].has("fuel"):
		var detail_label = Label.new()
		var time_str = ScoringSystem.format_time(entry["metadata"]["time"])
		detail_label.text = "Time: %s | Fuel: %.0f%%" % [time_str, entry["metadata"]["fuel"]]
		detail_label.add_theme_font_size_override("font_size", 12)
		detail_label.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))
		info_vbox.add_child(detail_label)
	
	# Score
	var score_label = Label.new()
	score_label.text = "%d pts" % entry["score"]
	score_label.add_theme_font_size_override("font_size", 16)
	score_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	score_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	score_label.custom_minimum_size = Vector2(80, 0)
	hbox.add_child(score_label)
	
	container.add_child(entry_panel)



func _process(_delta: float) -> void:
	if current_state != GameState.PLAYING or orbiting_body == null:
		return
	
	if not is_instance_valid(orbiting_body):
		return
	
	# Update elapsed time
	_level_elapsed_time = (Time.get_ticks_msec() / 1000.0) - _level_start_time
	
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
	
	# Clear all leaderboard caches when returning to main menu
	print("[GameController] show_start_screen() - Clearing all caches")
	print("[GameController] Before clear - Cache size: ", _leaderboard_cache.size())
	_leaderboard_cache.clear()
	_cache_timestamp.clear()
	_active_fetch_tasks.clear()
	print("[GameController] After clear - Cache size: ", _leaderboard_cache.size())
	
	# Hide HUD and touch controls on menu
	if hud:
		hud.visible = false
	if touch_controls_manager:
		touch_controls_manager.visible = false
	
	# Reset to level 1 when returning to main menu
	if LevelManager:
		LevelManager.current_level_id = 1
	
	# Start background music if not already playing
	if music_player and not music_player.playing:
		_play_random_music()
	
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
	
	# Reset global rank panel to loading state
	_reset_global_rank_panel()
	
	var fuel_percent := 0.0
	var max_fuel := 1000.0
	if orbiting_body and is_instance_valid(orbiting_body):
		fuel_percent = orbiting_body.get_fuel_percentage()
		max_fuel = orbiting_body.max_fuel
	
	# Get S rank parameters from level config
	var s_rank_time := 30.0
	var s_rank_fuel := 100.0
	if current_level_root and current_level_root is LevelConfig:
		s_rank_time = current_level_root.s_rank_target_time
		s_rank_fuel = current_level_root.s_rank_target_fuel
	
	# Calculate score using ScoringSystem with level-specific S rank targets
	var score_data := ScoringSystem.calculate_score(
		_level_elapsed_time, 
		fuel_percent, 
		s_rank_time,
		s_rank_fuel,
		max_fuel
	)
	
	# DEBUG: Log completion stats for S-tier calibration
	var separator = "=".repeat(60)
	print(separator)
	print("LEVEL COMPLETION DEBUG - Level %d" % LevelManager.current_level_id)
	print(separator)
	print("Time: %.2f seconds (S-rank target: %.2f)" % [_level_elapsed_time, s_rank_time])
	print("Fuel: %.2f%% (S-rank target: %.2f%%)" % [fuel_percent, s_rank_fuel])
	print("Grade: %s" % score_data["grade"])
	print("Score: %d" % score_data["total_score"])
	print(separator)
	
	# Create styled stats display
	var stats_container = game_won_screen.get_node("CenterContainer/VBoxContainer/StatsLabel")
	if stats_container and orbiting_body:
		# Clear existing content if it's a label
		if stats_container is Label:
			# Replace the Label with an HBoxContainer for side-by-side layout
			var parent = stats_container.get_parent()
			var index = stats_container.get_index()
			stats_container.queue_free()
			
			# Create new HBoxContainer
			var hbox = HBoxContainer.new()
			hbox.name = "StatsLabel"
			hbox.alignment = BoxContainer.ALIGNMENT_CENTER
			parent.add_child(hbox)
			parent.move_child(hbox, index)
			stats_container = hbox
		
		# Clear any existing children
		for child in stats_container.get_children():
			child.queue_free()
		
		# Get grade info
		var grade = score_data["grade"]
		var grade_color: Color
		match grade:
			"S":
				grade_color = Color(1.0, 0.85, 0.0)  # Gold
			"A+", "A", "A-":
				grade_color = Color(0.3, 1.0, 0.5)  # Green
			"B+", "B", "B-":
				grade_color = Color(0.4, 0.8, 1.0)  # Blue
			"C+", "C", "C-":
				grade_color = Color(1.0, 0.8, 0.4)  # Orange
			"D+", "D":
				grade_color = Color(1.0, 0.5, 0.3)  # Red-Orange
			_:
				grade_color = Color(0.6, 0.6, 0.6)  # Gray
		
		# Left side - Large grade letter
		var grade_container = CenterContainer.new()
		grade_container.custom_minimum_size = Vector2(120, 0)
		stats_container.add_child(grade_container)
		
		# Wrapper control for absolute positioning
		var grade_wrapper = Control.new()
		grade_wrapper.custom_minimum_size = Vector2(120, 100)
		grade_container.add_child(grade_wrapper)
		
		# Grade letter (centered)
		var grade_label = Label.new()
		grade_label.add_theme_font_override("font", AudiowideFont)
		grade_label.add_theme_font_size_override("font_size", 80)
		grade_label.add_theme_color_override("font_color", grade_color)
		grade_label.text = grade
		grade_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		grade_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		grade_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		grade_wrapper.add_child(grade_label)
		
		# "Tier" label anchored at top center (added after so it renders on top)
		var tier_label = Label.new()
		tier_label.add_theme_font_override("font", AudiowideFont)
		tier_label.add_theme_font_size_override("font_size", 16)
		tier_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		tier_label.text = "Tier"
		tier_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tier_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
		tier_label.position.y = -5
		grade_wrapper.add_child(tier_label)
		
		# Right side - Stats details
		var stats_vbox = VBoxContainer.new()
		stats_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		stats_container.add_child(stats_vbox)
		
		var score_label = Label.new()
		score_label.add_theme_font_size_override("font_size", 28)
		score_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.5))
		score_label.text = "Score: %d" % score_data["total_score"]
		stats_vbox.add_child(score_label)
		
		var time_str := ScoringSystem.format_time(_level_elapsed_time)
		var time_label = Label.new()
		time_label.add_theme_font_size_override("font_size", 20)
		time_label.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))
		time_label.text = "Time: %s" % time_str
		stats_vbox.add_child(time_label)
		
		var fuel_label = Label.new()
		fuel_label.add_theme_font_size_override("font_size", 20)
		fuel_label.add_theme_color_override("font_color", Color(0.7, 0.9, 1.0))
		fuel_label.text = "Fuel: %.1f%%" % fuel_percent
		stats_vbox.add_child(fuel_label)
	
	if LevelManager:
		# Pass score data to level manager instead of just fuel percentage
		var is_new_local_best = LevelManager.complete_level(score_data["total_score"], _level_elapsed_time, fuel_percent)
		print("[GameController] Level completed. Is new local best: ", is_new_local_best)
		
		# Always submit score to LootLocker and check if it's a server-side new best
		if LootLockerManager:
			print("[GameController] Submitting score to leaderboard...")
			var metadata := {
				"time": _level_elapsed_time,
				"fuel": fuel_percent
			}
			
			# Get current server best score before submitting
			var old_rank_result = await LootLockerManager.fetch_player_rank(LevelManager.current_level_id)
			var old_server_score = old_rank_result.get("score", 0) if old_rank_result.get("success", false) else 0
			print("[GameController] Old server best score: ", old_server_score)
			
			# Submit the new score
			LootLockerManager.submit_score(
				LevelManager.current_level_id,
				score_data["total_score"],
				metadata
			)
			
			# Wait for submission to process
			await get_tree().create_timer(1.0).timeout
			
			# Invalidate cache so leaderboard refreshes with new score
			_invalidate_leaderboard_cache(LevelManager.current_level_id)
			
			# Check if the new score is better than the old server score
			var is_new_server_best = score_data["total_score"] > old_server_score
			
			# Always fetch and display global rank to show connection status
			if is_new_server_best:
				await _fetch_and_display_global_rank(LevelManager.current_level_id)
			else:
				await _show_rank_encouragement_message(LevelManager.current_level_id)
		
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
	_update_music_button_text()
	touch_controls_button.grab_focus()


func show_options_from_pause() -> void:
	_options_opened_from_pause = true
	pause_screen.visible = false
	options_screen.visible = true
	_update_touch_controls_button_text()
	_update_soi_visibility_button_text()
	_update_music_button_text()
	touch_controls_button.grab_focus()


func show_level_select_screen(context: LevelSelectContext = LevelSelectContext.MAIN_MENU) -> void:
	_level_select_context = context
	current_state = GameState.LEVEL_SELECT
	_hide_all_screens()
	level_select_screen.visible = true
	
	# Clear leaderboard caches when opening level select to ensure fresh data
	print("[GameController] show_level_select_screen() - Clearing all caches")
	print("[GameController] Before clear - Cache size: ", _leaderboard_cache.size())
	_leaderboard_cache.clear()
	_cache_timestamp.clear()
	_active_fetch_tasks.clear()
	print("[GameController] After clear - Cache size: ", _leaderboard_cache.size())
	
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
	
	# Reset level time tracking
	_level_start_time = Time.get_ticks_msec() / 1000.0
	_level_elapsed_time = 0.0
	
	# Show HUD and touch controls during gameplay
	if hud:
		hud.visible = true
	if touch_controls_manager:
		touch_controls_manager.visible = true
	
	# Start background music if not already playing
	if music_player and not music_player.playing:
		_play_random_music()
	
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
	
	# Reset level time tracking
	_level_start_time = Time.get_ticks_msec() / 1000.0
	_level_elapsed_time = 0.0
	
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


func _update_music_button_text() -> void:
	if not music_button:
		return
	var state_text := "On" if music_enabled else "Off"
	music_button.text = "Music: " + state_text


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
	_save_settings()
	if Events:
		Events.soi_visibility_changed.emit(soi_visible)


func _on_music_pressed() -> void:
	music_enabled = not music_enabled
	_update_music_button_text()
	_save_settings()
	
	if music_enabled:
		# Start music if it's not already playing
		if music_player and not music_player.playing:
			_play_random_music()
	else:
		# Stop music
		_stop_music()


func _on_save_name_pressed() -> void:
	var new_name: String = player_name_edit.text.strip_edges()
	if new_name.length() > 0:
		PlayerProfile.set_player_name(new_name)
		_update_player_name_display()
		player_name_edit.text = ""
		player_name_edit.placeholder_text = "Name saved!"


func _on_random_name_pressed() -> void:
	var random_name: String = PlayerProfile.generate_random_name()
	PlayerProfile.set_player_name(random_name)
	_update_player_name_display()
	player_name_edit.text = ""


func _update_player_name_display() -> void:
	var current_name: String = PlayerProfile.get_player_name()
	player_name_label.text = "Player Name: " + current_name


func _on_camera_zoom_changed(zoom_level: float) -> void:
	_saved_zoom = zoom_level


func _on_ship_exploded() -> void:
	pass


func is_game_active() -> bool:
	return current_state == GameState.PLAYING


## Setup the background music player
func _setup_music_player() -> void:
	music_player = AudioStreamPlayer.new()
	music_player.bus = "Master"
	music_player.volume_db = -5.0  # Slightly quieter background music
	add_child(music_player)
	
	# Connect to finished signal to play next track
	music_player.finished.connect(_on_music_finished)


## Start playing random background music
func _play_random_music() -> void:
	if MUSIC_TRACKS.is_empty() or not music_enabled:
		return
	
	# Select a random track
	var random_index = randi() % MUSIC_TRACKS.size()
	music_player.stream = MUSIC_TRACKS[random_index]
	music_player.play()
	print("[GameController] Playing music track: ", random_index + 1)


## Called when current music track finishes
func _on_music_finished() -> void:
	# Play another random track only if music is still enabled
	if music_enabled:
		_play_random_music()


## Stop background music
func _stop_music() -> void:
	if music_player and music_player.playing:
		music_player.stop()


## Save game settings to file
func _save_settings() -> void:
	var settings_data := {
		"music_enabled": music_enabled,
		"soi_visible": soi_visible,
		"version": 1
	}
	
	var file := FileAccess.open(SETTINGS_SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_var(settings_data)
		file.close()
		print("[GameController] Settings saved")
		if Events:
			Events.settings_saved.emit()


## Load game settings from file
func _load_settings() -> void:
	if not FileAccess.file_exists(SETTINGS_SAVE_PATH):
		print("[GameController] No settings file found, using defaults")
		return
	
	var file := FileAccess.open(SETTINGS_SAVE_PATH, FileAccess.READ)
	if file:
		var settings_data = file.get_var()
		file.close()
		
		if settings_data is Dictionary:
			if "music_enabled" in settings_data:
				music_enabled = settings_data["music_enabled"]
			if "soi_visible" in settings_data:
				soi_visible = settings_data["soi_visible"]
			
			print("[GameController] Settings loaded - Music: %s, SOI: %s" % [music_enabled, soi_visible])
			if Events:
				Events.settings_loaded.emit()

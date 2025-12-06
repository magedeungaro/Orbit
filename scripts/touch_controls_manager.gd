extends CanvasLayer
## Touch Controls Manager - Handles visibility of touch controls based on device type

signal touch_controls_changed(enabled: bool)

@onready var touch_container: Control = $TouchControlContainer

# User preference override (-1 = auto, 0 = force off, 1 = force on)
var user_preference: int = -1
var _is_auto_touch_device: bool = false

const SETTINGS_PATH = "user://settings.cfg"


func _ready() -> void:
	_load_settings()
	_setup_touch_controls()


func _setup_touch_controls() -> void:
	_is_auto_touch_device = _detect_touch_device()
	_apply_touch_controls_visibility()


func _apply_touch_controls_visibility() -> void:
	var should_show: bool
	
	if user_preference == -1:
		# Auto mode - use device detection
		should_show = _is_auto_touch_device
	else:
		# Manual override
		should_show = user_preference == 1
	
	if touch_container:
		touch_container.visible = should_show
		# Also disable/enable input processing to prevent invisible clicks
		touch_container.set_process_input(should_show)
		touch_container.mouse_filter = Control.MOUSE_FILTER_STOP if should_show else Control.MOUSE_FILTER_IGNORE
		# Recursively set mouse filter on all children
		_set_children_mouse_filter(touch_container, should_show)
	
	if should_show:
		print("Touch controls enabled")
	else:
		print("Touch controls disabled")


func _set_children_mouse_filter(node: Node, enabled: bool) -> void:
	for child in node.get_children():
		if child is Control:
			if enabled:
				# Restore to default (STOP for buttons)
				child.mouse_filter = Control.MOUSE_FILTER_STOP
			else:
				# Ignore all mouse/touch input
				child.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_set_children_mouse_filter(child, enabled)


func _detect_touch_device() -> bool:
	# Check for mobile platforms
	if OS.has_feature("mobile"):
		return true
	
	# Check for Android specifically
	if OS.has_feature("android"):
		return true
	
	# Check for iOS specifically
	if OS.has_feature("ios"):
		return true
	
	# Check for web platform (could be mobile browser)
	if OS.has_feature("web"):
		# On web, check if it's a touch-capable device
		# Web exports on mobile devices will have touchscreen support
		return DisplayServer.is_touchscreen_available()
	
	# For desktop, check if touchscreen is available (e.g., touch-enabled laptops)
	if DisplayServer.is_touchscreen_available():
		return true
	
	return false


## Get current touch controls state
func is_touch_controls_enabled() -> bool:
	if touch_container:
		return touch_container.visible
	return false


## Get if auto-detection thinks this is a touch device
func is_auto_touch_device() -> bool:
	return _is_auto_touch_device


## Get current preference mode (-1 = auto, 0 = off, 1 = on)
func get_preference() -> int:
	return user_preference


## Set touch controls preference (-1 = auto, 0 = force off, 1 = force on)
func set_preference(pref: int) -> void:
	user_preference = clampi(pref, -1, 1)
	_apply_touch_controls_visibility()
	_save_settings()
	touch_controls_changed.emit(is_touch_controls_enabled())


## Force show touch controls
func show_touch_controls() -> void:
	set_preference(1)


## Force hide touch controls
func hide_touch_controls() -> void:
	set_preference(0)


## Set to auto mode
func set_auto_mode() -> void:
	set_preference(-1)


## Toggle between on/off (not auto)
func toggle_touch_controls() -> void:
	if is_touch_controls_enabled():
		set_preference(0)
	else:
		set_preference(1)


## Cycle through modes: Auto -> On -> Off -> Auto
func cycle_preference() -> void:
	if user_preference == -1:
		set_preference(1)
	elif user_preference == 1:
		set_preference(0)
	else:
		set_preference(-1)


func _save_settings() -> void:
	var config = ConfigFile.new()
	config.set_value("touch_controls", "preference", user_preference)
	config.save(SETTINGS_PATH)


func _load_settings() -> void:
	var config = ConfigFile.new()
	var err = config.load(SETTINGS_PATH)
	if err == OK:
		user_preference = config.get_value("touch_controls", "preference", -1)

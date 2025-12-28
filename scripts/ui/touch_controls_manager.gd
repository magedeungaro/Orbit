extends CanvasLayer

signal touch_controls_changed(enabled: bool)

@onready var touch_container: Control = $TouchControlContainer

var user_preference: int = -1  # -1 = auto, 0 = force off, 1 = force on
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
		should_show = _is_auto_touch_device
	else:
		should_show = user_preference == 1
	
	if touch_container:
		touch_container.visible = should_show
		touch_container.set_process_input(should_show)
		touch_container.mouse_filter = Control.MOUSE_FILTER_STOP if should_show else Control.MOUSE_FILTER_IGNORE
		_set_children_mouse_filter(touch_container, should_show)


func _set_children_mouse_filter(node: Node, enabled: bool) -> void:
	for child in node.get_children():
		if child is Control:
			child.mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
		_set_children_mouse_filter(child, enabled)


func _detect_touch_device() -> bool:
	if OS.has_feature("mobile") or OS.has_feature("android") or OS.has_feature("ios"):
		return true
	
	if OS.has_feature("web"):
		return DisplayServer.is_touchscreen_available()
	
	return DisplayServer.is_touchscreen_available()


func is_touch_controls_enabled() -> bool:
	return touch_container.visible if touch_container else false


func is_auto_touch_device() -> bool:
	return _is_auto_touch_device


func get_preference() -> int:
	return user_preference


func set_preference(pref: int) -> void:
	user_preference = clampi(pref, -1, 1)
	_apply_touch_controls_visibility()
	_save_settings()
	touch_controls_changed.emit(is_touch_controls_enabled())


func show_touch_controls() -> void:
	set_preference(1)


func hide_touch_controls() -> void:
	set_preference(0)


func set_auto_mode() -> void:
	set_preference(-1)


func toggle_touch_controls() -> void:
	set_preference(0 if is_touch_controls_enabled() else 1)


func cycle_preference() -> void:
	match user_preference:
		-1: set_preference(1)
		1: set_preference(0)
		_: set_preference(-1)


func _save_settings() -> void:
	var config = ConfigFile.new()
	config.set_value("touch_controls", "preference", user_preference)
	config.save(SETTINGS_PATH)


func _load_settings() -> void:
	var config = ConfigFile.new()
	var err = config.load(SETTINGS_PATH)
	if err == OK:
		user_preference = config.get_value("touch_controls", "preference", -1)

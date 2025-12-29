extends Node
## Level Manager - Handles level loading, progression, and state
## Levels are now defined as individual scenes in res://scenes/levels/

const SAVE_PATH := "user://level_progress.save"
const LEVELS_PATH := "res://scenes/levels/"

# Preload all level scenes for web export compatibility
const LEVEL_SCENES: Dictionary = {
	1: "res://scenes/levels/level_1.tscn",
	2: "res://scenes/levels/level_2.tscn",
	3: "res://scenes/levels/level_3.tscn",
	4: "res://scenes/levels/level_4.tscn",
	5: "res://scenes/levels/level_5.tscn",
	6: "res://scenes/levels/level_6.tscn",
}

var current_level_id: int = 1
var unlocked_levels: Array[int] = [1]
var level_best_scores: Dictionary = {}  # level_id -> best fuel remaining percentage

var _level_scenes: Dictionary = {}  # level_id -> scene path
var _level_configs: Dictionary = {}  # level_id -> LevelConfig data (cached)


func _ready() -> void:
	_initialize_level_scenes()
	load_progress()


## Initialize level scenes (web-compatible)
func _initialize_level_scenes() -> void:
	_level_scenes.clear()
	_level_configs.clear()
	
	# Use predefined level paths for web export compatibility
	for level_id in LEVEL_SCENES:
		var scene_path = LEVEL_SCENES[level_id]
		var config = _load_level_config(scene_path)
		if config:
			_level_scenes[config.level_id] = scene_path
			_level_configs[config.level_id] = config


## Load level config from a scene
func _load_level_config(scene_path: String) -> LevelConfig:
	var scene = load(scene_path)
	if not scene:
		return null
	
	var instance = scene.instantiate()
	if instance and instance is LevelConfig:
		var config = LevelConfig.new()
		config.level_id = instance.level_id
		config.level_name = instance.level_name
		config.description = instance.description
		config.ship_start_velocity = instance.ship_start_velocity
		config.max_fuel = instance.max_fuel
		config.stable_orbit_time = instance.stable_orbit_time
		instance.queue_free()
		return config
	
	if instance:
		instance.queue_free()
	return null


## Get all level IDs sorted
func get_all_level_ids() -> Array[int]:
	var ids: Array[int] = []
	for id in _level_scenes.keys():
		ids.append(id)
	ids.sort()
	return ids


## Get level config by ID
func get_level(level_id: int) -> LevelConfig:
	if level_id in _level_configs:
		return _level_configs[level_id]
	return null


## Get the scene path for a level
func get_level_scene_path(level_id: int) -> String:
	if level_id in _level_scenes:
		return _level_scenes[level_id]
	return ""


## Get the current level configuration
func get_current_level() -> LevelConfig:
	return get_level(current_level_id)


## Get the current level scene path
func get_current_level_scene_path() -> String:
	return get_level_scene_path(current_level_id)


## Load a level scene instance
func load_level_scene(level_id: int) -> Node2D:
	var scene_path = get_level_scene_path(level_id)
	if scene_path.is_empty():
		return null
	
	var scene = load(scene_path)
	if scene:
		return scene.instantiate()
	return null


## Set the current level
func set_current_level(level_id: int) -> void:
	if is_level_unlocked(level_id):
		current_level_id = level_id
		if Events:
			Events.level_changed.emit(level_id)


## Check if a level is unlocked
func is_level_unlocked(level_id: int) -> bool:
	return level_id in unlocked_levels


## Unlock a level
func unlock_level(level_id: int) -> void:
	if level_id not in unlocked_levels:
		unlocked_levels.append(level_id)
		unlocked_levels.sort()
		save_progress()
		if Events:
			Events.level_unlocked.emit(level_id)


## Complete current level and unlock next
func complete_level(fuel_remaining_percent: float) -> void:
	var level_id := current_level_id
	
	# Update best score
	if level_id not in level_best_scores or fuel_remaining_percent > level_best_scores[level_id]:
		level_best_scores[level_id] = fuel_remaining_percent
	
	# Unlock next level
	var next_level_id := level_id + 1
	if get_level(next_level_id) != null:
		unlock_level(next_level_id)
	
	save_progress()
	
	if Events:
		Events.level_completed.emit(level_id, fuel_remaining_percent)


## Get best score for a level
func get_best_score(level_id: int) -> float:
	if level_id in level_best_scores:
		return level_best_scores[level_id]
	return -1.0


## Check if there's a next level
func has_next_level() -> bool:
	return get_level(current_level_id + 1) != null


## Advance to next level
func advance_to_next_level() -> bool:
	var next_id := current_level_id + 1
	if has_next_level() and is_level_unlocked(next_id):
		set_current_level(next_id)
		return true
	return false


## Get total number of levels
func get_level_count() -> int:
	return _level_scenes.size()


## Save progress to file
func save_progress() -> void:
	var save_data := {
		"unlocked_levels": unlocked_levels,
		"best_scores": level_best_scores,
		"current_level": current_level_id
	}
	
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_var(save_data)
		file.close()
		if Events:
			Events.settings_saved.emit()


## Load progress from file
func load_progress() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file:
		var save_data = file.get_var()
		file.close()
		
		if save_data is Dictionary:
			if "unlocked_levels" in save_data:
				unlocked_levels.clear()
				for level_id in save_data["unlocked_levels"]:
					unlocked_levels.append(level_id)
			if "best_scores" in save_data:
				level_best_scores = save_data["best_scores"]
			if "current_level" in save_data:
				current_level_id = save_data["current_level"]
		
		if Events:
			Events.settings_loaded.emit()


## Reset all progress (for testing/debugging)
func reset_progress() -> void:
	unlocked_levels = [1]
	level_best_scores = {}
	current_level_id = 1
	save_progress()

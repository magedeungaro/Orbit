extends Node
## Level Manager - Handles level loading, progression, and state

const SAVE_PATH := "user://level_progress.save"

var current_level_id: int = 1
var unlocked_levels: Array[int] = [1]
var level_best_scores: Dictionary = {}  # level_id -> best fuel remaining percentage

var _levels: Array[LevelData.LevelConfig] = []


func _ready() -> void:
	_levels = LevelData.get_all_levels()
	load_progress()


## Get all available levels
func get_all_levels() -> Array[LevelData.LevelConfig]:
	return _levels


## Get a specific level by ID
func get_level(level_id: int) -> LevelData.LevelConfig:
	for level in _levels:
		if level.id == level_id:
			return level
	return null


## Get the current level configuration
func get_current_level() -> LevelData.LevelConfig:
	return get_level(current_level_id)


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
	return _levels.size()


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

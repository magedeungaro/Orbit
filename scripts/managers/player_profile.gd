extends Node
class_name PlayerProfile
## Manages player profile data including player name and unique ID

const SAVE_PATH := "user://player_profile.save"

static var _player_name: String = ""
static var _player_id: String = ""

# Random name generation word lists
const ADJECTIVES := [
	"Swift", "Brave", "Stellar", "Cosmic", "Lunar", "Solar", "Nova",
	"Rapid", "Blazing", "Silent", "Quantum", "Nebula", "Astral", "Orbital",
	"Velocity", "Eclipse", "Aurora", "Gravity", "Photon", "Pulsar"
]

const NOUNS := [
	"Pilot", "Navigator", "Explorer", "Voyager", "Ranger", "Pioneer",
	"Commander", "Captain", "Ace", "Runner", "Drifter", "Wanderer",
	"Traveler", "Seeker", "Hunter", "Raider", "Scout", "Guardian"
]


## Load player profile on startup
static func initialize() -> void:
	load_profile()
	
	# Generate ID and name if not set
	if _player_id.is_empty():
		_player_id = _generate_unique_id()
	
	if _player_name.is_empty():
		_player_name = generate_random_name()
		save_profile()


## Get player display name
static func get_player_name() -> String:
	if _player_name.is_empty():
		initialize()
	return _player_name


## Set player display name
static func set_player_name(new_name: String) -> void:
	_player_name = new_name.strip_edges()
	if _player_name.is_empty():
		_player_name = generate_random_name()
	save_profile()


## Get unique player ID (for LootLocker guest sessions)
static func get_player_id() -> String:
	if _player_id.is_empty():
		initialize()
	return _player_id


## Generate a random player name
static func generate_random_name() -> String:
	randomize()
	var adjective: String = ADJECTIVES[randi() % ADJECTIVES.size()]
	var noun: String = NOUNS[randi() % NOUNS.size()]
	var number: int = randi() % 1000
	return "%s%s%d" % [adjective, noun, number]


## Generate a unique player ID
static func _generate_unique_id() -> String:
	var timestamp := Time.get_unix_time_from_system()
	var random_part := randi() % 100000
	return "player_%d_%d" % [timestamp, random_part]


## Save player profile to disk
static func save_profile() -> void:
	var save_data := {
		"player_name": _player_name,
		"player_id": _player_id,
		"version": 1
	}
	
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file:
		file.store_var(save_data)
		file.close()
		print("PlayerProfile: Saved profile - Name: %s, ID: %s" % [_player_name, _player_id])


## Load player profile from disk
static func load_profile() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file:
		var save_data = file.get_var()
		file.close()
		
		if save_data is Dictionary:
			if "player_name" in save_data:
				_player_name = save_data["player_name"]
			if "player_id" in save_data:
				_player_id = save_data["player_id"]
			
			print("PlayerProfile: Loaded profile - Name: %s, ID: %s" % [_player_name, _player_id])


## Check if player has a custom name (not randomly generated)
static func has_custom_name() -> bool:
	# Check if name follows the random pattern
	var name := get_player_name()
	for adjective in ADJECTIVES:
		for noun in NOUNS:
			if name.begins_with(adjective + noun):
				return false
	return true


## Reset profile (for testing)
static func reset_profile() -> void:
	_player_name = ""
	_player_id = ""
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	initialize()

extends Node
## LootLocker Manager - Handles authentication and API communication with LootLocker
## Manages leaderboards for each level using LootLocker SDK

# Session state
var is_authenticated: bool = false
var player_id: int = 0

# Leaderboard IDs mapping (level_id -> leaderboard_id)
# Leaderboards created in LootLocker dashboard
var leaderboard_ids := {
	1: 32525,  # orbit_level_1
	2: 32526,  # orbit_level_2
	3: 32527,  # orbit_level_3
	4: 32528,  # orbit_level_4
	5: 32529,  # orbit_level_5
	6: 32530   # orbit_level_6
}

# Signals
signal authentication_completed(success: bool)
signal leaderboard_fetched(success: bool, level_id: int, entries: Array)

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Auto-authenticate on startup
	call_deferred("start_guest_session")


## Start a guest session with LootLocker using the SDK
func start_guest_session() -> void:
	if is_authenticated:
		authentication_completed.emit(true)
		return
	
	var player_identifier := PlayerProfile.get_player_id()
	
	var response = await LL_Authentication.GuestSession.new(player_identifier).send()
	
	if response.success:
		is_authenticated = true
		player_id = response.player_id
		
		# Set player name in LootLocker
		var player_name = PlayerProfile.get_player_name()
		var name_response = await LL_Players.SetPlayerName.new(player_name).send()
		if not name_response.success:
			push_warning("[LootLocker] Failed to set player name")
		
		authentication_completed.emit(true)
	else:
		var error_msg = response.error_data.message if response.error_data else "Unknown error"
		push_error("LootLocker: Authentication failed: " + error_msg)
		is_authenticated = false
		authentication_completed.emit(false)


## Submit a score to a level leaderboard using the SDK
## metadata format: {"time": float, "fuel": float}
func submit_score(level_id: int, score: int, metadata: Dictionary) -> void:
	if not is_authenticated:
		push_warning("LootLocker: Not authenticated, attempting to authenticate first")
		await authentication_completed
		if not is_authenticated:
			return
	
	if not leaderboard_ids.has(level_id) or leaderboard_ids[level_id] == 0:
		push_error("LootLocker: No leaderboard ID configured for level " + str(level_id))
		return
	
	var leaderboard_id: int = leaderboard_ids[level_id]
	var member_id := str(player_id)  # Use player_id for player type leaderboards
	var metadata_string := JSON.stringify(metadata)
	
	var response = await LL_Leaderboards.SubmitScore.new(
		str(leaderboard_id), 
		score, 
		member_id, 
		metadata_string
	).send()
	
	if not response.success:
		var error_msg = response.error_data.message if response.error_data else "Unknown error"
		push_error("LootLocker: Score submission failed: " + error_msg)


## Fetch leaderboard entries for a level using the SDK
## count: number of entries to fetch (default 10)
func fetch_leaderboard(level_id: int, count: int = 10) -> void:
	if not is_authenticated:
		push_warning("LootLocker: Not authenticated, attempting to authenticate first")
		await authentication_completed
		if not is_authenticated:
			leaderboard_fetched.emit(false, level_id, [])
			return
	
	if not leaderboard_ids.has(level_id) or leaderboard_ids[level_id] == 0:
		push_error("LootLocker: No leaderboard ID configured for level " + str(level_id))
		leaderboard_fetched.emit(false, level_id, [])
		return
	
	var leaderboard_id: int = leaderboard_ids[level_id]
	
	var response = await LL_Leaderboards.GetScoreList.new(str(leaderboard_id), count).send()
	
	if not response.success:
		var error_msg = response.error_data.message if response.error_data else "Unknown error"
		push_error("LootLocker: Leaderboard fetch failed: " + error_msg)
		leaderboard_fetched.emit(false, level_id, [])
		return
	
	var entries: Array = []
	
	for item in response.items:
		var entry := {
			"rank": item.rank,
			"score": item.score,
			"member_id": item.player.name if item.player and item.player.name else "Anonymous",
			"metadata": {}
		}
		
		# Parse metadata if present
		if item.metadata and item.metadata != "":
			var metadata_json := JSON.new()
			if metadata_json.parse(item.metadata) == OK:
				entry["metadata"] = metadata_json.data
		
		entries.append(entry)
	
	leaderboard_fetched.emit(true, level_id, entries)


## Fetch player's rank for a specific level
## Returns a Dictionary with success, rank, score, member_id, and metadata
func fetch_player_rank(level_id: int) -> Dictionary:
	if not is_authenticated:
		push_warning("LootLocker: Not authenticated")
		return {"success": false}
	
	if player_id == 0:
		push_warning("LootLocker: No player ID available")
		return {"success": false}
	
	if not leaderboard_ids.has(level_id) or leaderboard_ids[level_id] == 0:
		push_error("LootLocker: No leaderboard ID configured for level " + str(level_id))
		return {"success": false}
	
	var leaderboard_id: int = leaderboard_ids[level_id]
	var member_id := str(player_id)
	
	var response = await LL_Leaderboards.GetMemberRank.new(
		str(leaderboard_id),
		member_id
	).send()
	
	if not response.success:
		var error_msg = response.error_data.message if response.error_data else "Unknown error"
		push_warning("LootLocker: Failed to get player rank: " + error_msg)
		return {"success": false}
	
	# Parse metadata if present
	var metadata_dict = {}
	if response.metadata and response.metadata != "":
		var metadata_json := JSON.new()
		if metadata_json.parse(response.metadata) == OK:
			metadata_dict = metadata_json.data
	
	var result = {
		"success": true,
		"rank": response.rank,
		"score": response.score,
		"member_id": response.player.name if response.player and response.player.name else "You",
		"metadata": metadata_dict
	}
	
	return result

extends Node
class_name ScoringSystem
## Scoring System - Calculates player scores based on time and fuel efficiency
## Formula gives more weight to time to prevent boring records with excessive fuel conservation
## Scores are uncapped to promote competitive leaderboards - faster times = exponentially higher scores

# Time scoring constant - tuned so target time with 100% fuel = 10000 points
# Formula: time_score = (TIME_CONSTANT * target_time) / time_elapsed
const TIME_CONSTANT: float = 6000.0  # At target time: 6000 points from time

# Maximum fuel points (capped component)
const MAX_FUEL_POINTS: float = 4000.0


## Calculate the final score for a level completion
## @param time_elapsed: Time taken to complete the level in seconds
## @param fuel_remaining_percent: Percentage of fuel remaining (0-100)
## @param s_rank_time: Target time for S rank (from level config)
## @param s_rank_fuel: Target fuel percentage for S rank (from level config)
## @param max_fuel: Maximum fuel capacity for the level (for reference)
## @return: Dictionary with score breakdown
static func calculate_score(
	time_elapsed: float, 
	fuel_remaining_percent: float, 
	s_rank_time: float = 30.0,
	s_rank_fuel: float = 100.0,
	max_fuel: float = 1000.0
) -> Dictionary:
	# Prevent division by zero - minimum 0.1 seconds
	time_elapsed = max(0.1, time_elapsed)
	s_rank_time = max(0.1, s_rank_time)
	
	# Calculate time score (inverse relationship - faster = more points, NO CAP)
	# Scale based on S rank target time
	# At s_rank_time: gives 6000 points
	# Faster than s_rank_time: exponentially more points
	var time_score := (TIME_CONSTANT * s_rank_time) / time_elapsed
	
	# Calculate fuel score (linear - more fuel remaining = higher score, CAPPED at 4000)
	var fuel_score := (fuel_remaining_percent / 100.0) * MAX_FUEL_POINTS
	
	# Calculate final score (theoretically unlimited)
	var final_score := time_score + fuel_score
	
	# Calculate letter grade based on S rank targets
	var grade := _calculate_grade(time_elapsed, fuel_remaining_percent, s_rank_time, s_rank_fuel)
	
	# Calculate benchmark score (what S rank would be with perfect execution)
	var benchmark_score := TIME_CONSTANT + (s_rank_fuel / 100.0) * MAX_FUEL_POINTS
	
	return {
		"total_score": int(final_score),
		"time_score": int(time_score),
		"fuel_score": int(fuel_score),
		"time_elapsed": time_elapsed,
		"fuel_remaining_percent": fuel_remaining_percent,
		"grade": grade,
		"benchmark_score": int(benchmark_score),
		"s_rank_time": s_rank_time,
		"s_rank_fuel": s_rank_fuel
	}


## Calculate letter grade based on performance relative to S rank targets
## Lower grades use hardcoded multipliers of S rank requirements
static func _calculate_grade(
	time_elapsed: float, 
	fuel_remaining_percent: float, 
	s_rank_time: float,
	s_rank_fuel: float
) -> String:
	# Grade thresholds as multipliers of S rank requirements
	# Time: lower is better (faster), Fuel: higher is better (more remaining)
	# Grades require meeting BOTH time and fuel criteria for that tier
	
	# Calculate performance ratios (0-1 scale where 1.0 = perfect S rank performance)
	var time_ratio: float = s_rank_time / max(0.1, time_elapsed)  # >1.0 = faster than S rank (good)
	var fuel_ratio: float = fuel_remaining_percent / max(1.0, s_rank_fuel)  # >1.0 = more fuel than S rank (good)
	
	# Combined performance score (average of both ratios)
	var performance: float = (time_ratio + fuel_ratio) / 2.0
	
	# Grade thresholds based on meeting S rank standards
	if performance >= 0.95:  # 95%+ of S rank performance
		return "S"
	elif performance >= 0.90:  # 90%+ of S rank
		return "A+"
	elif performance >= 0.85:  # 85%+ of S rank
		return "A"
	elif performance >= 0.80:  # 80%+ of S rank
		return "A-"
	elif performance >= 0.75:  # 75%+ of S rank
		return "B+"
	elif performance >= 0.70:  # 70%+ of S rank
		return "B"
	elif performance >= 0.65:  # 65%+ of S rank
		return "B-"
	elif performance >= 0.60:  # 60%+ of S rank
		return "C+"
	elif performance >= 0.55:  # 55%+ of S rank
		return "C"
	elif performance >= 0.50:  # 50%+ of S rank
		return "C-"
	elif performance >= 0.45:  # 45%+ of S rank
		return "D+"
	elif performance >= 0.40:  # 40%+ of S rank
		return "D"
	else:
		return "F"


## Format time as MM:SS.xx
static func format_time(seconds: float) -> String:
	var minutes := int(seconds) / 60
	var secs := fmod(seconds, 60.0)
	return "%d:%05.2f" % [minutes, secs]

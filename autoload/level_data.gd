extends RefCounted
class_name LevelData
## Contains all level configurations for the game

## Planet configuration for a level
class PlanetConfig:
	var position: Vector2
	var mass: float
	var texture_path: String
	var is_target: bool
	
	func _init(pos: Vector2, m: float, tex: String, target: bool = false) -> void:
		position = pos
		mass = m
		texture_path = tex
		is_target = target

## Level configuration
class LevelConfig:
	var id: int
	var name: String
	var description: String
	var ship_start_position: Vector2
	var ship_start_velocity: Vector2
	var planets: Array[PlanetConfig]
	var max_fuel: float
	var stable_orbit_time: float
	
	func _init() -> void:
		planets = []
		ship_start_velocity = Vector2.ZERO
		max_fuel = 1000.0
		stable_orbit_time = 10.0

## Get all level configurations
static func get_all_levels() -> Array[LevelConfig]:
	var levels: Array[LevelConfig] = []
	levels.append(_create_level_1())
	levels.append(_create_level_2())
	levels.append(_create_level_3())
	levels.append(_create_level_4())
	return levels

## Level 1 - Original level (Tutorial)
static func _create_level_1() -> LevelConfig:
	var level := LevelConfig.new()
	level.id = 1
	level.name = "First Steps"
	level.description = "Learn the basics of orbital mechanics"
	level.ship_start_position = Vector2(301, 300)
	level.ship_start_velocity = Vector2.ZERO
	level.max_fuel = 1000.0
	level.stable_orbit_time = 10.0
	
	# Original planet positions
	var planet1 := PlanetConfig.new(
		Vector2(1059, 609),
		20.0,
		"res://Assets/Sprites/Planet 2.PNG",
		false
	)
	var planet2 := PlanetConfig.new(
		Vector2(1545, 2048),
		20.0,
		"res://Assets/Sprites/Planet 3.PNG",
		false
	)
	var planet3 := PlanetConfig.new(
		Vector2(3801, 2118),
		20.0,
		"res://Assets/Sprites/Planet 1.PNG",
		true  # Target planet
	)
	
	level.planets.append(planet1)
	level.planets.append(planet2)
	level.planets.append(planet3)
	
	return level

## Level 2 - Gravity Assist
static func _create_level_2() -> LevelConfig:
	var level := LevelConfig.new()
	level.id = 2
	level.name = "Gravity Assist"
	level.description = "Use planetary gravity to reach your destination"
	level.ship_start_position = Vector2(200, 500)
	level.ship_start_velocity = Vector2.ZERO
	level.max_fuel = 800.0
	level.stable_orbit_time = 10.0
	
	# Planets arranged for gravity assist maneuver
	var planet1 := PlanetConfig.new(
		Vector2(800, 400),
		25.0,
		"res://Assets/Sprites/Planet 1.PNG",
		false
	)
	var planet2 := PlanetConfig.new(
		Vector2(1800, 1200),
		30.0,
		"res://Assets/Sprites/Planet 2.PNG",
		false
	)
	var planet3 := PlanetConfig.new(
		Vector2(3000, 800),
		20.0,
		"res://Assets/Sprites/Planet 3.PNG",
		true  # Target planet
	)
	
	level.planets.append(planet1)
	level.planets.append(planet2)
	level.planets.append(planet3)
	
	return level

## Level 3 - The Gauntlet
static func _create_level_3() -> LevelConfig:
	var level := LevelConfig.new()
	level.id = 3
	level.name = "The Gauntlet"
	level.description = "Navigate through a tight cluster of planets"
	level.ship_start_position = Vector2(150, 150)
	level.ship_start_velocity = Vector2.ZERO
	level.max_fuel = 600.0
	level.stable_orbit_time = 12.0
	
	# Planets in a challenging formation
	var planet1 := PlanetConfig.new(
		Vector2(600, 600),
		22.0,
		"res://Assets/Sprites/Planet 2.PNG",
		false
	)
	var planet2 := PlanetConfig.new(
		Vector2(1200, 300),
		28.0,
		"res://Assets/Sprites/Planet 1.PNG",
		false
	)
	var planet3 := PlanetConfig.new(
		Vector2(2000, 1500),
		18.0,
		"res://Assets/Sprites/Planet 3.PNG",
		true  # Target planet
	)
	
	level.planets.append(planet1)
	level.planets.append(planet2)
	level.planets.append(planet3)
	
	return level

## Level 4 - Deep Space
static func _create_level_4() -> LevelConfig:
	var level := LevelConfig.new()
	level.id = 4
	level.name = "Deep Space"
	level.description = "A long journey with limited fuel"
	level.ship_start_position = Vector2(100, 100)
	level.ship_start_velocity = Vector2.ZERO
	level.max_fuel = 500.0
	level.stable_orbit_time = 15.0
	
	# Planets spread far apart
	var planet1 := PlanetConfig.new(
		Vector2(1000, 500),
		35.0,
		"res://Assets/Sprites/Planet 1.PNG",
		false
	)
	var planet2 := PlanetConfig.new(
		Vector2(2500, 1800),
		25.0,
		"res://Assets/Sprites/Planet 2.PNG",
		false
	)
	var planet3 := PlanetConfig.new(
		Vector2(4500, 3000),
		20.0,
		"res://Assets/Sprites/Planet 3.PNG",
		true  # Target planet
	)
	
	level.planets.append(planet1)
	level.planets.append(planet2)
	level.planets.append(planet3)
	
	return level

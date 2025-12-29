extends Node2D
class_name LevelConfig
## Attach this to a level scene root to define level settings.
## All level properties are editable in the Godot editor.
## Place a Ship node under "Player" container and planets under "Planets" container.

@export_group("Level Info")
@export var level_id: int = 1
@export var level_name: String = "New Level"
@export_multiline var description: String = "Level description"
@export var thumbnail: Texture2D = null  ## Thumbnail image for level select (placeholder for now)
@export var tags: Array[String] = []  ## Tags: n-body, Patched Conic, Orbiting planets, Static Planets, Hard, Medium, Easy, Challenge

@export_group("Ship Settings")
## Max fuel for this level (also set on Ship node for visual editing)
@export var max_fuel: float = 1000.0
## Initial velocity for the ship
@export var ship_start_velocity: Vector2 = Vector2.ZERO

@export_group("Win Condition")
@export var stable_orbit_time: float = 10.0

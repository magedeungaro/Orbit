extends Node2D
## Main test scene that sets up the orbital mechanics demo

func _ready():
	# Load and instantiate the orbit controller
	var orbit_controller = preload("res://scripts/orbit_controller.gd").new()
	add_child(orbit_controller)

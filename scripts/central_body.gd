extends CharacterBody2D

@export var mass: float = 20.0
@export var show_mass_info: bool = true


func _ready() -> void:
	queue_redraw()


func _draw() -> void:
	if not show_mass_info:
		return
	
	var mass_label: Label
	if not has_node("MassLabel"):
		mass_label = Label.new()
		mass_label.name = "MassLabel"
		add_child(mass_label)
	else:
		mass_label = get_node("MassLabel")
	
	mass_label.text = "Mass: %.0f" % mass
	mass_label.position = Vector2(-30, -50)
	mass_label.add_theme_font_size_override("font_size", 12)
	mass_label.add_theme_color_override("font_color", Color.BLACK)

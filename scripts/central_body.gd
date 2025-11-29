extends CharacterBody2D
## Central body script - acts as the gravitational center
## Has mass that influences the orbiting body

@export var mass: float = 20.0  # Mass of the central body (reduced for less gravity)
@export var show_mass_info: bool = true  # Display mass information


func _ready() -> void:
	print("Central body initialized with mass: %.2f" % mass)


func _draw() -> void:
	if show_mass_info:
		# Display mass info
		var mass_text = "Mass: %.0f" % mass
		
		# Get or create mass label
		var mass_label: Label
		if not has_node("MassLabel"):
			mass_label = Label.new()
			mass_label.name = "MassLabel"
			add_child(mass_label)
		else:
			mass_label = get_node("MassLabel")
		
		mass_label.text = mass_text
		mass_label.position = Vector2(-30, -50)
		mass_label.add_theme_font_size_override("font_size", 12)
		mass_label.add_theme_color_override("font_color", Color.BLACK)

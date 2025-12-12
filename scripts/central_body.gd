@tool
extends Area2D
class_name Planet
## Planet that exerts gravitational pull on the ship.
## Configure mass and appearance in the editor.
## The gravitational sphere of influence is shown in the editor for level design.
## Uses Area2D for trigger-based collision detection with the ship.

@export_group("Physics")
@export var mass: float = 20.0:
	set(value):
		mass = value
		queue_redraw()

@export_group("Target")
## If true, this is the planet the player must orbit to win
@export var is_target: bool = false:
	set(value):
		is_target = value
		queue_redraw()

@export_group("Editor Visualization")
## Show the sphere of influence in the editor
@export var show_soi_in_editor: bool = true:
	set(value):
		show_soi_in_editor = value
		queue_redraw()
## Color of the SOI circle in editor
@export var soi_color: Color = Color(0.3, 0.6, 1.0, 0.15):
	set(value):
		soi_color = value
		queue_redraw()
## Color of the SOI border in editor
@export var soi_border_color: Color = Color(0.3, 0.6, 1.0, 0.5):
	set(value):
		soi_border_color = value
		queue_redraw()
## Gravitational constant (should match ship's value)
@export var gravitational_constant: float = 500000.0:
	set(value):
		gravitational_constant = value
		queue_redraw()
## Base sphere of influence radius
@export var base_sphere_of_influence: float = 350.0:
	set(value):
		base_sphere_of_influence = value
		queue_redraw()


func _ready() -> void:
	queue_redraw()
	# Connect to body_entered signal for collision detection
	if not Engine.is_editor_hint():
		body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node2D) -> void:
	# Check if it's the ship (has the orbiting_body script)
	if body.has_method("trigger_explosion"):
		body.trigger_explosion(self)


func _process(_delta: float) -> void:
	# Continuously redraw in editor to ensure visualization is updated
	if Engine.is_editor_hint():
		queue_redraw()


func _draw() -> void:
	# Only draw in editor when show_soi_in_editor is enabled
	if not Engine.is_editor_hint():
		return
	
	if not show_soi_in_editor:
		return
	
	var soi = _calculate_soi()
	
	# Draw filled circle for SOI
	draw_circle(Vector2.ZERO, soi, soi_color)
	
	# Draw border
	draw_arc(Vector2.ZERO, soi, 0, TAU, 64, soi_border_color, 2.0)
	
	# Draw target indicator if this is the target planet
	if is_target:
		var target_color = Color(0.0, 1.0, 0.3, 0.3)
		var target_border = Color(0.0, 1.0, 0.3, 0.8)
		draw_circle(Vector2.ZERO, soi * 0.1, target_color)
		draw_arc(Vector2.ZERO, soi * 0.1, 0, TAU, 32, target_border, 3.0)


func _calculate_soi() -> float:
	# Match the exact calculation from orbiting_body.gd calculate_sphere_of_influence()
	var base_gravity = 100000.0
	var gravity_ratio = gravitational_constant / base_gravity
	return base_sphere_of_influence * sqrt(gravity_ratio)

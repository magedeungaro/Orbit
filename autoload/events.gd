extends Node
## Global Event Bus - Centralized signal hub for decoupled communication

# Ship events
signal ship_thrust_started
signal ship_thrust_stopped
signal ship_fuel_changed(current: float, max_fuel: float)
signal ship_fuel_depleted
signal ship_crashed(planet: Node2D)
signal ship_exploded
signal ship_orientation_changed(lock_type: int)

# Game state events
signal game_state_changed(new_state: int)
signal game_started
signal game_paused
signal game_resumed
signal game_over
signal game_won
signal game_restarted

# Orbit events  
signal orbit_stability_changed(progress: float)
signal stable_orbit_achieved

# Camera events
signal camera_zoom_changed(zoom_level: float)

# Settings events
signal touch_controls_changed(enabled: bool)
signal settings_saved
signal settings_loaded

# Level events
signal level_changed(level_id: int)
signal level_completed(level_id: int, fuel_remaining: float)
signal level_unlocked(level_id: int)
signal level_loaded(level_id: int)

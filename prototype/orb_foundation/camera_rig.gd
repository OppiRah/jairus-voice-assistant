extends Node3D
## Minimal camera drift, disableable — not a showcase spin.
##
## Per JAIRUS_ORB_VFX_TECHNICAL_ARCHITECTURE.md section 14: subtle,
## irregular drift, with amplitude responding a little to `activity`, not a
## constant orbital spin. `drift_enabled` is exposed so the core can be
## evaluated with the camera perfectly still (debug_ui.gd's "Camera Drift"
## checkbox toggles this).

@export var drift_enabled: bool = true
@export var drift_amplitude_deg: float = 4.0
@export var drift_speed: float = 0.15

var _t := 0.0


func _process(delta: float) -> void:
	if not drift_enabled:
		return
	_t += delta

	var activity_boost := 1.0
	var energy := get_node_or_null("/root/EnergyModel")
	if energy:
		activity_boost = lerp(1.0, 1.6, energy.current_activity)

	rotation_degrees.y = sin(_t * drift_speed * activity_boost) * drift_amplitude_deg
	rotation_degrees.x = cos(_t * drift_speed * 0.7 * activity_boost) * drift_amplitude_deg * 0.5

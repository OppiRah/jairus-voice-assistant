extends Node
## Central shared-parameter authority for the orb foundation prototype.
##
## Owns the small set of parameters described in
## JAIRUS_ORB_VFX_TECHNICAL_ARCHITECTURE.md section 12. Every visual system
## (currently just the core shader) is meant to be a pure *consumer* of these
## values via Godot's global shader uniform mechanism — nothing downstream
## should ever reference this node directly for its shader behavior.
##
## This prototype has no knowledge of Jairus, WebSockets, or state names.
## Values are driven only by the debug UI (see debug_ui.gd) for now.

# Per-parameter smoothing rate (higher = snaps to target faster).
# Matches JAIRUS_ORB_VFX_TECHNICAL_ARCHITECTURE.md section 12's
# fast/medium/slow smoothing guidance.
const RATE_FAST := 6.0
const RATE_MEDIUM := 2.5
const RATE_SLOW := 1.0

const PULSE_DECAY_PER_SEC := 1.8

var target_intensity := 0.35
var target_activity := 0.25
var target_turbulence := 0.2
var target_coherence := 0.6
var target_core_morph := 0.0
var target_field_strength := 0.4
var target_particle_activity := 0.2
var target_symbol_reveal := 0.0

var current_intensity := target_intensity
var current_activity := target_activity
var current_turbulence := target_turbulence
var current_coherence := target_coherence
var current_core_morph := target_core_morph
var current_field_strength := target_field_strength
var current_particle_activity := target_particle_activity
var current_symbol_reveal := target_symbol_reveal
var current_pulse := 0.0


func _process(delta: float) -> void:
	current_intensity = _approach(current_intensity, target_intensity, RATE_FAST, delta)
	current_activity = _approach(current_activity, target_activity, RATE_MEDIUM, delta)
	current_turbulence = _approach(current_turbulence, target_turbulence, RATE_MEDIUM, delta)
	current_coherence = _approach(current_coherence, target_coherence, RATE_SLOW, delta)
	current_core_morph = _approach(current_core_morph, target_core_morph, RATE_SLOW, delta)
	current_field_strength = _approach(current_field_strength, target_field_strength, RATE_MEDIUM, delta)
	current_particle_activity = _approach(current_particle_activity, target_particle_activity, RATE_MEDIUM, delta)
	current_symbol_reveal = _approach(current_symbol_reveal, target_symbol_reveal, RATE_MEDIUM, delta)
	current_pulse = maxf(0.0, current_pulse - PULSE_DECAY_PER_SEC * delta)

	var rs := RenderingServer
	rs.global_shader_parameter_set("energy_intensity", current_intensity)
	rs.global_shader_parameter_set("energy_activity", current_activity)
	rs.global_shader_parameter_set("energy_turbulence", current_turbulence)
	rs.global_shader_parameter_set("energy_coherence", current_coherence)
	rs.global_shader_parameter_set("energy_core_morph", current_core_morph)
	rs.global_shader_parameter_set("energy_field_strength", current_field_strength)
	rs.global_shader_parameter_set("energy_particle_activity", current_particle_activity)
	rs.global_shader_parameter_set("energy_symbol_reveal", current_symbol_reveal)
	rs.global_shader_parameter_set("energy_pulse", current_pulse)


func _approach(current: float, target: float, rate: float, delta: float) -> float:
	var t := 1.0 - exp(-rate * delta)
	return lerp(current, target, t)


func set_intensity(v: float) -> void:
	target_intensity = clampf(v, 0.0, 1.0)


func set_activity(v: float) -> void:
	target_activity = clampf(v, 0.0, 1.0)


func set_turbulence(v: float) -> void:
	target_turbulence = clampf(v, 0.0, 1.0)


func set_coherence(v: float) -> void:
	target_coherence = clampf(v, 0.0, 1.0)


func set_core_morph(v: float) -> void:
	target_core_morph = clampf(v, 0.0, 1.0)


func set_field_strength(v: float) -> void:
	target_field_strength = clampf(v, 0.0, 1.0)


func set_particle_activity(v: float) -> void:
	target_particle_activity = clampf(v, 0.0, 1.0)


func set_symbol_reveal(v: float) -> void:
	target_symbol_reveal = clampf(v, 0.0, 1.0)


func trigger_pulse() -> void:
	current_pulse = 1.0

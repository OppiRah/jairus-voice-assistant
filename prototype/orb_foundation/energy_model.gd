extends Node
## Central shared-parameter authority for the orb foundation prototype.
##
## Owns the small set of parameters described in
## JAIRUS_ORB_VFX_TECHNICAL_ARCHITECTURE.md section 12. Every visual system
## (currently just the core shader) is meant to be a pure *consumer* of these
## values via Godot's global shader uniform mechanism — nothing downstream
## should ever reference this node directly for its shader behavior.
##
## This prototype has no knowledge of Jairus, WebSockets, or state names —
## except for STATE_PROFILES below, which names the 7 real Jairus states only
## as labels for target-parameter vectors (JAIRUS_ORB_FOUNDATION_PROTOTYPE.md
## section 18's state-personality validation pass). This still doesn't know
## about the bridge/WebSocket contract; `set_state()` is called by the debug
## UI, standing in for where a real state controller would call it later.
## Values are driven only by the debug UI (see debug_ui.gd) for now.

## Emitted at the end of set_state(), including when SUCCESS's own timer
## calls it internally to auto-revert to IDLE — debug_ui.gd listens for this
## instead of updating its own label/sliders only from the button press that
## triggered it, so the UI can't go stale after a state change it didn't
## directly cause.
signal state_changed(state_name: String)

# Per-parameter smoothing rate (higher = snaps to target faster).
# Matches JAIRUS_ORB_VFX_TECHNICAL_ARCHITECTURE.md section 12's
# fast/medium/slow smoothing guidance.
const RATE_FAST := 6.0
const RATE_MEDIUM := 2.5
const RATE_SLOW := 1.0

const PULSE_DECAY_PER_SEC := 1.8

# Named target-parameter vectors for the 7 real Jairus states, reasoned
# against JAIRUS_ORB_VFX_TECHNICAL_ARCHITECTURE.md section 13's table and
# the design brief's per-state personality direction (archived
# JAIRUS_ORB_VISUAL_DESIGN_DIRECTION.md section 13, which named this exact
# mechanism `STATE_PROFILES`) — see JAIRUS_ORB_FOUNDATION_PROTOTYPE.md
# section 18 for the full per-state reasoning. `camera_drift` isn't an
# EnergyModel/shader parameter; it's applied directly to CameraRig in
# `set_state()` because the brief explicitly calls out that OFFLINE should
# read as inactive rather than "IDLE but dimmer," and CameraRig's own
# activity-based amplitude modulation never reaches zero on its own (a real,
# separate finding — see the prototype doc).
const STATE_PROFILES := {
	"IDLE": {
		"intensity": 0.3, "activity": 0.2, "turbulence": 0.15, "coherence": 0.65,
		"core_morph": 0.1, "field_strength": 0.4, "particle_activity": 0.15,
		"symbol_reveal": 0.0, "camera_drift": true,
	},
	"LISTENING": {
		"intensity": 0.5, "activity": 0.45, "turbulence": 0.25, "coherence": 0.8,
		"core_morph": 0.25, "field_strength": 0.55, "particle_activity": 0.4,
		"symbol_reveal": 0.12, "camera_drift": true,
	},
	"THINKING": {
		"intensity": 0.7, "activity": 0.75, "turbulence": 0.75, "coherence": 0.55,
		"core_morph": 0.55, "field_strength": 0.7, "particle_activity": 0.7,
		"symbol_reveal": 0.05, "camera_drift": true,
	},
	"EXECUTING": {
		"intensity": 0.95, "activity": 0.9, "turbulence": 0.85, "coherence": 0.9,
		"core_morph": 0.8, "field_strength": 0.9, "particle_activity": 0.9,
		"symbol_reveal": 0.3, "camera_drift": true,
	},
	"SUCCESS": {
		"intensity": 0.55, "activity": 0.3, "turbulence": 0.15, "coherence": 0.85,
		"core_morph": 0.15, "field_strength": 0.45, "particle_activity": 0.35,
		"symbol_reveal": 0.9, "camera_drift": true,
	},
	"ERROR": {
		"intensity": 0.35, "activity": 0.4, "turbulence": 0.5, "coherence": 0.15,
		"core_morph": 0.4, "field_strength": 0.3, "particle_activity": 0.25,
		"symbol_reveal": 0.0, "camera_drift": true,
	},
	"OFFLINE": {
		"intensity": 0.08, "activity": 0.0, "turbulence": 0.0, "coherence": 0.6,
		"core_morph": 0.0, "field_strength": 0.05, "particle_activity": 0.0,
		"symbol_reveal": 0.0, "camera_drift": false,
	},
}

# SUCCESS is inherently transient (per the brief: "pulse, then settle back
# toward idle's baseline"), not a state that should be a permanent rest
# target — this is how long it holds before auto-reverting to IDLE.
const SUCCESS_HOLD_SEC := 2.0

var current_state_name := "IDLE"

# Cold-launch defaults now equal STATE_PROFILES["IDLE"] exactly, so there's
# one authoritative definition of "idle" instead of two slightly different
# ones (this used to be a separate, hand-tuned set of "idle-like" values
# left over from testing the core shader before STATE_PROFILES existed).
var target_intensity: float = STATE_PROFILES["IDLE"]["intensity"]
var target_activity: float = STATE_PROFILES["IDLE"]["activity"]
var target_turbulence: float = STATE_PROFILES["IDLE"]["turbulence"]
var target_coherence: float = STATE_PROFILES["IDLE"]["coherence"]
var target_core_morph: float = STATE_PROFILES["IDLE"]["core_morph"]
var target_field_strength: float = STATE_PROFILES["IDLE"]["field_strength"]
var target_particle_activity: float = STATE_PROFILES["IDLE"]["particle_activity"]
var target_symbol_reveal: float = STATE_PROFILES["IDLE"]["symbol_reveal"]

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


## Applies a named STATE_PROFILES vector as the new smoothing targets — this
## does NOT snap current_* values; the existing per-parameter smoothing
## rates above carry the transition, which is the point being tested (see
## JAIRUS_ORB_FOUNDATION_PROTOTYPE.md section 18).
func set_state(state_name: String) -> void:
	if not STATE_PROFILES.has(state_name):
		push_warning("EnergyModel.set_state: unknown state %s" % state_name)
		return

	current_state_name = state_name
	var profile: Dictionary = STATE_PROFILES[state_name]
	set_intensity(profile["intensity"])
	set_activity(profile["activity"])
	set_turbulence(profile["turbulence"])
	set_coherence(profile["coherence"])
	set_core_morph(profile["core_morph"])
	set_field_strength(profile["field_strength"])
	set_particle_activity(profile["particle_activity"])
	set_symbol_reveal(profile["symbol_reveal"])

	var rig := get_node_or_null("/root/Main/CameraRig")
	if rig:
		rig.drift_enabled = profile["camera_drift"]

	state_changed.emit(state_name)

	if state_name == "SUCCESS":
		trigger_pulse()
		var timer := get_tree().create_timer(SUCCESS_HOLD_SEC)
		timer.timeout.connect(func():
			if current_state_name == "SUCCESS":
				set_state("IDLE")
		)

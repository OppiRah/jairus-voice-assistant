extends Control
## Disposable development tooling (JAIRUS_ORB_VFX_TECHNICAL_ARCHITECTURE.md
## section 20 / task section 20): plain sliders wired straight to
## EnergyModel's setters, built in code rather than hand-laid-out in the
## editor. Not meant to survive into the real orb.
##
## Also exposes EnergyModel.STATE_PROFILES as one button per named Jairus
## state (JAIRUS_ORB_FOUNDATION_PROTOTYPE.md section 18) — pressing one calls
## EnergyModel.set_state(), which only changes smoothing *targets*; the
## sliders below will visibly animate toward the new state's values over the
## next second or two rather than jumping, since nothing here bypasses
## EnergyModel's existing per-parameter smoothing.

var _energy: Node
var _state_label: Label
var _camera_toggle: CheckButton
var _sliders: Dictionary = {}

## Scripted-capture harness (state-profile validation testing only): command
## line args let a launch script drive states/screenshots deterministically
## instead of an OS-level screen capture racing this machine's window
## z-order (the "always on top" flag was found unreliable against other
## foreground windows during this pass — see the prototype doc). Format:
## --state=NAME               sets the initial state immediately.
## --switch=NAME:t[,NAME:t]   switches to NAME at elapsed-second t.
## --shots=path:t[,path:t]    saves a PNG of the live viewport at elapsed t.
## Quits automatically after the last scheduled shot. No effect if --shots
## isn't passed, so normal interactive runs are unaffected.
var _elapsed := 0.0
var _pending_switches: Array = []
var _pending_shots: Array = []


func _ready() -> void:
	anchor_right = 1.0
	anchor_bottom = 1.0
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	_energy = get_node("/root/EnergyModel")

	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.position = Vector2(12, 12)
	panel.custom_minimum_size = Vector2(260, 0)
	add_child(panel)

	var vbox := VBoxContainer.new()
	panel.add_child(vbox)

	_state_label = Label.new()
	_state_label.text = "State: %s" % _energy.current_state_name
	vbox.add_child(_state_label)

	var state_grid := GridContainer.new()
	state_grid.columns = 2
	for state_name in _energy.STATE_PROFILES.keys():
		var state_btn := Button.new()
		state_btn.text = state_name
		state_btn.pressed.connect(func(): _energy.set_state(state_name))
		state_grid.add_child(state_btn)
	vbox.add_child(state_grid)

	_add_slider(vbox, "intensity", "Intensity", _energy.target_intensity, func(v): _energy.set_intensity(v))
	_add_slider(vbox, "activity", "Activity", _energy.target_activity, func(v): _energy.set_activity(v))
	_add_slider(vbox, "turbulence", "Turbulence", _energy.target_turbulence, func(v): _energy.set_turbulence(v))
	_add_slider(vbox, "coherence", "Coherence", _energy.target_coherence, func(v): _energy.set_coherence(v))
	_add_slider(vbox, "core_morph", "Core Morph", _energy.target_core_morph, func(v): _energy.set_core_morph(v))
	_add_slider(vbox, "field_strength", "Field Strength", _energy.target_field_strength, func(v): _energy.set_field_strength(v))
	_add_slider(vbox, "particle_activity", "Particle Activity", _energy.target_particle_activity, func(v): _energy.set_particle_activity(v))
	_add_slider(vbox, "symbol_reveal", "Symbol Reveal", _energy.target_symbol_reveal, func(v): _energy.set_symbol_reveal(v))

	var pulse_btn := Button.new()
	pulse_btn.text = "Trigger Pulse"
	pulse_btn.pressed.connect(func(): _energy.trigger_pulse())
	vbox.add_child(pulse_btn)

	_camera_toggle = CheckButton.new()
	_camera_toggle.text = "Camera Drift"
	_camera_toggle.button_pressed = true
	var rig := get_node_or_null("/root/Main/CameraRig")
	if rig:
		_camera_toggle.toggled.connect(func(on): rig.drift_enabled = on)
	vbox.add_child(_camera_toggle)

	_energy.state_changed.connect(_on_state_changed)
	_parse_capture_args()


func _parse_capture_args() -> void:
	for arg in OS.get_cmdline_args():
		if arg.begins_with("--state="):
			_energy.set_state(arg.substr(8))
		elif arg.begins_with("--switch="):
			for pair in arg.substr(9).split(","):
				var kv := pair.split(":")
				_pending_switches.append({"name": kv[0], "t": float(kv[1])})
		elif arg.begins_with("--shots="):
			for pair in arg.substr(8).split(","):
				var sep := pair.rfind(":")
				_pending_shots.append({"path": pair.substr(0, sep), "t": float(pair.substr(sep + 1))})
	_pending_switches.sort_custom(func(a, b): return a["t"] < b["t"])
	_pending_shots.sort_custom(func(a, b): return a["t"] < b["t"])


func _process(delta: float) -> void:
	if _pending_shots.is_empty() and _pending_switches.is_empty():
		return
	_elapsed += delta

	while not _pending_switches.is_empty() and _elapsed >= _pending_switches[0]["t"]:
		_energy.set_state(_pending_switches.pop_front()["name"])

	while not _pending_shots.is_empty() and _elapsed >= _pending_shots[0]["t"]:
		var shot: Dictionary = _pending_shots.pop_front()
		var img := get_viewport().get_texture().get_image()
		img.save_png(shot["path"])
		if _pending_shots.is_empty() and _pending_switches.is_empty():
			get_tree().quit()


## Connected to EnergyModel.state_changed rather than called directly from
## the button press, so a state change EnergyModel makes on its own (SUCCESS's
## auto-revert to IDLE) keeps this display in sync too, not just ones this
## UI initiated itself.
func _on_state_changed(state_name: String) -> void:
	_state_label.text = "State: %s" % state_name
	# set_state() only moves EnergyModel's *targets* (see energy_model.gd) —
	# the sliders below are cosmetic reflections of those targets, so they're
	# synced here to match, not because this bypasses the smoothing; the
	# core itself still animates toward the new values over the next second
	# or two exactly as if a slider had been dragged.
	var profile: Dictionary = _energy.STATE_PROFILES[state_name]
	for key in profile.keys():
		if _sliders.has(key):
			_sliders[key].value = profile[key]
	_camera_toggle.button_pressed = profile["camera_drift"]


func _add_slider(parent: Node, param_key: String, label_text: String, initial: float, on_change: Callable) -> void:
	var row := VBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = initial
	slider.value_changed.connect(on_change)
	row.add_child(slider)
	parent.add_child(row)
	_sliders[param_key] = slider

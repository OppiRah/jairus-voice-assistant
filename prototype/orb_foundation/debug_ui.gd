extends Control
## Disposable development tooling (JAIRUS_ORB_VFX_TECHNICAL_ARCHITECTURE.md
## section 20 / task section 20): plain sliders wired straight to
## EnergyModel's setters, built in code rather than hand-laid-out in the
## editor. Not meant to survive into the real orb.

var _energy: Node


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

	_add_slider(vbox, "Intensity", _energy.target_intensity, func(v): _energy.set_intensity(v))
	_add_slider(vbox, "Activity", _energy.target_activity, func(v): _energy.set_activity(v))
	_add_slider(vbox, "Turbulence", _energy.target_turbulence, func(v): _energy.set_turbulence(v))
	_add_slider(vbox, "Coherence", _energy.target_coherence, func(v): _energy.set_coherence(v))
	_add_slider(vbox, "Core Morph", _energy.target_core_morph, func(v): _energy.set_core_morph(v))
	_add_slider(vbox, "Field Strength", _energy.target_field_strength, func(v): _energy.set_field_strength(v))
	_add_slider(vbox, "Particle Activity", _energy.target_particle_activity, func(v): _energy.set_particle_activity(v))
	_add_slider(vbox, "Symbol Reveal", _energy.target_symbol_reveal, func(v): _energy.set_symbol_reveal(v))

	var pulse_btn := Button.new()
	pulse_btn.text = "Trigger Pulse"
	pulse_btn.pressed.connect(func(): _energy.trigger_pulse())
	vbox.add_child(pulse_btn)

	var camera_toggle := CheckButton.new()
	camera_toggle.text = "Camera Drift"
	camera_toggle.button_pressed = true
	var rig := get_node_or_null("/root/Main/CameraRig")
	if rig:
		camera_toggle.toggled.connect(func(on): rig.drift_enabled = on)
	vbox.add_child(camera_toggle)


func _add_slider(parent: Node, label_text: String, initial: float, on_change: Callable) -> void:
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

extends Node3D
## orb_controller.gd — Jairus Orb Renderer PoC.
##
## Throwaway/experimental script validating ORB_RENDERER_INVESTIGATION.md's
## recommendation. Connects to a local WebSocket (test_driver.py, NOT the
## real Jairus Android Gateway on port 8765 — this uses 8766, a
## deliberately separate port) and drives the orb's color/pulse/particle
## behavior purely from received JSON state messages. Never calls into
## anything resembling Jairus's real Agent Core/tools -- this process has
## no awareness of them at all, by design.

const WS_URL := "ws://localhost:8766"

# Same per-state colors as the real app's theme.py (theme.ORB_COLORS),
# normalized to 0..1 floats -- cosmetic parity for a meaningful preview,
# not load-bearing for the PoC's actual pass/fail questions.
const STATE_COLORS := {
	"idle": Color(70.0 / 255.0, 130.0 / 255.0, 200.0 / 255.0),
	"listening": Color(60.0 / 255.0, 200.0 / 255.0, 140.0 / 255.0),
	"thinking": Color(170.0 / 255.0, 90.0 / 255.0, 220.0 / 255.0),
	"speaking": Color(250.0 / 255.0, 170.0 / 255.0, 60.0 / 255.0),
}
const EMISSION_ENERGY := 3.5  # HDR multiplier so the color actually blooms

@onready var core: MeshInstance3D = $Core
@onready var particles: GPUParticles3D = $AmbientParticles

var _socket := WebSocketPeer.new()
var _connected_once := false
var _current_color := STATE_COLORS["idle"]
var _target_color := STATE_COLORS["idle"]
var _level := 0.0
var _elapsed := 0.0
var _material: StandardMaterial3D


func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core.set_surface_override_material(0, _material)
	_apply_color(_current_color)
	var err := _socket.connect_to_url(WS_URL)
	if err != OK:
		print("[orb_controller] connect_to_url failed immediately: ", err)


func _process(delta: float) -> void:
	_elapsed += delta
	_poll_socket()

	# smooth transition between states, same spirit as the real orb's
	# breathing/pulse math (assistant_state.py's level + a sine breathe)
	_current_color = _current_color.lerp(_target_color, delta * 4.0)
	_apply_color(_current_color)

	var breathe := (sin(_elapsed * 1.6) + 1.0) / 2.0
	var pulse_scale := 1.0 + 0.12 * breathe + 0.25 * _level
	core.scale = Vector3.ONE * pulse_scale

	if particles:
		particles.amount_ratio = clamp(0.3 + _level, 0.0, 1.0)


func _poll_socket() -> void:
	_socket.poll()
	var state := _socket.get_ready_state()

	if state == WebSocketPeer.STATE_OPEN:
		if not _connected_once:
			_connected_once = true
			print("[orb_controller] connected to ", WS_URL)
		while _socket.get_available_packet_count() > 0:
			var packet := _socket.get_packet()
			_handle_message(packet.get_string_from_utf8())
	elif state == WebSocketPeer.STATE_CLOSING:
		pass
	elif state == WebSocketPeer.STATE_CLOSED:
		if _connected_once:
			var code := _socket.get_close_code()
			print("[orb_controller] connection closed, code=", code)
			_connected_once = false


func _handle_message(raw_text: String) -> void:
	var data = JSON.parse_string(raw_text)
	if data == null or not (data is Dictionary):
		print("[orb_controller] received unparseable message: ", raw_text)
		return

	print("[orb_controller] received state message: ", data)

	var new_state: String = data.get("state", "idle")
	_target_color = STATE_COLORS.get(new_state, STATE_COLORS["idle"])
	_level = clamp(float(data.get("level", 0.0)), 0.0, 1.0)


func _apply_color(color: Color) -> void:
	_material.albedo_color = color
	_material.emission = color
	_material.emission_energy_multiplier = EMISSION_ENERGY

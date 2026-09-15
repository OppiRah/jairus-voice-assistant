extends Node3D
## glass_poc_test.tscn's root script -- standalone glass/PBR material
## investigation test, NOT wired into the real orb_scene.tscn/
## orb_controller.gd in any way. Widens the window beyond the orb's
## 480x480 production size purely so both test shells and their labels are
## comfortably visible side by side; inherits the project's transparent/
## borderless/always-on-top settings unchanged, since testing real
## OS-compositor transparency is the whole point of this scene.

const WINDOW_SIZE := Vector2i(700, 500)


func _ready() -> void:
	get_window().size = WINDOW_SIZE
	print("[glass_poc_test] ready: FresnelShell + RefractionShell + BackgroundMarker instanced")

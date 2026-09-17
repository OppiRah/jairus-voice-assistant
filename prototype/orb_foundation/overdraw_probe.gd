extends Node
## Overdraw measurement tool (JAIRUS_ORB_VFX_TECHNICAL_ARCHITECTURE.md
## section 16: "Overdraw from layered transparency... is the #1 thing to
## measure early, not late," section 18's risk register: "Layered-
## transparency overdraw exceeds budget once shells+wisps+particles all
## render together" -- "Measure early with even placeholder geometry").
##
## The doc gives no single numeric overdraw ceiling anywhere -- the actual
## requirement is qualitative ("small fixed shell count," section 5's "hard
## ceiling," measured with "Godot's built-in profiler/monitors"). This uses
## Viewport.debug_draw = DEBUG_DRAW_OVERDRAW, a real, documented Godot
## rendering mode that additively tints each pixel by how many
## transparent/overlapping draws touched it, then samples the resulting
## image's average channel brightness as a real, comparable-across-scenes
## overdraw proxy number (not FPS, which section 16 explicitly warns can
## look fine while fill-rate cost is real).
##
## --overdraw=path:t   saves an image.get_pixels() average-brightness
##                      readout to res://overdraw_log.txt at elapsed second t,
##                      after switching the viewport into overdraw debug
##                      draw mode. No effect unless this arg is passed, so
##                      scenes without this node/arg are unaffected.

var _pending: Array = []
var _elapsed := 0.0
var _log_file: FileAccess


func _ready() -> void:
	for arg in OS.get_cmdline_args():
		if arg.begins_with("--overdraw="):
			for pair in arg.substr(11).split(","):
				var sep := pair.rfind(":")
				_pending.append({"path": pair.substr(0, sep), "t": float(pair.substr(sep + 1))})
	if _pending.is_empty():
		return
	_pending.sort_custom(func(a, b): return a["t"] < b["t"])
	get_viewport().debug_draw = Viewport.DEBUG_DRAW_OVERDRAW
	_log_file = FileAccess.open("res://overdraw_log.txt", FileAccess.WRITE)


func _process(delta: float) -> void:
	if _pending.is_empty():
		return
	_elapsed += delta
	while not _pending.is_empty() and _elapsed >= _pending[0]["t"]:
		var entry: Dictionary = _pending.pop_front()
		var img := get_viewport().get_texture().get_image()
		img.save_png(entry["path"])
		var avg := _average_brightness(img)
		var line := "overdraw_avg_brightness path=%s t=%.2f value=%.5f" % [entry["path"], entry["t"], avg]
		print(line)
		if _log_file:
			_log_file.store_line(line)
			_log_file.flush()
		if _pending.is_empty():
			get_tree().quit()


## Mean of (R+G+B)/3 across every pixel, ignoring alpha -- DEBUG_DRAW_OVERDRAW
## additively tints white per overlapping draw, so a higher mean here is a
## real, direct proxy for "how much overlapping transparency this frame
## paid for," comparable across scenes/captures using the same camera and
## resolution.
func _average_brightness(img: Image) -> float:
	var w := img.get_width()
	var h := img.get_height()
	var step := 4 # sample every 4th pixel in each axis -- plenty for a stable average, far cheaper than every pixel
	var sum := 0.0
	var count := 0
	var y := 0
	while y < h:
		var x := 0
		while x < w:
			var c := img.get_pixel(x, y)
			sum += (c.r + c.g + c.b) / 3.0
			count += 1
			x += step
		y += step
	return sum / max(count, 1)

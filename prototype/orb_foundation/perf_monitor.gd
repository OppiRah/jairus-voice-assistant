extends Node
## Baseline performance logging for the foundation prototype.
##
## Not an optimization pass — just records real, measured numbers to
## res://perf_log.txt (and stdout) so JAIRUS_ORB_FOUNDATION_PROTOTYPE.md can
## report actual figures instead of invented ones. Samples Godot's built-in
## Performance singleton, which is the documented, real source for these
## values (no custom timing/estimation logic).

const SAMPLE_INTERVAL_SEC := 1.0

var _time_accum := 0.0
var _log_file: FileAccess
var _core_vertex_count := -1
var _core_triangle_count := -1


func _ready() -> void:
	_log_file = FileAccess.open("res://perf_log.txt", FileAccess.WRITE)
	_write_line("=== Jairus Orb Foundation Prototype — perf log ===")
	_write_line("Godot version: %s" % Engine.get_version_info().string)
	_write_line("Viewport size: %s" % str(get_viewport().size))
	_write_line("Rendering method: %s" % ProjectSettings.get_setting("rendering/renderer/rendering_method"))
	_write_line("DIAG window transparent flag: %s" % str(DisplayServer.window_get_flag(DisplayServer.WINDOW_FLAG_TRANSPARENT)))
	_write_line("DIAG per_pixel_transparency setting: %s" % str(ProjectSettings.get_setting("display/window/per_pixel_transparency/allowed")))
	_write_line("DIAG transparent_background setting: %s" % str(ProjectSettings.get_setting("rendering/transparent_background")))
	_write_line("DIAG is_layered_allowed: %s" % str(DisplayServer.get_name()))


func report_core_stats(vertex_count: int, triangle_count: int) -> void:
	_core_vertex_count = vertex_count
	_core_triangle_count = triangle_count
	_write_line("Core mesh: %d vertices, %d triangles" % [vertex_count, triangle_count])


func _process(delta: float) -> void:
	_time_accum += delta
	if _time_accum < SAMPLE_INTERVAL_SEC:
		return
	_time_accum = 0.0

	var fps := Performance.get_monitor(Performance.TIME_FPS)
	var frame_time_ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var draw_calls := Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
	var primitives := Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
	var video_mem_mb := Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / (1024.0 * 1024.0)

	var line := "FPS=%.1f frame_ms=%.3f draw_calls=%d primitives=%d video_mem_mb=%.1f" % [
		fps, frame_time_ms, draw_calls, primitives, video_mem_mb
	]
	print(line)
	_write_line(line)


func _write_line(line: String) -> void:
	if _log_file:
		_log_file.store_line(line)
		_log_file.flush()


func _exit_tree() -> void:
	if _log_file:
		_log_file.close()

shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded;

// Pass B (energy ribbons, take 2): replaces the old binary sin()>threshold
// on/off flicker with continuous brightness that travels ALONG the
// ribbon's length over time, never fully snapping on or off -- see
// _build_arc_mesh()'s UV.x tagging (0.0 at one end of the path, 1.0 at
// the other) for how each vertex knows its own position along the arc.
// Uses Godot's built-in TIME (no per-frame uniform push needed for the
// animation itself -- deterministic, same wall-clock time always
// produces the same frame, same "reproducible, not random" principle
// the rest of this file already follows for the arcs' jagged path).
// flow_speed/turbulence are the only values _process() still pushes
// per-frame, from STATE_PROFILES, same pattern as every other shader
// material in this project (CoreHousing, the 4 glass shells).
uniform vec3 base_color : source_color = vec3(1.0);
uniform float emission_energy : hint_range(0.0, 20.0) = 2.0;
uniform float alpha = 0.6;
uniform float flow_speed : hint_range(-4.0, 4.0) = 1.0;
uniform float turbulence : hint_range(0.0, 1.0) = 0.3;
uniform float ripple_cycles : hint_range(0.5, 6.0) = 2.0;
uniform float time_offset = 0.0;

void fragment() {
	float phase = UV.x * ripple_cycles * TAU - TIME * flow_speed * TAU + time_offset;
	float wave = (sin(phase) + 1.0) * 0.5; // 0..1, continuous -- no threshold, no hard cutoff

	// turbulence controls how deep the ripple dips: 0.0 stays close to
	// full brightness the whole time (a calm, barely-perceptible shimmer);
	// 1.0 swings from near-invisible to full (an unstable, crackling
	// read) -- but brightness_min never reaches exactly 0.0, so the
	// ribbon is never fully off, which is the entire point of this pass.
	float brightness_min = mix(0.85, 0.15, turbulence);
	float brightness = mix(brightness_min, 1.0, wave);

	ALBEDO = base_color;
	EMISSION = base_color * emission_energy * brightness;
	ALPHA = alpha * mix(0.55, 1.0, brightness);
}

shader_type spatial;
render_mode unshaded;

// VFX technique investigation PoC only -- NOT wired into orb_scene.tscn.
// Tests design-doc section 4's still-unaddressed "subtle internal
// motion" for the core: a real, Godot-generated FastNoiseLite texture
// (assigned as `noise_tex` from vfx_technique_poc_test.gd) scrolled over
// the sphere's own UV to modulate emission brightness, instead of the
// real orb's current flat, uniform emissive core.
uniform vec3 base_color : source_color = vec3(0.55, 0.75, 1.0);
uniform float emission_energy : hint_range(0.0, 10.0) = 4.0;
uniform sampler2D noise_tex : repeat_enable;
uniform float noise_scale : hint_range(0.5, 8.0) = 2.0;
uniform float noise_speed : hint_range(0.0, 2.0) = 0.3;
uniform float noise_strength : hint_range(0.0, 1.0) = 0.35;

void fragment() {
	vec2 scrolled_uv = UV * noise_scale + vec2(TIME * noise_speed, TIME * noise_speed * 0.6);
	float n = texture(noise_tex, scrolled_uv).r;
	float modulation = mix(1.0 - noise_strength, 1.0, n);
	ALBEDO = base_color * modulation;
	EMISSION = base_color * emission_energy * modulation;
}

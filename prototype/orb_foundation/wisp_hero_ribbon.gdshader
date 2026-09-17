shader_type spatial;
render_mode blend_mix, cull_disabled, unshaded;

#include "res://energy_common.gdshaderinc"

// Candidate B (wisp decision prototype, JAIRUS_ORB_VFX_TECHNICAL_ARCHITECTURE.md
// section 11 table row 2 / section 19 step 4): flow-shader technique reused
// directly from archive/orb_v1/godot_project/orb_arc_ribbon.gdshader's
// continuous traveling-brightness-wave approach (UV.x tags each vertex's
// position along the ribbon, see wisp_system_b.gd's _build_ribbon_strip_mesh)
// -- never a hard on/off snap, same reasoning as that shader's own comment.
//
// Difference from the archived version: this reads the shared
// energy_activity/energy_turbulence/energy_intensity global uniforms
// directly (energy_common.gdshaderinc) instead of local uniforms a
// controller script pushes per-frame -- one of the actual comparison axes
// against Candidate A, which needs a script reading EnergyModel every frame
// for its non-shader GPUParticles3D properties.
uniform vec3 base_color : source_color = vec3(0.85, 0.65, 0.18);
uniform float ripple_cycles : hint_range(0.5, 6.0) = 2.0;
uniform float time_offset = 0.0;
uniform float base_alpha : hint_range(0.0, 1.0) = 0.5;

void fragment() {
	float flow_speed = mix(0.15, 2.5, energy_activity);
	float turb = clamp(energy_turbulence, 0.0, 1.0);
	float phase = UV.x * ripple_cycles * TAU - TIME * flow_speed * TAU + time_offset;
	float wave = (sin(phase) + 1.0) * 0.5; // 0..1, continuous -- no threshold

	// turbulence controls ripple depth, same as the archived shader's own
	// brightness_min mechanism -- never reaches exactly 0.0.
	float brightness_min = mix(0.85, 0.15, turb);
	float brightness = mix(brightness_min, 1.0, wave);

	ALBEDO = base_color;
	// Kept dim (0.3-1.6 range) so this stays subordinate to the core's own
	// emission per the architecture's brightness-hierarchy principle.
	EMISSION = base_color * mix(0.3, 1.6, energy_intensity) * brightness;
	ALPHA = base_alpha * mix(0.5, 1.0, brightness);
}

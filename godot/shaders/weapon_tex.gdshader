// First-person weapon with scanned / textured models. Two texture layouts:
//  - use_arm = 1 (Poly Haven): albedo, OpenGL normal and an ARM map (R occlusion, G roughness, B metallic)
//  - use_arm = 0 (older game assets): albedo + separate roughness map + specular map; metal is
//    derived from the specular brightness (bare steel is bright there, wood / polymer dark)
// Depth is pulled toward the near plane like weapon.gdshader so the gun never sinks into walls.
// `camo` blends in the upgrade finish.
shader_type spatial;
render_mode cull_back;

uniform sampler2D tex_alb : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_nor : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_arm : hint_default_white, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_rough : hint_default_white, filter_linear_mipmap_anisotropic;
uniform sampler2D tex_spec : hint_default_black, filter_linear_mipmap_anisotropic;
uniform float use_arm = 1.0;
uniform float rough_mul = 1.0;
uniform vec4 tint : source_color = vec4(1.0);
uniform float camo = 0.0;
uniform vec4 emission : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;

void vertex() {
	POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	POSITION.z = mix(POSITION.z, POSITION.w, 0.97);
}

void fragment() {
	vec3 a = texture(tex_alb, UV).rgb;
	float ao = 1.0;
	float rough;
	float metal;
	if (use_arm > 0.5) {
		vec3 arm = texture(tex_arm, UV).rgb;
		ao = arm.r;
		rough = arm.g;
		metal = arm.b;
		NORMAL_MAP = texture(tex_nor, UV).rgb;
	} else {
		rough = clamp(texture(tex_rough, UV).r * rough_mul, 0.08, 1.0);
		float sp = dot(texture(tex_spec, UV).rgb, vec3(0.333));
		metal = smoothstep(0.22, 0.55, sp);
	}
	float lum = dot(a, vec3(0.3, 0.59, 0.11));
	ALBEDO = mix(a, tint.rgb * clamp(lum * 2.4, 0.5, 1.6), camo);
	AO = ao;
	AO_LIGHT_AFFECT = 0.5;
	ROUGHNESS = mix(rough, 0.3, camo);
	METALLIC = mix(metal, 0.9, camo);
	EMISSION = emission.rgb * emission_energy;
}

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
// Armero camouflage: pattern 0 = solid finish (tint), 1 = three-colour blotches (tint / c2 / c3),
// 2 = digital squares. Painted finishes are matte (paint_rough / paint_metal).
uniform float pattern = 0.0;
uniform vec4 c2 : source_color = vec4(0.3, 0.3, 0.3, 1.0);
uniform vec4 c3 : source_color = vec4(0.1, 0.1, 0.1, 1.0);
uniform float pat_scale = 9.0;
uniform float paint_rough = 0.3;
uniform float paint_metal = 0.9;
varying vec3 obj;

float h3(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h3(i), h3(i + vec3(1, 0, 0)), f.x), mix(h3(i + vec3(0, 1, 0)), h3(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(h3(i + vec3(0, 0, 1)), h3(i + vec3(1, 0, 1)), f.x), mix(h3(i + vec3(0, 1, 1)), h3(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

void vertex() {
	// pattern space in metres whatever the mesh units (the AK FBX meshes are in centimetres)
	obj = VERTEX * length(MODEL_MATRIX[0].xyz);
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
	vec3 paint = tint.rgb;
	if (pattern > 0.5) {
		vec3 q = obj * pat_scale;
		if (pattern > 1.5) {
			q = floor(q * 2.0) / 2.0;   // digital: blocky cells
		}
		float n1 = vnoise(q) * 0.65 + vnoise(q * 2.3 + 7.1) * 0.35;
		float n2 = vnoise(q * 1.4 + 31.0);
		paint = mix(tint.rgb, c2.rgb, step(0.48, n1));
		paint = mix(paint, c3.rgb, step(0.62, n2));
	}
	ALBEDO = mix(a, paint * clamp(lum * 2.4, 0.5, 1.6), camo);
	AO = ao;
	AO_LIGHT_AFFECT = 0.5;
	ROUGHNESS = mix(rough, paint_rough, camo);
	METALLIC = mix(metal, paint_metal, camo);
	EMISSION = emission.rgb * emission_energy;
}

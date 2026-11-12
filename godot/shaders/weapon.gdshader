// First-person weapon: normal lit surface, but its depth is pulled toward the near plane
// so the gun and hands never sink into walls (Godot 4 uses reverse-Z: depth = w at the near plane).
// A scanned detail normal/roughness map (metal grain, polymer stipple, wood grain, glove fabric)
// is projected in object space so every part gets real surface definition without UVs.
shader_type spatial;
render_mode cull_back;

uniform vec4 albedo : source_color = vec4(0.2, 0.2, 0.2, 1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.6;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform vec4 emission : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float emission_energy = 0.0;
uniform sampler2D detail_nor : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_rough : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float detail_scale = 25.0;
uniform float detail_strength = 0.0;
uniform sampler2D detail_alb : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
// 0 = scanned colour only modulates brightness (wear, grime), 1 = full scanned colour (wood grain, leather)
uniform float detail_alb_mode = 0.0;
uniform float detail_alb_mix = 0.0;

varying vec3 lp;
varying vec3 ln;

void vertex() {
	lp = VERTEX;
	ln = NORMAL;
	POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	POSITION.z = mix(POSITION.z, POSITION.w, 0.97);
}

void fragment() {
	ALBEDO = albedo.rgb;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	EMISSION = emission.rgb * emission_energy;
	if (detail_strength > 0.0) {
		vec3 an = abs(ln);
		vec2 uv = (an.x > an.y && an.x > an.z) ? lp.zy : ((an.y > an.z) ? lp.xz : lp.xy);
		uv *= detail_scale;
		NORMAL_MAP = texture(detail_nor, uv).rgb;
		NORMAL_MAP_DEPTH = detail_strength;
		float r = texture(detail_rough, uv).r;
		ROUGHNESS = clamp(roughness * mix(1.0, 0.55 + r * 0.9, detail_strength), 0.05, 1.0);
		vec3 sc = texture(detail_alb, uv).rgb;
		float lum = dot(sc, vec3(0.3, 0.59, 0.11));
		vec3 worn = albedo.rgb * clamp(lum * 2.2, 0.55, 1.6);
		vec3 full = sc * albedo.rgb * 2.4;
		ALBEDO = mix(albedo.rgb, mix(worn, full, detail_alb_mode), detail_alb_mix);
		ALBEDO *= mix(1.0, 0.88 + r * 0.24, detail_strength * 0.5);
	}
}

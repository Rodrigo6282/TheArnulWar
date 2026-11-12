// First-person arms (skinned Mixamo body, see scripts/fp_arms.gd): the character's own textures,
// with the same depth pull toward the near plane as weapon.gdshader so arms and gun never sink
// into walls and always sort together.
shader_type spatial;
render_mode cull_back;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic;
uniform bool has_normal = false;
uniform vec3 tint = vec3(1.0);
uniform float roughness : hint_range(0.0, 1.0) = 0.78;

void vertex() {
	POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	POSITION.z = mix(POSITION.z, POSITION.w, 0.97);
}

void fragment() {
	ALBEDO = texture(albedo_tex, UV).rgb * tint;
	if (has_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
	}
	ROUGHNESS = roughness;
}

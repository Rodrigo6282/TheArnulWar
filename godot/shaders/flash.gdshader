// Muzzle flash star: additive, unshaded, always facing the camera, drawn in front like the weapon.
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

uniform vec4 color : source_color = vec4(1.0, 0.75, 0.35, 1.0);
uniform float energy = 4.0;
uniform float spin = 0.0;

void vertex() {
	// billboard
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	POSITION.z = mix(POSITION.z, POSITION.w, 0.96);
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float a = atan(p.y, p.x) + spin;
	float star = 0.55 + 0.45 * cos(a * 8.0);
	float core = smoothstep(1.0, 0.0, r / max(star, 0.2));
	ALBEDO = color.rgb * energy * core * core;
	ALPHA = core;
}

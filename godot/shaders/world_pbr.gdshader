// World surfaces (ground, walls, props): same photoscanned triplanar PBR as the old
// StandardMaterial3D, plus weather driven by two global uniforms set per map in main.apply_env():
//   wetness     0..1  darker, glossier surfaces; flat ground collects mirror-like puddles
//   snow_cover  0..1  snow settles on upward-facing surfaces (roofs, crates, ledges)
// Puddle/snow patterns come from world position, so they are stable and seamless across meshes.
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D tex_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D tex_rough : hint_roughness_r, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec4 tint : source_color = vec4(1.0);
uniform float uv_scale = 0.5;
uniform float metal = 0.0;
uniform bool world_tri = true;
// per material: how much water it soaks up (metal and snow stay brighter when wet)
uniform float porosity = 1.0;
// multiply by the vertex / instance colour (MultiMesh variation)
uniform bool vcol = false;

global uniform float wetness;
global uniform float snow_cover;

varying vec3 tri_w;
varying vec3 tri_p;
varying vec3 w_pos;
varying vec3 w_nrm;

void vertex() {
	w_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	w_nrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	// identical to StandardMaterial3D triplanar (blend sharpness 1)
	TANGENT = vec3(0.0, 0.0, -1.0) * abs(NORMAL.x);
	TANGENT += vec3(1.0, 0.0, 0.0) * abs(NORMAL.y);
	TANGENT += vec3(1.0, 0.0, 0.0) * abs(NORMAL.z);
	TANGENT = normalize(TANGENT);
	BINORMAL = vec3(0.0, 1.0, 0.0) * abs(NORMAL.x);
	BINORMAL += vec3(0.0, 0.0, -1.0) * abs(NORMAL.y);
	BINORMAL += vec3(0.0, 1.0, 0.0) * abs(NORMAL.z);
	BINORMAL = normalize(BINORMAL);
	vec3 n = world_tri ? w_nrm : NORMAL;
	tri_w = abs(n);
	tri_w /= dot(tri_w, vec3(1.0));
	tri_p = (world_tri ? w_pos : VERTEX) * uv_scale;
	tri_p *= vec3(1.0, -1.0, 1.0);
}

// skips the projections that don't contribute (floors and straight walls need just one sample)
// (explicit gradients: mipmaps stay correct inside the branches)
vec4 tri(sampler2D s) {
	vec4 r = vec4(0.0);
	vec3 dx = dFdx(tri_p);
	vec3 dy = dFdy(tri_p);
	if (tri_w.z > 0.002) { r += textureGrad(s, tri_p.xy, dx.xy, dy.xy) * tri_w.z; }
	if (tri_w.y > 0.002) { r += textureGrad(s, tri_p.xz, dx.xz, dy.xz) * tri_w.y; }
	if (tri_w.x > 0.002) { r += textureGrad(s, tri_p.zy * vec2(-1.0, 1.0), dx.zy * vec2(-1.0, 1.0), dy.zy * vec2(-1.0, 1.0)) * tri_w.x; }
	return r / max(tri_w.x * step(0.002, tri_w.x) + tri_w.y * step(0.002, tri_w.y) + tri_w.z * step(0.002, tri_w.z), 0.0001);
}

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void fragment() {
	vec3 alb = tri(tex_albedo).rgb * tint.rgb;
	if (vcol) {
		alb *= COLOR.rgb;
	}
	float rough = tri(tex_rough).r;
	vec3 nm = tri(tex_normal).rgb;
	float up = clamp(w_nrm.y, 0.0, 1.0);
	// large blotches + detail, used by both puddles and snow drifts
	float n = vnoise(w_pos.xz * 0.11) * 0.65 + vnoise(w_pos.xz * 0.53) * 0.35;
	// texture cavities (dark, rough spots) hold water first
	float cavity = 1.0 - clamp(dot(alb, vec3(0.333)) * 2.2, 0.0, 1.0);

	if (wetness > 0.001) {
		// walls get streaks running down, floors are wet all over
		float streak = vnoise(vec2(w_pos.x * 3.0 + w_pos.z * 3.0, w_pos.y * 0.25)) * (1.0 - up);
		float wet = wetness * clamp(0.45 + 0.55 * up + streak * 0.35, 0.0, 1.0);
		alb *= mix(1.0, 0.74, wet * porosity);
		rough = mix(rough, 0.22, wet * 0.75);
		// puddles: only on (nearly) flat ground, low spots of the noise field
		float level = smoothstep(0.96, 0.995, up) * (w_pos.y < 0.3 ? 1.0 : 0.25);
		float pud = smoothstep(0.6, 0.66, n + cavity * 0.18) * level * smoothstep(0.25, 0.7, wetness);
		alb = mix(alb, alb * 0.45 + vec3(0.01), pud * 0.8);
		rough = mix(rough, 0.03, pud);
		nm = mix(nm, vec3(0.5, 0.5, 1.0), pud * 0.92);
	}
	if (snow_cover > 0.001) {
		float s = snow_cover * smoothstep(0.45, 0.8, up + (n - 0.5) * 0.45);
		s = clamp(s * 1.3, 0.0, 1.0);
		alb = mix(alb, vec3(0.86, 0.89, 0.94), s);
		rough = mix(rough, 0.62, s);
		nm = mix(nm, vec3(0.5, 0.5, 1.0), s * 0.75);
	}
	ALBEDO = alb;
	ROUGHNESS = rough;
	METALLIC = metal;
	NORMAL_MAP = nm;
	NORMAL_MAP_DEPTH = 1.0;
}

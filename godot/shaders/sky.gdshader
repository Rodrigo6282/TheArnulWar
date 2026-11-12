// Sky: horizon-to-zenith gradient, fbm clouds and a sharp HDR sun disk (feeds the glow pass).
// The expensive cloud noise runs in the quarter-resolution pass; the full-resolution pass only
// upsamples it and adds the sun disk, which keeps it cheap on integrated GPUs.
// No TIME use on purpose, so the reflection/ambient cubemap is not re-rendered every frame.
shader_type sky;
render_mode use_quarter_res_pass;

uniform vec3 zenith : source_color = vec3(0.2, 0.38, 0.66);
uniform vec3 horizon : source_color = vec3(0.68, 0.75, 0.82);
uniform vec3 ground : source_color = vec3(0.36, 0.34, 0.31);
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.5;
uniform vec2 cloud_offset = vec2(0.0, 0.0);
uniform float cloud_light = 1.0;
uniform float stars = 0.0;
uniform float sun_sharp = 1400.0;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}
float noise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0, a = 0.5;
	mat2 rot = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	for (int i = 0; i < 5; i++) { v += a * noise(p); p = rot * p * 2.03 + 1.7; a *= 0.5; }
	return v;
}

vec3 base_sky(vec3 d, vec3 sun_col, float s) {
	float h = d.y;
	vec3 col = mix(horizon, zenith, pow(clamp(h, 0.0, 1.0), 0.55));
	if (h < 0.0) {
		col = mix(horizon, ground, clamp(-h * 4.0, 0.0, 1.0));
	}
	col += sun_col * pow(s, 8.0) * 0.35;
	if (h > 0.02) {
		vec2 uv = d.xz / (h + 0.15) * 1.6 + cloud_offset;
		float c = smoothstep(0.72 - cloud_cover * 0.38, 0.95 - cloud_cover * 0.2, fbm(uv));
		vec3 bright = mix(vec3(0.98), sun_col, 0.2) * cloud_light;
		vec3 shade = mix(horizon, vec3(0.5, 0.53, 0.58) * cloud_light, 0.5);
		vec3 cc = mix(bright, shade, smoothstep(0.55, 1.0, fbm(uv * 1.7 + 3.0)));
		cc += sun_col * pow(s, 6.0) * 0.4;
		col = mix(col, cc, c * smoothstep(0.02, 0.25, h) * 0.92);
	}
	return col;
}

void sky() {
	vec3 d = EYEDIR;
	vec3 sun_col = vec3(1.0, 0.95, 0.85);
	float s = 0.0;
	if (LIGHT0_ENABLED) {
		sun_col = LIGHT0_COLOR;
		s = max(dot(d, LIGHT0_DIRECTION), 0.0);
	}
	if (AT_CUBEMAP_PASS || AT_QUARTER_RES_PASS) {
		COLOR = base_sky(d, sun_col, s);
	} else {
		vec3 c = QUARTER_RES_COLOR.rgb;
		if (stars > 0.0 && d.y > 0.02) {
			vec3 q = floor(d * 420.0);
			float h = hash(q.xy + q.z * 17.13);
			float lum = dot(c, vec3(0.3, 0.6, 0.1));
			c += vec3(0.9, 0.95, 1.0) * step(0.9972, h) * stars * (1.0 - smoothstep(0.03, 0.12, lum)) * smoothstep(0.02, 0.3, d.y) * 1.8;
		}
		COLOR = c + sun_col * pow(s, sun_sharp) * 9.0;
	}
}

// Final image pass: contrast-adaptive sharpening (restores the crispness FXAA/upscaling soften),
// per-map cinematic colour grading (split toning + soft S-curve), fine film grain and a soft lens
// vignette. Runs under the HUD (lower canvas layer), so text is not affected.
// Grading values come from each map's env "grade" entry (main.apply_env).
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float sharpen = 0.5;
uniform float vignette = 0.16;
// colour grading
uniform vec3 shadow_tint = vec3(1.0);    // multiplies the dark tones
uniform vec3 high_tint = vec3(1.0);      // multiplies the bright tones
uniform float grade_amount = 0.0;        // 0 = off, 1 = full
uniform float curve = 0.0;               // soft S-curve strength (filmic contrast)
uniform float grain = 0.0;               // film grain amount
uniform float lift = 0.0;                // raises the darkest tones (readable night shadows)

float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = SCREEN_PIXEL_SIZE;
	vec3 c = texture(screen_tex, uv).rgb;
	vec3 n = texture(screen_tex, uv + vec2(0.0, -px.y)).rgb;
	vec3 s = texture(screen_tex, uv + vec2(0.0, px.y)).rgb;
	vec3 e = texture(screen_tex, uv + vec2(px.x, 0.0)).rgb;
	vec3 w = texture(screen_tex, uv + vec2(-px.x, 0.0)).rgb;
	// adaptive amount: less sharpening where local contrast is already high (no halos)
	vec3 mn = min(c, min(min(n, s), min(e, w)));
	vec3 mx = max(c, max(max(n, s), max(e, w)));
	vec3 amp = sqrt(clamp(min(mn, 1.0 - mx) / max(mx, vec3(0.0001)), 0.0, 1.0));
	vec3 wgt = -amp * (sharpen * 0.2);
	vec3 col = max((c + (n + s + e + w) * wgt) / (1.0 + 4.0 * wgt), vec3(0.0));

	// split toning: tint shadows and highlights separately, keeping the overall brightness
	float l = clamp(luma(col), 0.0, 1.0);
	vec3 tone = mix(shadow_tint, high_tint, smoothstep(0.05, 0.75, l));
	vec3 graded = col * tone;
	graded *= l / max(luma(graded), 0.0001) * 0.35 + 0.65;
	col = mix(col, graded, grade_amount);
	// soft S-curve around mid grey (deeper blacks, gentle highlight roll-off)
	vec3 cc = clamp(col, 0.0, 1.0);
	vec3 sc = cc * cc * (3.0 - 2.0 * cc);
	col = mix(col, sc, curve);
	// lift: brighten the shadows without washing out the highlights
	col += lift * (1.0 - clamp(col, 0.0, 1.0)) * (1.0 - smoothstep(0.0, 0.35, luma(col)));

	// film grain: stronger in the mid/dark tones, like real film
	float t = fract(TIME * 7.0);
	float gn = fract(sin(dot(uv * vec2(1920.0, 1080.0) + t * 91.7, vec2(12.9898, 78.233))) * 43758.5453) - 0.5;
	col += gn * grain * (1.0 - l * 0.7);

	vec2 d = uv - 0.5;
	col *= 1.0 - vignette * smoothstep(0.15, 0.75, dot(d, d) * 2.2);
	COLOR = vec4(max(col, vec3(0.0)), 1.0);
}

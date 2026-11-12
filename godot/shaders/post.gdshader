// Final image pass: contrast-adaptive sharpening (restores the crispness FXAA/upscaling soften)
// and a soft lens vignette. Runs under the HUD (lower canvas layer), so text is not affected.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear;
uniform float sharpen = 0.5;
uniform float vignette = 0.16;

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
	vec3 col = (c + (n + s + e + w) * wgt) / (1.0 + 4.0 * wgt);
	vec2 d = uv - 0.5;
	col *= 1.0 - vignette * smoothstep(0.15, 0.75, dot(d, d) * 2.2);
	COLOR = vec4(max(col, vec3(0.0)), 1.0);
}

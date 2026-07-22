shader_type canvas_item;
// PS1/VHS-ish post shader applied to the low-res SubViewport texture:
// chromatic aberration -> Bayer dither + quantization -> sickly grade,
// scanlines, animated grain, vignette.

uniform float color_levels : hint_range(4.0, 64.0) = 12.0;
uniform float dither_strength : hint_range(0.0, 2.0) = 1.0;
uniform float pixel_scale = 4.0;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.5;
uniform float aberration : hint_range(0.0, 4.0) = 1.4;
uniform float grain_strength : hint_range(0.0, 0.2) = 0.05;
uniform float scanline_strength : hint_range(0.0, 0.5) = 0.12;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;

const float bayer[16] = {
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0
};

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 from_center = SCREEN_UV - vec2(0.5);

	vec2 ab = from_center * aberration * SCREEN_PIXEL_SIZE * 2.0;

	vec4 c;
	c.r = texture(screen_texture, SCREEN_UV + ab).r;
	c.g = texture(screen_texture, SCREEN_UV).g;
	c.b = texture(screen_texture, SCREEN_UV - ab).b;
	c.a = 1.0;

	// Ordered dither + color quantization (the PS1 look).
	ivec2 pix = ivec2(FRAGCOORD.xy / pixel_scale);
	int idx = (pix.x % 4) + (pix.y % 4) * 4;
	float d = (bayer[idx] / 16.0 - 0.5) * dither_strength / color_levels;
	c.rgb = floor((c.rgb + d) * color_levels + 0.5) / color_levels;

	// Sickly fluorescent grade: lift greens, crush blue in shadows.
	float luma = dot(c.rgb, vec3(0.299, 0.587, 0.114));
	c.rgb = mix(c.rgb, c.rgb * vec3(0.92, 1.06, 0.9), 0.5);
	c.rgb += vec3(0.0, 0.012, 0.004) * (1.0 - luma);

	// Scanlines on the low-res grid.
	if (pix.y % 2 == 0) {
		c.rgb *= 1.0 - scanline_strength;
	}

	// Animated film grain (kept coarse to match the pixel grid).
	float g = hash(vec2(pix) + fract(TIME * 7.31) * 100.0) - 0.5;
	c.rgb += g * grain_strength * (1.2 - luma);

	// Vignette.
	float vig = length(from_center) * 1.5;
	c.rgb *= 1.0 - vignette_strength * smoothstep(0.4, 1.15, vig);

	COLOR = c;
}

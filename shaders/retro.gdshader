shader_type canvas_item;
// PS1/VHS-ish post shader applied to the low-res SubViewport texture:
// ordered Bayer dithering + color quantization + vignette.

uniform float color_levels : hint_range(4.0, 64.0) = 14.0;
uniform float dither_strength : hint_range(0.0, 2.0) = 0.9;
uniform float pixel_scale = 4.0;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.45;

const float bayer[16] = {
	0.0, 8.0, 2.0, 10.0,
	12.0, 4.0, 14.0, 6.0,
	3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0
};

void fragment() {
	vec4 c = texture(TEXTURE, UV);

	ivec2 pix = ivec2(FRAGCOORD.xy / pixel_scale);
	int idx = (pix.x % 4) + (pix.y % 4) * 4;
	float d = (bayer[idx] / 16.0 - 0.5) * dither_strength / color_levels;

	c.rgb = floor((c.rgb + d) * color_levels + 0.5) / color_levels;

	float vig = length(UV - vec2(0.5)) * 1.5;
	c.rgb *= 1.0 - vignette_strength * smoothstep(0.45, 1.1, vig);

	COLOR = c;
}

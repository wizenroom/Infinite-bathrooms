shader_type spatial;
render_mode cull_back, diffuse_burley, specular_disabled;

uniform sampler2D albedo_texture : source_color, hint_default_white;
uniform float roughness_value : hint_range(0.0, 1.0) = 1.0;

varying vec4 vcol;

void vertex() {
	vcol = COLOR;
}

void fragment() {
	ALBEDO = texture(albedo_texture, UV).rgb * vcol.rgb;
	ROUGHNESS = roughness_value;
}
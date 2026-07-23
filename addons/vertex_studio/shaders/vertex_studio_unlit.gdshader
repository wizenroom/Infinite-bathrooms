shader_type spatial;
render_mode cull_back, diffuse_burley, specular_disabled, shadows_disabled, unshaded;

// vertex_studio_paint: identity marker; (do not change, used by vertex_studio_plugin.gd)

// View toggles driven by the addon
uniform bool use_vertex_color = true;
uniform bool use_texture = true;
uniform bool has_texture = false;

// Debug channel isolation: 0 = off, 1 = R, 2 = G, 3 = B, 4 = A
uniform int debug_channel = 0;

uniform sampler2D albedo_texture : source_color, hint_default_white;
uniform float roughness_value : hint_range(0.0, 1.0) = 1.0;

varying vec4 vcol;

void vertex() {
	vcol = COLOR;
}

void fragment() {
	if (debug_channel > 0) {
		// Show a single channel as unlit grayscale
		float v = vcol.r;
		if (debug_channel == 2) { v = vcol.g; }
		else if (debug_channel == 3) { v = vcol.b; }
		else if (debug_channel == 4) { v = vcol.a; }
		ALBEDO = vec3(v);
		EMISSION = vec3(0.0);
		ROUGHNESS = 1.0;
	} else {
		vec3 base = vec3(1.0);
		bool textured = use_texture && has_texture;

		if (textured) {
			base = texture(albedo_texture, UV).rgb;
		}

		vec3 col = base;
		if (use_vertex_color) {
			col = textured ? base * vcol.rgb : vcol.rgb;
		}

		ALBEDO = col;
		ROUGHNESS = roughness_value;
	}
}

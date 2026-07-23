shader_type spatial;
render_mode cull_back, diffuse_burley, specular_disabled;

// Blends the mesh from one snapshot ("from", stored in the base VERTEX/NORMAL/
// COLOR channels) toward a second snapshot ("to", baked into custom vertex
// attributes) entirely on the GPU. The whole tween is a single uniform, so the
// per-frame CPU cost is one set_shader_parameter() call regardless of poly count.
//
//   CUSTOM0 = target color   (rgba)
//   CUSTOM1 = target position (xyz, local space; w unused)
//   CUSTOM2 = target normal   (xyz, local space; w unused)

uniform float blend : hint_range(0.0, 1.0) = 0.0;

// Match the runtime look (StandardMaterial3D with vertex_color_use_as_albedo).
uniform bool use_vertex_color = true;
uniform bool has_texture = false;
uniform sampler2D albedo_texture : source_color, hint_default_white;
uniform float roughness_value : hint_range(0.0, 1.0) = 1.0;

varying vec4 vcol;

void vertex() {
	vcol = mix(COLOR, CUSTOM0, blend);
	VERTEX = mix(VERTEX, CUSTOM1.xyz, blend);
	NORMAL = normalize(mix(NORMAL, CUSTOM2.xyz, blend));
}

void fragment() {
	vec3 base = vec3(1.0);
	if (has_texture) {
		base = texture(albedo_texture, UV).rgb;
	}
	vec3 col = base;
	if (use_vertex_color) {
		col = has_texture ? base * vcol.rgb : vcol.rgb;
	}
	ALBEDO = col;
	ROUGHNESS = roughness_value;
}

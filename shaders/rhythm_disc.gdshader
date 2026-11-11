shader_type canvas_item;
render_mode unshaded;

uniform bool catcher = false;
uniform float inner_ratio = 0.826923;

float ring(float radius, float center, float width, float aa) {
	return 1.0 - smoothstep(width, width + aa, abs(radius - center));
}

void fragment() {
	vec2 p = (UV * 2.0 - 1.0) * 1.15;
	float radius = length(p);
	// Derivatives keep the edge feather and ring strokes smooth in actual screen
	// pixels, including the shallow ellipse and smaller perspective notes.
	float pixel = max(fwidth(radius), 0.0001);
	float aa = pixel * 0.85;
	vec3 tint = COLOR.rgb;
	if (catcher) {
		float press = clamp((COLOR.a - 0.25) / 0.75, 0.0, 1.0);
		float outer = ring(radius, 1.0, pixel * 0.65, aa);
		float inner = ring(radius, inner_ratio, pixel * 0.4, aa);
		float glow = exp(-abs(radius - 1.0) / (pixel * 3.5)) * 0.06;
		float pool = exp(-radius * radius * 3.8) * press * 0.34;
		float halo = exp(-abs(radius - inner_ratio) / 0.14) * press * 0.15;
		vec3 light = mix(tint, vec3(0.9, 0.85, 1.0), press * 0.45);
		float edge_fade = 1.0 - smoothstep(1.02, 1.14, radius);
		float alpha = max(outer * (0.45 + press * 0.35), inner * (0.58 + press * 0.28)) + glow + pool + halo;
		COLOR = vec4(light, min(1.0, alpha) * edge_fade);
	} else {
		float fill = 1.0 - smoothstep(1.0 - aa, 1.0 + aa, radius);
		float bevel = smoothstep(0.78, 1.0, radius);
		vec3 surface = tint * (1.02 - bevel * 0.32);
		surface += tint * max(0.0, -p.y) * 0.07;
		float rim = ring(radius, 0.96, pixel * 0.5, aa);
		float inner = ring(radius, inner_ratio, pixel * 0.3, aa);
		surface = mix(surface, mix(tint, vec3(1.0), 0.2), rim * 0.7);
		surface += tint * inner * 0.08;
		float glow = exp(-max(0.0, radius - 1.0) * 32.0) * 0.09 * (1.0 - fill);
		COLOR = vec4(surface, fill * 0.98 + glow);
	}
}

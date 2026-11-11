shader_type canvas_item;
render_mode unshaded, blend_add;

uniform float age = 0.0;
uniform float strength = 0.0;
uniform float seed = 0.0;
uniform vec4 tint : source_color = vec4(0.78, 0.70, 1.0, 1.0);

void fragment() {
	// Road-plane spiral, flattened to match the catcher rather than a screen-space circle.
	vec2 p = (UV - vec2(0.5, 0.64)) * vec2(2.9, 1.65);
	vec2 ground = vec2(p.x, p.y / 0.33);
	float radius = length(ground);
	float angle = atan(ground.y, ground.x);
	float pixel = max(fwidth(radius), 0.003);
	vec3 pearl = vec3(1.0, 0.96, 1.0);
	vec3 lavender = mix(tint.rgb, vec3(0.78, 0.70, 1.0), 0.45);
	vec3 ice = mix(lavender, vec3(0.66, 0.85, 1.0), 0.30);
	float spin = age * 26.0 + seed;
	float winding = angle * 2.0 + radius * 11.0 - spin;
	float spiral_delta = sin(winding * 0.5);
	float spiral = exp(-spiral_delta * spiral_delta * 100.0);
	float spiral_halo = exp(-spiral_delta * spiral_delta * 12.0);
	float annulus = smoothstep(0.28, 0.48, radius) * (1.0 - smoothstep(0.98, 1.16, radius));
	vec3 light = (mix(lavender, pearl, 0.65) * spiral * 0.70 + ice * spiral_halo * 0.12) * annulus;
	float edge_delta = (radius - 1.0) / max(pixel * 1.1, 0.018);
	float edge = exp(-edge_delta * edge_delta);
	light += lavender * edge * (0.18 + 0.16 * sin(angle * 3.0 - spin));
	// Two rotating arcs lift off the floor and tighten into a short vortex funnel.
	for (int i = 0; i < 2; i++) {
		float phase = fract(age * 4.4 + float(i) * 0.5);
		float ring_radius = mix(0.95, 0.57, phase);
		float rise = phase * 0.53;
		vec2 orbit = vec2(p.x / ring_radius, (p.y + rise) / (0.27 * ring_radius));
		float orbit_radius = length(orbit);
		float orbit_angle = atan(orbit.y, orbit.x);
		float aa = max(fwidth(orbit_radius), 0.012);
		float distance_to_ring = (orbit_radius - 1.0) / (aa * 1.2);
		float ribbon = exp(-distance_to_ring * distance_to_ring);
		float halo = exp(-distance_to_ring * distance_to_ring * 0.10);
		float arc = smoothstep(-0.65, 0.65, sin(orbit_angle - spin - float(i) * 2.2));
		float fade = smoothstep(0.0, 0.12, phase) * (1.0 - smoothstep(0.65, 1.0, phase));
		light += (mix(ice, pearl, 0.65) * ribbon * 0.80 + lavender * halo * 0.10) * arc * fade;
	}
	float pool = exp(-radius * radius * 5.0);
	light += mix(lavender, pearl, 0.35) * pool * 0.20;
	float bounds = smoothstep(0.0, 0.06, UV.x) * (1.0 - smoothstep(0.94, 1.0, UV.x));
	bounds *= smoothstep(0.0, 0.06, UV.y) * (1.0 - smoothstep(0.94, 1.0, UV.y));
	COLOR = vec4(light * strength * bounds, 1.0);
}

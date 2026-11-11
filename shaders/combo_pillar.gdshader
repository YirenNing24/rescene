shader_type canvas_item;
render_mode unshaded, blend_add;

uniform float age = 1.0;
uniform float seed = 0.0;
uniform float lifetime = 0.52;

float hash(float value) {
	return fract(sin(value * 127.1 + seed * 31.7) * 43758.5453);
}

void fragment() {
	// The beam grows out of the same road-plane ellipse as the note catcher.
	// UV fades remove every edge of the quad; no hard rectangular light block.
	float base = 0.86;
	float x = UV.x * 2.0 - 1.0;
	float height = (base - UV.y) / base;
	float attack = smoothstep(0.0, 0.035, age);
	float fade = 1.0 - smoothstep(0.10, lifetime, age);
	float rise = mix(0.16, 1.0, smoothstep(0.0, 0.10, age));
	float vertical = smoothstep(-0.008, 0.025, height);
	vertical *= 1.0 - smoothstep(rise * 0.66, rise, height);
	float taper = mix(0.55, 0.35, clamp(height, 0.0, 1.0));
	float spread = x / taper;
	float haze = exp(-spread * spread * 3.2) * 0.20;
	float shaft = exp(-spread * spread * 16.0) * 0.34;
	float core = exp(-spread * spread * 110.0) * 0.43;
	vec3 lavender = vec3(0.78, 0.70, 1.0);
	vec3 ice = vec3(0.65, 0.84, 0.96);
	vec3 pearl = vec3(1.0, 0.96, 1.0);
	vec3 tint = mix(lavender, ice, clamp(height * 0.85, 0.0, 1.0));
	vec3 light = (tint * (haze + shaft) + pearl * core) * vertical;
	// Spread distinct streams across both sides instead of burying them in the core.
	// Each has a bright thin spine, soft halo and its own rising, tapered tip.
	float above_ground = smoothstep(-0.008, 0.016, height);
	for (int i = 0; i < 14; i++) {
		float f = float(i);
		float side = mod(f, 2.0) * 2.0 - 1.0;
		float band = floor(f * 0.5);
		float offset = side * (0.10 + band * 0.078 + hash(f + 1.0) * 0.018);
		offset *= 1.0 - clamp(height, 0.0, 1.0) * 0.08;
		float width = max(0.008 + hash(f + 12.0) * 0.005, fwidth(x) * 0.7);
		float line_delta = (x - offset) / width;
		float spine = exp(-line_delta * line_delta);
		float halo = exp(-line_delta * line_delta * 0.10);
		float tip = (0.30 + hash(f + 30.0) * 0.64) * rise;
		float stream = above_ground * (1.0 - smoothstep(tip * 0.72, tip, height));
		float surge = 0.78 + 0.22 * sin(height * 24.0 - age * 40.0 + f * 2.3);
		vec3 stream_tint = mix(lavender, ice, hash(f + 50.0) * 0.6);
		light += (mix(stream_tint, pearl, 0.65) * spine * 0.80 + stream_tint * halo * 0.12) * stream * surge;
	}
	// A broad ellipse anchors the narrow vertical column to the road surface.
	vec2 ground = vec2(x / 0.65, (UV.y - base) / 0.047);
	float radius = length(ground);
	float pool = exp(-radius * radius * 3.2) * 0.62;
	float ring_radius = 0.72 + age * 0.75;
	float ring_delta = (radius - ring_radius) / 0.055;
	float ring = exp(-ring_delta * ring_delta) * 0.24;
	light += mix(lavender, pearl, 0.4) * (pool + ring);
	// Eight deterministic rising glints; fixed work, no particle nodes or trails.
	for (int i = 0; i < 8; i++) {
		float f = float(i);
		float travel = age * (0.85 + hash(f + 20.0) * 1.1);
		float sparkle_y = base - travel - hash(f + 40.0) * 0.16;
		float sparkle_x = (hash(f + 60.0) - 0.5) * 0.75;
		vec2 delta = vec2((x - sparkle_x) * 0.5, (UV.y - sparkle_y) * 1.8);
		float dot_glow = exp(-dot(delta, delta) * 19000.0);
		float star = exp(-abs(delta.x) * 650.0 - abs(delta.y) * 100.0);
		float twinkle = 0.5 + 0.5 * sin(age * 34.0 + f * 4.0);
		light += pearl * (dot_glow + star) * twinkle * 0.45;
	}
	float edge = smoothstep(0.0, 0.04, UV.y) * (1.0 - smoothstep(0.94, 1.0, abs(x)));
	light *= attack * fade * edge;
	// Mobile gameplay is composited through a transparent SubViewport. A solid
	// alpha would make the entire sprite quad obscure the lobby behind it.
	float coverage = clamp(max(light.r, max(light.g, light.b)), 0.0, 1.0);
	if (coverage < 0.0001) {
		discard;
	}
	// blend_add multiplies RGB by alpha; normalize to retain the beam's energy.
	COLOR = vec4(light / coverage, coverage);
}

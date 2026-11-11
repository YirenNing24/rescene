shader_type canvas_item;
render_mode unshaded;

void fragment() {
	float top = (1.0 - smoothstep(0.0, 0.30, UV.y)) * 0.68;
	float bottom = smoothstep(0.65, 1.0, UV.y) * 0.83;
	float left = (1.0 - smoothstep(0.0, 0.34, UV.x)) * 0.24;
	float right = smoothstep(0.80, 1.0, UV.x) * 0.20;
	COLOR = vec4(vec3(0.035, 0.045, 0.095), min(0.92, top + bottom + left + right));
}

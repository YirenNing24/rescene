shader_type canvas_item;
uniform vec2 dimensions = vec2(100.0);
uniform float corner = 18.0;
varying vec2 local_position;
void vertex() { local_position = VERTEX; }
void fragment() {
	vec4 photo = texture(TEXTURE, UV);
	vec2 half_size = dimensions * 0.5;
	float r = min(corner, min(half_size.x, half_size.y));
	vec2 q = abs(local_position - half_size) - half_size + vec2(r);
	float distance = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
	float feather = max(fwidth(distance), 0.65);
	COLOR = photo * vec4(1.0, 1.0, 1.0, 1.0 - smoothstep(-feather, feather, distance));
}

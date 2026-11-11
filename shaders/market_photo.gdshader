shader_type canvas_item;
render_mode unshaded;

void fragment() {
	vec2 p = abs(UV - 0.5) - vec2(0.465, 0.475);
	float distance_to_edge = length(max(p, 0.0)) + min(max(p.x, p.y), 0.0) - 0.025;
	float alpha = 1.0 - smoothstep(-fwidth(distance_to_edge), fwidth(distance_to_edge), distance_to_edge);
	vec4 photo = texture(TEXTURE, UV);
	COLOR = vec4(photo.rgb, photo.a * alpha);
}

shader_type canvas_item;
render_mode unshaded;

void fragment() {
	vec4 photo = texture(TEXTURE, UV);
	float shade = smoothstep(0.49, 1.0, UV.y) * 0.87;
	photo.rgb = mix(photo.rgb, vec3(0.065, 0.06, 0.12), shade);
	photo.rgb = mix(photo.rgb, vec3(0.75, 0.68, 0.94), 0.045);
	COLOR = photo;
}

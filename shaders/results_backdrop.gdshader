shader_type canvas_item;
render_mode unshaded;

uniform vec4 accent : source_color = vec4(0.76, 0.69, 0.96, 1.0);

void fragment() {
	vec3 photo = texture(TEXTURE, UV).rgb;
	vec3 ink = vec3(0.035, 0.041, 0.078);
	float reveal = 0.10 + smoothstep(0.1, 1.0, UV.x) * 0.12;
	vec3 color = mix(ink, photo, reveal);
	float haze = exp(-dot((UV - vec2(0.89, 0.24)) * vec2(2.6, 3.1), (UV - vec2(0.89, 0.24)) * vec2(2.6, 3.1)));
	color += accent.rgb * haze * 0.065;
	float vignette = smoothstep(0.35, 0.85, length((UV - 0.5) * vec2(0.8, 1.0)));
	color *= 1.0 - vignette * 0.4;
	COLOR = vec4(color, 1.0);
}

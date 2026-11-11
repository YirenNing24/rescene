shader_type canvas_item;
render_mode unshaded;

// Soft matching fill beyond the 16:9 artwork on wider phones or tablets.
// The foreground always contains the complete, undistorted source image.
void fragment() {
	float glow = exp(-length((UV - vec2(0.5, 0.55)) * vec2(1.2, 0.8)) * 2.0);
	vec3 midnight = vec3(0.045, 0.055, 0.095);
	vec3 lavender = vec3(0.23, 0.25, 0.34);
	COLOR = vec4(mix(midnight, lavender, glow), 1.0);
}

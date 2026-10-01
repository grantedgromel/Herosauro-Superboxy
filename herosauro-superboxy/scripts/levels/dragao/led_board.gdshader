// Pitch-side LED boards with no advertiser: club-blue chevrons, dots and a wave
// scrolling along the perimeter. UV.x is metres along the board run, UV.y is
// 0..1 up the screen.
shader_type spatial;
render_mode unshaded, cull_back;

uniform float speed = 1.6;
uniform float brightness = 0.95;

void fragment() {
	float x = UV.x - TIME * speed;
	float panel = floor(x / 7.0);
	float px = fract(x / 7.0) * 7.0;
	float kind = mod(panel, 3.0);
	vec3 blue = vec3(0.04, 0.22, 0.85);
	vec3 white = vec3(0.92, 0.95, 1.0);
	vec3 cyan = vec3(0.25, 0.78, 1.0);
	vec3 c;
	if (kind < 0.5) {
		float ch = fract((px + abs(UV.y - 0.5) * 1.4) * 0.7);
		c = mix(blue, white, step(0.62, ch));
	} else if (kind < 1.5) {
		vec2 q = vec2(fract(px * 0.55), UV.y);
		float d = length((q - vec2(0.5)) * vec2(1.0, 0.8));
		c = mix(blue * 0.8, white, step(d, 0.3));
	} else {
		float w = sin(px * 1.6 + TIME * 2.4) * 0.2 + 0.5;
		c = mix(blue * 0.65, cyan, step(UV.y, w));
	}
	vec2 g = fract(vec2(UV.x * 12.0, UV.y * 9.0));
	float led = 0.78 + 0.22 * step(0.18, g.x) * step(0.18, g.y);
	ALBEDO = c * led * brightness;
}

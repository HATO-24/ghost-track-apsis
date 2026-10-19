shader_type canvas_item;

// 玻璃与 CRT 的"脏"层。
// 关键原则：UI 本身保持锐利，不可靠感来自数据，不来自滤镜。
// 所以这里只做很轻的扫描线、颗粒、暗角和玻璃反光。

uniform float scan_strength : hint_range(0.0, 0.2) = 0.028;
uniform float grain_strength : hint_range(0.0, 0.1) = 0.016;
uniform float vignette_strength : hint_range(0.0, 1.0) = 0.22;
uniform float aberration : hint_range(0.0, 0.01) = 0.0006;
uniform float flicker_strength : hint_range(0.0, 0.05) = 0.005;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 d = uv - 0.5;

	vec3 col;
	col.r = texture(screen_texture, uv + d * aberration).r;
	col.g = texture(screen_texture, uv).g;
	col.b = texture(screen_texture, uv - d * aberration).b;

	// 扫描线：1080 高度上每 3 px 一条
	float scan = 0.5 + 0.5 * sin(uv.y * 1080.0 * 2.0943951);
	col *= 1.0 - scan_strength * scan;

	// 颗粒
	float g = hash12(FRAGCOORD.xy + vec2(floor(TIME * 24.0), 0.0));
	col += (g - 0.5) * grain_strength;

	// 暗角
	vec2 v = UV * 2.0 - 1.0;
	float vig = smoothstep(1.35, 0.30, length(v * vec2(0.86, 1.0)));
	col *= mix(1.0, vig, vignette_strength);
	col *= 1.16;

	// 玻璃斜向反光
	float band = exp(-pow((UV.x + UV.y - 0.55) * 3.5, 2.0)) * 0.016;
	col += vec3(band * 0.8, band, band * 0.9);

	// 极轻的刷新抖动
	col *= 1.0 + sin(TIME * 41.0) * flicker_strength;

	COLOR = vec4(col, 1.0);
}

shader_type spatial;
// Cinder Peak heat haze: a Y-billboarded quad that wobbles what is behind it, strongest at
// its base (the hot surface) and fading out toward its top and sides. Visual only.

render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix, fog_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float strength = 0.006;
uniform float speed = 1.0;
uniform vec4 tint : source_color = vec4(1.0, 0.35, 0.1, 0.06);

void vertex() {
	vec3 up = MODEL_MATRIX[1].xyz;
	vec3 side = normalize(cross(up, INV_VIEW_MATRIX[2].xyz)) * length(MODEL_MATRIX[0].xyz);
	vec3 fwd = normalize(cross(side, up));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(vec4(side, 0.0), vec4(up, 0.0), vec4(fwd, 0.0), MODEL_MATRIX[3]);
}

void fragment() {
	vec2 uv = UV;
	float rise = uv.y;
	float mask = smoothstep(0.0, 0.85, rise) * smoothstep(1.0, 0.8, rise) * smoothstep(0.0, 0.2, uv.x) * smoothstep(1.0, 0.8, uv.x);
	float t = TIME * speed;
	vec2 wob = vec2(
		sin(uv.y * 19.0 + t * 6.0 + sin(uv.x * 7.0 + t * 1.7) * 2.0),
		cos(uv.x * 23.0 - t * 4.5 + uv.y * 9.0));
	vec3 behind = textureLod(screen_tex, SCREEN_UV + wob * strength * mask, 0.0).rgb;
	ALBEDO = behind + tint.rgb * tint.a * mask;
	ALPHA = mask;
}

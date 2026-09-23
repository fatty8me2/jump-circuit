shader_type spatial;
// Heat shimmer over a hot surface (laser beams): refracts what is behind a vertical
// quad with rising, wobbling noise. The quad's bottom edge (UV.y = 1) is the heat source.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float strength = 0.0035;
uniform float speed = 1.0;
uniform vec4 tint : source_color = vec4(1.0, 0.3, 0.2, 0.1);
uniform float intensity = 1.0;

void fragment() {
	vec2 uv = UV;
	float rise = uv.y;                       // 1 at the beam, 0 at the top
	float mask = smoothstep(0.0, 0.8, rise) * smoothstep(1.0, 0.9, rise) * smoothstep(0.0, 0.12, uv.x) * smoothstep(1.0, 0.88, uv.x);
	float t = TIME * speed;
	vec2 wob = vec2(
		sin(uv.y * 23.0 + t * 7.0 + sin(uv.x * 9.0 + t * 2.0) * 2.0),
		cos(uv.x * 31.0 - t * 5.0 + uv.y * 11.0));
	vec2 offs = wob * strength * mask * intensity;
	vec3 behind = textureLod(screen_tex, SCREEN_UV + offs, 0.0).rgb;
	ALBEDO = behind + tint.rgb * tint.a * mask * intensity;
	ALPHA = mask * intensity;
}

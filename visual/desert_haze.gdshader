shader_type spatial;
// Scarab Sands: heat shimmer. A wide upright quad (turned to face the camera about Y) that
// refracts what is behind it with rising, wobbling noise - the air boiling over the hot sand.
// Soft on every edge; strongest low down, where the ground is hottest.
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, blend_mix, fog_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float strength = 0.004;
uniform float speed = 1.0;

void vertex() {
	// billboard about the vertical axis
	vec3 cam = (INV_VIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 origin = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 to_cam = cam - origin;
	to_cam.y = 0.0;
	vec3 fwd = normalize(to_cam + vec3(0.0001, 0.0, 0.0));
	vec3 right = normalize(cross(vec3(0.0, 1.0, 0.0), fwd));
	vec3 sx = MODEL_MATRIX[0].xyz;
	vec3 sy = MODEL_MATRIX[1].xyz;
	vec3 w = origin + right * VERTEX.x * length(sx) + vec3(0.0, 1.0, 0.0) * VERTEX.y * length(sy);
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(w, 1.0);
}

void fragment() {
	vec2 uv = UV;
	float mask = smoothstep(0.0, 0.25, uv.x) * smoothstep(1.0, 0.75, uv.x) * smoothstep(0.0, 0.5, uv.y) * smoothstep(1.0, 0.85, uv.y);
	float t = TIME * speed;
	vec2 wob = vec2(sin(uv.y * 40.0 + t * 6.0 + sin(uv.x * 13.0 + t * 1.7) * 2.0), cos(uv.x * 29.0 - t * 4.0 + uv.y * 17.0));
	vec2 offs = wob * strength * mask;
	ALBEDO = textureLod(screen_tex, SCREEN_UV + offs, 0.0).rgb;
	ALPHA = mask;
}

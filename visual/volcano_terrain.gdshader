shader_type spatial;
// Cinder Peak: the volcano's flank, a single big radial mesh centred on the crater (local
// XZ = offset from the crater centre, local Y = world height). Dark ash and basalt, lighter
// ash drifts on the gentle slopes, and glowing lava rivers radiating from the rim that race
// downhill (animated), braiding and fading out as they cool; fissure cracks glow in places;
// the inner crater wall burns brighter toward the lava lake. Fogged by hand (fog_disabled)
// so the glowing summit still reads from the bottom of the climb.

render_mode fog_disabled;

uniform float crater_r = 60.0;
uniform float rim_y = 120.0;
uniform float rivers = 22.0;
uniform float river_width = 0.018;
uniform float flow_speed = 4.0;
uniform vec3 rock : source_color = vec3(0.075, 0.06, 0.06);
uniform vec3 ash : source_color = vec3(0.2, 0.17, 0.16);
uniform vec3 hot_color : source_color = vec3(1.0, 0.45, 0.08);
uniform vec3 white_hot : source_color = vec3(1.0, 0.85, 0.45);
uniform vec3 haze_color : source_color = vec3(0.16, 0.05, 0.035);
uniform float haze_density = 0.0018;
uniform float heat = 1.0;

varying vec3 op;
varying vec3 wp;
varying vec3 wn;

void vertex() {
	op = VERTEX;
	wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash2(i).x;
	float b = hash2(i + vec2(1.0, 0.0)).x;
	float c = hash2(i + vec2(0.0, 1.0)).x;
	float d = hash2(i + vec2(1.0, 1.0)).x;
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float s = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		s += a * vnoise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return s;
}

void fragment() {
	float t = TIME;
	float r = length(op.xz);
	float ang = atan(op.z, op.x);
	float slope = 1.0 - clamp(wn.y, 0.0, 1.0);
	// ground: basalt on the steep parts, ash drifts on the flatter ones
	float n = fbm(op.xz * 0.02);
	float n2 = fbm(op.xz * 0.11 + 4.0);
	vec3 col = mix(ash, rock, smoothstep(0.12, 0.45, slope + (n - 0.5) * 0.4));
	col *= 0.75 + 0.5 * n2;
	vec3 emit = vec3(0.0);
	// lava rivers: meandering radial channels from the rim, each with its own length
	float wig = (fbm(vec2(r * 0.006, ang * 3.0)) - 0.5) * 0.9 + sin(r * 0.015 + ang * 5.0) * 0.08;
	float lane = ang / 6.28318 * rivers + wig;
	float idx = floor(lane);
	float h = hash2(vec2(idx, 3.7)).x;
	float d = abs(fract(lane) - 0.5) / rivers * 6.28318;
	float len = mix(180.0, 900.0, h * h) * step(0.3, h);
	float along = clamp((r - crater_r) / max(len, 1.0), 0.0, 1.0);
	float width = river_width * (0.6 + 0.8 * h) * (1.0 - 0.6 * along);
	float river = (1.0 - smoothstep(width * 0.35, width, d)) * step(crater_r * 0.9, r) * (1.0 - smoothstep(0.75, 1.0, along));
	float pulse = vnoise(vec2(r * 0.05 - t * flow_speed * 0.05, idx * 7.0));
	float streak = vnoise(vec2(r * 0.18 - t * flow_speed * 0.18, d * 900.0));
	vec3 melt = mix(hot_color, white_hot, clamp(pulse * 0.7 + streak * 0.4 - along * 0.5, 0.0, 1.0));
	float cool = 1.0 - along * 0.75;
	col = mix(col, melt * 0.3, river);
	emit += melt * river * (1.5 + 1.8 * pulse) * cool;
	// a dull ember halo around each river (heat lighting the ash)
	float halo = (1.0 - smoothstep(width, width * 5.0, d)) * step(crater_r * 0.9, r) * (1.0 - along) * step(0.3, h);
	emit += hot_color * halo * 0.12;
	// fissures: short glowing cracks scattered over the flank
	float cr = abs(vnoise(op.xz * 0.045) - 0.5);
	float crack = (1.0 - smoothstep(0.0, 0.012, cr)) * smoothstep(0.62, 0.72, fbm(op.xz * 0.008 + 11.0));
	emit += hot_color * crack * (1.2 + 0.6 * sin(t * 1.1 + n * 20.0));
	// the crater: the inner wall burns hotter toward the lava lake
	float inner = 1.0 - smoothstep(crater_r * 0.85, crater_r * 1.05, r);
	float deep = clamp((rim_y - op.y) / 40.0, 0.0, 1.0);
	emit += mix(hot_color, white_hot, deep) * inner * deep * (1.2 + 0.4 * sin(t * 2.0 + ang * 7.0));
	emit *= heat;
	// hand-made fog (the level fog is off for this mesh): dim toward the smoke colour
	float dist = length(wp - CAMERA_POSITION_WORLD);
	float fog = 1.0 - exp(-dist * haze_density);
	ALBEDO = mix(col, haze_color, fog);
	EMISSION = emit * (1.0 - fog * 0.6) + haze_color * fog * 0.35;
	ROUGHNESS = 0.95;
}

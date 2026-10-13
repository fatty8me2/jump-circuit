class_name FlowSurface
extends StaticBody3D
## A static surface that keeps and builds speed (flow slope, half-pipe, launch ramp). The Player
## finds it through the floor body's flow() query (Player._surface_move -> _flow_move):
##   * no over-speed bleed on it
##   * a downhill grade adds speed: gravity_fall * sin(pitch) * `gain`, never past `cap`
##   * steering turns the heading (`carve` m/s^2 of lateral acceleration at full stick)
## Nothing else changes: any other surface keeps the ordinary ground rules.
## Built by kit.flow_slope / kit.halfpipe / kit.launch_arc, which add the shape and mesh.

@export var gain: float = 0.55
@export var cap: float = 30.0
@export var carve: float = 30.0


func _init() -> void:
	collision_layer = 1
	collision_mask = 0
	add_to_group("flow_surface")


func flow() -> Dictionary:
	return {"gain": gain, "cap": cap, "carve": carve}


## Speed a rider entering at `v0` m/s has after `dist` metres straight down a grade of `pitch_deg`
## on this surface (the same rule the Player runs), for level designers and the bot.
func speed_after(v0: float, dist: float, pitch_deg: float) -> float:
	var t: MovementTuning = KitUtil.tuning()
	var a: float = t.gravity_fall * sin(deg_to_rad(pitch_deg)) * gain
	var v: float = v0
	var travelled: float = 0.0
	var dt: float = 1.0 / 60.0
	while travelled < dist:
		if v < cap:
			v = minf(v + a * dt, maxf(cap, v0))
		travelled += v * dt
	return v


## The glowing-chevron material flow surfaces share (the boost strip shader in the world's colours).
## `size` is the surface's bounding size, `scroll` how fast the chevrons run along -Z.
static func material(size: Vector3, scroll: float = 3.5) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = preload("res://visual/strip.gdshader")
	m.set_shader_parameter("half_size", size * 0.5)
	var col: Color = Look.c("accent2").lerp(Color(0.55, 1.0, 0.9), 0.3)
	m.set_shader_parameter("arrow_color", Color(col.r, col.g, col.b))
	m.set_shader_parameter("base_color", Look.c("alt_top").darkened(0.55))
	m.set_shader_parameter("scroll_speed", scroll)
	m.set_shader_parameter("glow", 1.0)
	return m

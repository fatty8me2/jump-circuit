class_name BlobShadow
extends RefCounted
## Soft round drop shadow projected straight down: the landing-spot readout.

static var _tex: GradientTexture2D


static func make() -> Decal:
	if _tex == null:
		var g := Gradient.new()
		g.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
		g.colors = PackedColorArray([Color(0, 0, 0, 0.75), Color(0, 0, 0, 0.55), Color(0, 0, 0, 0)])
		_tex = GradientTexture2D.new()
		_tex.gradient = g
		_tex.fill = GradientTexture2D.FILL_RADIAL
		_tex.fill_from = Vector2(0.5, 0.5)
		_tex.fill_to = Vector2(0.5, 0.0)
		_tex.width = 128
		_tex.height = 128
	var d := Decal.new()
	d.texture_albedo = _tex
	d.size = Vector3(1.25, 60.0, 1.25)
	d.position = Vector3(0, -29.4, 0)
	d.cull_mask = 1
	d.normal_fade = 0.35
	d.upper_fade = 0.0001
	d.lower_fade = 0.6
	return d

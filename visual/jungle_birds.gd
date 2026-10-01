extends Node3D
## Jungle Temple: a little flock (toucans) wheeling over the canopy. Each child bird circles the
## node at `radius` (a lazy, wobbling orbit at its own phase and height), banks into the turn and
## flaps its wings ("WingL" / "WingR"). Visual only.

@export var radius: float = 20.0
@export var speed: float = 7.0

var _t: float = 0.0


func _process(dt: float) -> void:
	_t += dt
	var w: float = speed / maxf(radius, 1.0)
	for c: Node in get_children():
		var b := c as Node3D
		if b == null:
			continue
		var ph: float = float(b.get_meta("phase", 0.0))
		var alt: float = float(b.get_meta("alt", 0.0))
		var a: float = _t * w + ph
		var r: float = radius * (1.0 + 0.18 * sin(a * 2.3 + ph))
		var pos := Vector3(cos(a) * r, alt + sin(a * 1.7 + ph) * 1.5, sin(a) * r)
		var tangent := Vector3(-sin(a), 0.0, cos(a))
		b.position = pos
		b.basis = Basis.looking_at(tangent, Vector3.UP) * Basis(Vector3.FORWARD, 0.35)
		var flap: float = sin(_t * 11.0 + ph * 3.0) * 0.6
		var wl := b.get_node_or_null("WingL") as Node3D
		var wr := b.get_node_or_null("WingR") as Node3D
		if wl != null:
			wl.rotation.z = flap
		if wr != null:
			wr.rotation.z = -flap

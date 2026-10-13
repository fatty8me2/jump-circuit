class_name FlowHud
extends Control
## The flow meter's HUD widget (bottom centre): tier name, the meter bar with tier ticks, the ring-chain
## counter and the speed readout in m/s. A ZEN banner fades in and out the first time ZEN is reached.
## FlowMeter feeds it every frame through show_state(); it never reads the meter itself.

const BAR_SIZE: Vector2 = Vector2(380, 12)
const TIER_COLORS: Array[Color] = [
	Color(0.55, 0.62, 0.75), Color(0.22, 0.84, 0.75), Color(0.35, 0.78, 1.0), Color(1.0, 0.79, 0.3), Color(1.0, 0.97, 0.88),
]

var _tier_label: Label
var _chain_label: Label
var _speed_label: Label
var _banner: Label
var _banner_sub: Label
var _banner_tw: Tween
var _chain_tw: Tween

var _value: float = 0.0
var _tier: int = 0
var _pulse: float = 0.0
var _shown_chain: int = 0
var _bg: StyleBoxFlat
var _fill: StyleBoxFlat
var _halo: StyleBoxFlat


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_bg = StyleBoxFlat.new()
	_bg.bg_color = Color(0.03, 0.05, 0.1, 0.45)
	_bg.set_corner_radius_all(6)
	_bg.border_color = Color(1, 1, 1, 0.22)
	_bg.set_border_width_all(1)
	_fill = StyleBoxFlat.new()
	_fill.set_corner_radius_all(6)
	_halo = StyleBoxFlat.new()
	_halo.bg_color = Color(0, 0, 0, 0)
	_halo.set_corner_radius_all(9)
	_halo.set_border_width_all(3)
	_tier_label = _make_label("", 20, HORIZONTAL_ALIGNMENT_LEFT)
	_tier_label.name = "Tier"
	_chain_label = _make_label("", 22, HORIZONTAL_ALIGNMENT_RIGHT)
	_chain_label.name = "Chain"
	_chain_label.modulate.a = 0.0
	_speed_label = _make_label("0 m/s", 24, HORIZONTAL_ALIGNMENT_CENTER)
	_speed_label.name = "Speed"
	_banner = _make_label("", 84, HORIZONTAL_ALIGNMENT_CENTER)
	_banner.name = "Banner"
	_banner.modulate.a = 0.0
	_banner_sub = _make_label("", 22, HORIZONTAL_ALIGNMENT_CENTER)
	_banner_sub.name = "BannerSub"
	_banner_sub.modulate.a = 0.0
	resized.connect(_layout)
	_layout()


func _make_label(text: String, size: int, align: HorizontalAlignment) -> Label:
	var l: Label = UiKit.shadowed(UiKit.label(text, size, Color.WHITE, align), 5)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _bar_rect() -> Rect2:
	return Rect2(Vector2((size.x - BAR_SIZE.x) * 0.5, size.y - 74.0), BAR_SIZE)


func _layout() -> void:
	var bar: Rect2 = _bar_rect()
	_tier_label.position = Vector2(bar.position.x, bar.position.y - 30.0)
	_tier_label.size = Vector2(BAR_SIZE.x * 0.5, 28.0)
	_chain_label.position = Vector2(bar.position.x + BAR_SIZE.x * 0.5, bar.position.y - 32.0)
	_chain_label.size = Vector2(BAR_SIZE.x * 0.5, 30.0)
	_chain_label.pivot_offset = Vector2(BAR_SIZE.x * 0.5, 15.0)
	_speed_label.position = Vector2(bar.position.x, bar.position.y + 14.0)
	_speed_label.size = Vector2(BAR_SIZE.x, 32.0)
	_banner.position = Vector2(0.0, size.y * 0.24)
	_banner.size = Vector2(size.x, 100.0)
	_banner.pivot_offset = Vector2(size.x * 0.5, 50.0)
	_banner_sub.position = Vector2(0.0, size.y * 0.24 + 98.0)
	_banner_sub.size = Vector2(size.x, 30.0)
	queue_redraw()


## Called by FlowMeter each frame. `value` is the eased meter, `chain` the live ring chain, `speed` m/s.
func show_state(value: float, tier: int, chain: int, speed: float, dt: float) -> void:
	_value = clampf(value, 0.0, 1.0)
	if tier != _tier:
		if tier > _tier:
			_pulse = 1.0
		_tier = tier
	_pulse = maxf(_pulse - dt * 1.6, 0.0)
	_tier_label.text = FlowMeter.TIER_NAMES[clampi(tier, 0, 4)]
	_tier_label.add_theme_color_override("font_color", TIER_COLORS[clampi(tier, 0, 4)])
	_speed_label.text = "%d m/s" % int(speed)
	_speed_label.add_theme_color_override("font_color", TIER_COLORS[clampi(tier, 1, 4)] if speed > 11.0 else Color(1, 1, 1, 0.7))
	if chain != _shown_chain:
		var grew: bool = chain > _shown_chain
		_shown_chain = chain
		_chain_label.text = "CHAIN  x%d" % chain if chain >= 2 else ""
		if chain >= 2:
			_chain_label.modulate.a = 1.0
			if grew:
				if _chain_tw != null and _chain_tw.is_valid():
					_chain_tw.kill()
				_chain_label.scale = Vector2.ONE * 1.35
				_chain_tw = create_tween()
				_chain_tw.tween_property(_chain_label, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if chain < 2:
		_chain_label.modulate.a = move_toward(_chain_label.modulate.a, 0.0, dt * 3.0)
	queue_redraw()


## The soft ZEN banner (the first time per run): fades in, holds, fades out.
func show_zen_banner() -> void:
	_banner.text = "Z E N"
	_banner_sub.text = "everything else falls quiet"
	_banner.add_theme_color_override("font_color", TIER_COLORS[4])
	_banner_sub.add_theme_color_override("font_color", Color(0.8, 0.95, 0.92))
	if _banner_tw != null and _banner_tw.is_valid():
		_banner_tw.kill()
	_banner.scale = Vector2.ONE * 1.12
	_banner_tw = create_tween().set_parallel(true)
	_banner_tw.tween_property(_banner, "modulate:a", 0.9, 0.9).set_trans(Tween.TRANS_SINE)
	_banner_tw.tween_property(_banner_sub, "modulate:a", 0.8, 1.2).set_trans(Tween.TRANS_SINE)
	_banner_tw.tween_property(_banner, "scale", Vector2.ONE, 2.4).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_banner_tw.chain().tween_interval(1.1)
	_banner_tw.chain().tween_property(_banner, "modulate:a", 0.0, 1.4).set_trans(Tween.TRANS_SINE)
	_banner_tw.parallel().tween_property(_banner_sub, "modulate:a", 0.0, 1.4).set_trans(Tween.TRANS_SINE)


## True while the banner is up (tests).
func banner_visible() -> bool:
	return _banner.modulate.a > 0.01


func tier_text() -> String:
	return _tier_label.text


func chain_text() -> String:
	return _chain_label.text if _chain_label.modulate.a > 0.01 else ""


func speed_text() -> String:
	return _speed_label.text


func _draw() -> void:
	var bar: Rect2 = _bar_rect()
	draw_style_box(_bg, bar.grow(2.0))
	var col: Color = TIER_COLORS[clampi(_tier, 0, 4)]
	var w: float = BAR_SIZE.x * _value
	if w > 1.0:
		_fill.bg_color = col.lerp(Color.WHITE, _pulse * 0.5)
		draw_style_box(_fill, Rect2(bar.position, Vector2(maxf(w, BAR_SIZE.y), BAR_SIZE.y)))
	# tier ticks
	for t: float in FlowMeter.TIER_AT:
		var x: float = bar.position.x + BAR_SIZE.x * t
		draw_line(Vector2(x, bar.position.y - 1.0), Vector2(x, bar.end.y + 1.0), Color(1, 1, 1, 0.5), 1.0)
	if _tier >= 4:
		# ZEN: a calm halo around the full bar
		_halo.border_color = Color(1.0, 0.97, 0.88, 0.12 + 0.05 * sin(Time.get_ticks_msec() * 0.003))
		draw_style_box(_halo, bar.grow(5.0))

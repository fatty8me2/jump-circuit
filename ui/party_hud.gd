class_name PartyHud
extends CanvasLayer
## Party Mode overlay, on top of the level HUD: the item slot (icon, name, button prompt) with its
## roulette, the active power-up's timer / charge meter, Shove readiness, the round banner and
## end-of-round countdown, a live standings strip with a big "your place" readout (team totals in
## Team Party), "Targeted!" warnings and off-screen rival arrows, an event feed (KOs, bonuses,
## item hits, passes), big announcements, the waiting bar after you finish (countdown, spectate),
## and a host for the results panels.

const AUTO_SPECTATE_AFTER: float = 4.0
const FEED_MAX: int = 6

var party: PartyLayer

var _root: Control
var _slot_icon: PartyIcon
var _slot_name: Label
var _slot_hint: Label
var _shove: Label
var _power_box: VBoxContainer
var _power_name: Label
var _power_bar: ColorRect
var _power_fill: ColorRect
var _power_status: Label
var _charge_bar: ColorRect
var _charge_fill: ColorRect
var _round: Label
var _count: Label
var _score: Label
var _feed: VBoxContainer
var _announce: Label
var _announce_tw: Tween
var _panel_host: Control
var _hint: Label
var _last_count: int = -1
var _finish_bar: PanelContainer
var _finish_count: Label
var _finish_fill: ColorRect
var _finish_cb: Callable
var _auto_spec_in: float = -1.0

## The standings strip and the rival arrows.
var standings: PartyStandings
var radar: PartyRadar
var _board_t: float = 0.0
var _prev_order: Array[int] = []

## The item slot's roulette (a fresh pickup spins ~0.8 s, ticking, then lands).
var roulette := PartyRoulette.new()
var roulette_ticks_total: int = 0
var _held: String = ""

## "Targeted!" warnings.
var _target_box: VBoxContainer
var _target_title: Label
var _target_sub: Label
var _target_tw: Tween
var _edge: TextureRect
var _edge_tw: Tween
var _now: float = 0.0
var _scan_t: float = 0.0
var _last_warn: Dictionary = {}
## Rival id -> seconds (HUD clock) until which they count as a threat.
var _threat_until: Dictionary = {}
## Every warning shown: [{id, what}] (tests read this).
var warn_log: Array[Dictionary] = []

## The event feed's history: [{text, kind, icon}] (kind: ko, bonus, hit, use, pass, info).
var feed_log: Array[Dictionary] = []
var _hit_merge: Dictionary = {}


func _ready() -> void:
	layer = 6
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UiKit.theme()
	add_child(_root)

	# red vignette that pulses when somebody is after you
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.62, 1.0])
	grad.colors = PackedColorArray([Color(1, 0.1, 0.05, 0.0), Color(1, 0.1, 0.05, 0.0), Color(1, 0.1, 0.05, 0.55)])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 128
	gt.height = 128
	_edge = TextureRect.new()
	_edge.texture = gt
	_edge.set_anchors_preset(Control.PRESET_FULL_RECT)
	_edge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_edge.stretch_mode = TextureRect.STRETCH_SCALE
	_edge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_edge.modulate.a = 0.0
	_root.add_child(_edge)

	radar = PartyRadar.new()
	radar.party = party
	radar.visible = party != null and not party.practice
	_root.add_child(radar)

	# item slot, top left under the stage / falls line (the bottom left belongs to the level intro)
	var slot: PanelContainer = UiKit.panel()
	slot.set_anchors_preset(Control.PRESET_TOP_LEFT)
	slot.position = Vector2(24, 86)
	slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var row: HBoxContainer = UiKit.hbox(12)
	slot.add_child(row)
	_slot_icon = PartyIcon.new()
	row.add_child(_slot_icon)
	var col: VBoxContainer = UiKit.vbox(2)
	row.add_child(col)
	_slot_name = UiKit.label("", 22, Color.WHITE)
	col.add_child(_slot_name)
	_slot_hint = UiKit.label("", 16, UiKit.SOFT)
	col.add_child(_slot_hint)
	_shove = UiKit.label("", 15, UiKit.TEAL)
	col.add_child(_shove)
	_root.add_child(slot)

	# active power-up, bottom centre
	_power_box = UiKit.vbox(4)
	_power_box.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_power_box.position = Vector2(-200, -150)
	_power_box.custom_minimum_size = Vector2(400, 0)
	_power_box.visible = false
	_root.add_child(_power_box)
	_power_name = UiKit.shadowed(UiKit.label("", 24, UiKit.GOLD, HORIZONTAL_ALIGNMENT_CENTER), 6)
	_power_box.add_child(_power_name)
	var bars: Array = _bar(Color(1, 1, 1, 0.18), UiKit.GOLD, 10)
	_power_bar = bars[0]
	_power_fill = bars[1]
	_power_box.add_child(_power_bar)
	_power_status = UiKit.shadowed(UiKit.label("", 17, UiKit.SOFT, HORIZONTAL_ALIGNMENT_CENTER), 5)
	_power_box.add_child(_power_status)
	var cbars: Array = _bar(Color(1, 1, 1, 0.12), Color(0.7, 0.4, 1.0), 14)
	_charge_bar = cbars[0]
	_charge_fill = cbars[1]
	_power_box.add_child(_charge_bar)

	_round = UiKit.shadowed(UiKit.label("", 22, UiKit.GOLD, HORIZONTAL_ALIGNMENT_CENTER), 6)
	_round.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_round.position = Vector2(-300, 52)
	_round.custom_minimum_size = Vector2(600, 0)
	_root.add_child(_round)
	_count = UiKit.shadowed(UiKit.label("", 30, Color(1.0, 0.55, 0.45), HORIZONTAL_ALIGNMENT_CENTER), 7)
	_count.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_count.position = Vector2(-300, 48)
	_count.custom_minimum_size = Vector2(600, 0)
	_root.add_child(_count)

	_score = UiKit.shadowed(UiKit.label("", 19, Color(1, 1, 1, 0.9)), 5)
	_score.position = Vector2(24, 50)
	_root.add_child(_score)

	# live standings: big place + the racers in order, top right (replaces the level's race board)
	standings = PartyStandings.new()
	standings.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	standings.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	standings.position = Vector2(-20, 10)
	standings.visible = false
	_root.add_child(standings)
	standings.place_changed.connect(_on_place_changed)

	_feed = UiKit.vbox(3)
	_feed.set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	_feed.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_feed.position = Vector2(-20, 70)
	_feed.custom_minimum_size = Vector2(400, 0)
	_feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_feed)

	_announce = UiKit.shadowed(UiKit.label("", 46, UiKit.GOLD, HORIZONTAL_ALIGNMENT_CENTER), 10)
	_announce.set_anchors_preset(Control.PRESET_CENTER)
	_announce.position = Vector2(-400, -150)
	_announce.custom_minimum_size = Vector2(800, 0)
	_announce.modulate.a = 0.0
	_root.add_child(_announce)

	# "TARGETED!" banner under the round line
	_target_box = UiKit.vbox(0)
	_target_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_target_box.position = Vector2(-300, 104)
	_target_box.custom_minimum_size = Vector2(600, 0)
	_target_box.modulate.a = 0.0
	_target_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_target_box)
	_target_title = UiKit.shadowed(UiKit.label("TARGETED!", 46, Color(1.0, 0.3, 0.25), HORIZONTAL_ALIGNMENT_CENTER), 11)
	_target_box.add_child(_target_title)
	_target_sub = UiKit.shadowed(UiKit.label("", 22, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER), 6)
	_target_box.add_child(_target_sub)

	_hint = UiKit.shadowed(UiKit.label("", 17, Color(1, 1, 1, 0.8), HORIZONTAL_ALIGNMENT_CENTER), 5)
	_hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_hint.position = Vector2(-400, -42)
	_hint.custom_minimum_size = Vector2(800, 0)
	_root.add_child(_hint)

	_panel_host = Control.new()
	_panel_host.set_anchors_preset(Control.PRESET_FULL_RECT)
	_panel_host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_panel_host)

	if party != null and party.rules != null:
		var mode_name: String = PartyNames.mode_name(party.rules.mode)
		if party.practice:
			_round.text = mode_name.to_upper()
			_hint.text = "Every ? box gives the next power-up. Practice dummies wait on the checkpoint lawns."
			_fade_later(_hint, 9.0)
		else:
			_round.text = "ROUND %d  -  %s  -  %s" % [party.rules.round_no, mode_name.to_upper(), PartyNames.CUP.to_upper()]
		_fade_later(_round, 6.0, 0.55)
		party.hit_landed.connect(_on_hit_landed)
		party.hit_taken.connect(_on_hit_taken)
		party.item_changed.connect(_on_item_changed)


func _bar(bg: Color, fg: Color, h: float) -> Array:
	var back := ColorRect.new()
	back.color = bg
	back.custom_minimum_size = Vector2(400, h)
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var fill := ColorRect.new()
	fill.color = fg
	fill.size = Vector2(400, h)
	fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.add_child(fill)
	return [back, fill]


func _fade_later(c: CanvasItem, after: float, to_alpha: float = 0.0) -> void:
	var tw: Tween = create_tween()
	tw.tween_interval(after)
	tw.tween_property(c, "modulate:a", to_alpha, 1.0)


func _sfx(clip: String, volume: float = 1.0, pitch: float = 1.0) -> void:
	if party != null and party.sfx != null:
		party.sfx.play(clip, volume, pitch)


func _process(dt: float) -> void:
	if party == null:
		return
	_now += dt
	_hide_level_board()
	_process_slot(dt)
	_process_power()
	if not party.practice:
		_process_round()
		_board_t -= dt
		if _board_t <= 0.0:
			_board_t = 0.2
			update_standings()
		_scan_t -= dt
		if _scan_t <= 0.0:
			_scan_t = 0.1
			_scan_threats()
		_sync_danger()
		_process_finish_bar(dt)
	else:
		_score.text = ""
		_count.visible = false


## The standings strip replaces the level's own race board in Party races.
func _hide_level_board() -> void:
	if party.practice or party.level == null or party.level.hud == null:
		return
	var b: Control = party.level.hud._board
	if b != null and b.visible:
		b.visible = false


func _process_slot(dt: float) -> void:
	# item slot (flicking through items for a moment after a pickup)
	if roulette.active and party.item != "":
		var r: Dictionary = roulette.step(dt)
		if bool(r["tick"]):
			roulette_ticks_total += 1
			_slot_icon.item_id = roulette.current
			_slot_icon.pivot_offset = _slot_icon.size * 0.5
			_slot_icon.scale = Vector2.ONE * 1.14
			create_tween().tween_property(_slot_icon, "scale", Vector2.ONE, 0.06)
			if not bool(r["landed"]):
				_sfx("tick", 0.55, 0.85 + 0.5 * roulette.elapsed / PartyRoulette.DURATION)
		if bool(r["landed"]):
			_land_roll()
	elif roulette.active:
		roulette.active = false   # used / lost mid-spin
		_slot_icon.item_id = party.item
	else:
		_slot_icon.item_id = party.item
	if roulette.active:
		_slot_name.text = "? ? ?"
		_slot_name.add_theme_color_override("font_color", UiKit.GOLD)
		_slot_hint.text = "..."
	elif party.item != "":
		_slot_name.text = PartyNames.item_name(party.item)
		_slot_name.add_theme_color_override("font_color", PartyNames.item_color(party.item).lightened(0.3))
		_slot_hint.text = "%s  use" % Game.prompt("use_item")
	else:
		_slot_name.text = "No item"
		_slot_name.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
		_slot_hint.text = "Grab a ? box"
	var pw: PowerUp = party.transformation()
	var shove_key: String = Game.prompt("shove")
	if pw == null:
		shove_key += " / " + Game.prompt("attack")
	_shove.text = ("%s  %s" % [shove_key, PartyNames.move_name("shove")]) if party.shove_cd <= 0.0 else "%s  ..." % PartyNames.move_name("shove")
	_shove.modulate.a = 1.0 if party.shove_cd <= 0.0 else 0.45


func _process_power() -> void:
	# active power-up (the transformation first, else the latest gadget)
	var show: PowerUp = party.transformation()
	if show == null:
		for a: PowerUp in party.actives:
			if not a.ended:
				show = a
	_power_box.visible = show != null
	if show == null:
		return
	_power_name.text = PartyNames.item_name(show.item_id).to_upper()
	_power_name.add_theme_color_override("font_color", PartyNames.item_color(show.item_id).lightened(0.25))
	var frac: float = clampf(show.time_left / maxf(show.duration, 0.01), 0.0, 1.0)
	# running out: the timer blinks faster and faster over its last two seconds
	var left: float = show.time_left - (0.0 if show.local else 1.0)
	_power_box.modulate.a = 1.0 if PartyFx.blink_on(left, 2.0) else 0.5
	_power_fill.size.x = 400.0 * frac
	_power_fill.color = PartyNames.item_color(show.item_id).lerp(Color(1, 0.3, 0.3), 1.0 - frac if frac < 0.3 else 0.0)
	var status: String = show.hud_status()
	if show.takes_attack and status == "":
		status = "%s attack" % Game.prompt("attack")
	_power_status.text = status
	var ch: float = show.charge_frac()
	_charge_bar.visible = ch >= 0.0
	_charge_fill.size.x = 400.0 * maxf(ch, 0.0)
	_charge_fill.color = Color(0.7, 0.4, 1.0).lerp(Color(1.0, 0.95, 0.6), ch)


func _process_round() -> void:
	# score line (team totals live in the standings strip)
	var me: int = Net.my_id()
	var line: String = "KOs %d    Bonus %d" % [int(party.kos.get(me, 0)), int(party.bonus.get(me, 0))]
	if not party.rules.is_team() and party.rules.cup.has(me):
		line += "    Cup %d" % int(party.rules.cup[me])
	_score.text = line
	# end-of-round countdown
	var left: float = PartyRules.time_left(party.finish_times(), Game.course_time)
	if left >= 0.0 and not party.round_over:
		var n: int = int(ceil(left))
		_count.text = "Round ends in %d" % n
		_count.visible = true
		_round.visible = false   # the countdown takes the round banner's place
		if n != _last_count and n <= 10:
			Sfx.play("tick", 0.0, 0.6)
			_count.pivot_offset = _count.size * 0.5
			_count.scale = Vector2.ONE * 1.3
			create_tween().tween_property(_count, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		_count.add_theme_color_override("font_color", Color(1.0, 0.3, 0.25) if n <= 10 else Color(1.0, 0.55, 0.45))
		_last_count = n
	else:
		_count.visible = false


func _cup_teams() -> Dictionary:
	var t: Dictionary = party.rules.teams.duplicate()
	for id: Variant in Net.teams:
		t[int(id)] = int(Net.teams[id])
	return t


# ---- standings -----------------------------------------------------------------------------------

## Rebuilds the strip from the live race order (a few times a second; tests call it directly).
func update_standings() -> void:
	if party == null or party.practice:
		return
	var teams: Dictionary = _cup_teams()
	var order: Array[int] = Net.standings()
	var list: Array[Dictionary] = PartyBoard.entries(order, Net.roster, party.kos, party.bonus, party.rules.cup, teams, Net.my_id())
	standings.visible = not list.is_empty()
	var total: int = party.level.checkpoints.size() + 1 if party.level != null else 1
	var team: bool = party.rules.is_team()
	standings.update(list, total, team, PartyBoard.team_live(list), PartyBoard.team_cup(list))
	_note_passes(order)


## Feed lines for racers who swapped places with us since the last look.
func _note_passes(order: Array[int]) -> void:
	var me: int = Net.my_id()
	if not _prev_order.is_empty() and _prev_order.has(me) and order.has(me) and not party.level.finished:
		var was_me: int = _prev_order.find(me)
		var now_me: int = order.find(me)
		for id: int in order:
			if id == me or not _prev_order.has(id):
				continue
			var was_ahead: bool = _prev_order.find(id) < was_me
			var now_ahead: bool = order.find(id) < now_me
			if was_ahead and not now_ahead:
				feed("You passed %s!" % party.racer_name(id), Color(0.5, 1.0, 0.6), "pass")
			elif now_ahead and not was_ahead:
				feed("%s passed you!" % party.racer_name(id), Color(1.0, 0.55, 0.5), "pass")
	_prev_order = order.duplicate()


func _on_place_changed(old: int, now: int) -> void:
	if now < old:
		_sfx("chime", 0.5, 1.1)
	else:
		_sfx("clank", 0.3, 0.8)


# ---- threats -------------------------------------------------------------------------------------

## Rival projectiles closing in on us (their flight is deterministic, so the arc is known).
func _scan_threats() -> void:
	if party.player == null or party.level.finished or party.round_over:
		return
	var me: Vector3 = party.player.global_position + Vector3(0, 0.8, 0)
	for key: Variant in party.projectiles.keys():
		var pr: PartyProjectile = party.projectiles[key] as PartyProjectile
		if pr == null or not is_instance_valid(pr) or pr.done or pr.local or not party.is_rival(pr.owner_id):
			continue
		var to_me: Vector3 = me - pr.global_position
		var dist: float = to_me.length()
		if dist > 30.0:
			continue
		var vel: Vector3 = (pr.pos_at(pr.t + 0.1) - pr.pos_at(pr.t)) / 0.1
		if vel.length() < 1.0:
			continue
		if dist < 5.0 or vel.normalized().dot(to_me.normalized()) > 0.8:
			_threat_until[pr.owner_id] = _now + 0.7
			warn(pr.owner_id, "incoming!")


## A rival's item action reached us (fx message): a charging attack is a threat while it lasts.
func on_remote_fx(from_id: int, item: String, action: String, d: Dictionary) -> void:
	if party != null and not party.practice and (action == "tell" or action == "launch") and party.is_rival(from_id):
		_on_incoming(from_id, item, action, d)
		return
	if party == null or party.practice or action != "charge" or not party.is_rival(from_id):
		return
	if bool(d.get("on", true)):
		_threat_until[from_id] = _now + 6.0
		var g: RemoteRacer = party.ghost(from_id)
		if g != null and party.player != null and g.global_position.distance_to(party.player.global_position) < 50.0:
			warn(from_id, "charging an attack")
	else:
		_threat_until.erase(from_id)


## A rival's Leader Strike ("tell") or Homing Shell ("launch") is on its way: the one it is aimed at
## gets the big "Targeted!" banner, and so does anyone standing close enough to the strike's zone.
func _on_incoming(from_id: int, item: String, action: String, d: Dictionary) -> void:
	if party.player == null or party.level.finished or party.round_over:
		return
	var aimed: bool = int(d.get("t", 0)) == Net.my_id()
	var near: bool = false
	if action == "tell" and not aimed:
		var at: Vector3 = PowerUp.v3(d.get("at", []))
		near = at != Vector3.ZERO and at.distance_to(party.player.global_position) < StrikeZone.RADIUS + 5.0
	if not aimed and not near:
		return
	_threat_until[from_id] = maxf(float(_threat_until.get(from_id, 0.0)), _now + (StrikeZone.TELL + 0.5 if action == "tell" else 3.0))
	var what: String = PartyNames.item_name(item)
	if near:
		what += " - get clear!"
	warn(from_id, what)


## A rival used an item (use message): the feed says so, and Thunder / Swap warn when they reach us.
func on_item_used(from_id: int, item: String) -> void:
	if party == null or from_id == Net.my_id():
		return
	var line: String = PartyFeedText.use_line(party.racer_name(from_id), item)
	if line != "":
		feed(line, party.team_color_of(from_id), "use", item)
	if party.practice or party.level.finished or party.round_over or not party.is_rival(from_id):
		return
	var order: Array[int] = Net.standings()
	var mine: int = order.find(Net.my_id())
	var theirs: int = order.find(from_id)
	if mine < 0 or theirs < 0:
		return
	if (item == "thunder" and mine < theirs) or (item == "swap" and mine == theirs - 1):
		warn(from_id, PartyNames.item_name(item))


## The big "TARGETED!" banner (with the red edge pulse, a sting and the culprit's arrow).
func warn(from_id: int, what: String) -> void:
	var key: String = "%d:%s" % [from_id, what]
	if _now - float(_last_warn.get(key, -9.0)) < 1.5:
		return
	_last_warn[key] = _now
	_threat_until[from_id] = maxf(float(_threat_until.get(from_id, 0.0)), _now + 2.5)
	warn_log.append({"id": from_id, "what": what})
	_target_sub.text = "%s  -  %s" % [party.racer_name(from_id), what]
	_target_sub.add_theme_color_override("font_color", party.team_color_of(from_id).lerp(Color.WHITE, 0.5))
	_target_box.pivot_offset = Vector2(300, 30)
	_target_box.scale = Vector2.ONE * 1.5
	_target_box.modulate.a = 1.0
	if _target_tw != null and _target_tw.is_valid():
		_target_tw.kill()
	_target_tw = create_tween()
	_target_tw.tween_property(_target_box, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_target_tw.tween_interval(1.3)
	_target_tw.tween_property(_target_box, "modulate:a", 0.0, 0.4)
	_pulse_edge(0.8)
	_sfx("warn", 0.8)


func _pulse_edge(strength: float) -> void:
	_edge.modulate.a = strength
	if _edge_tw != null and _edge_tw.is_valid():
		_edge_tw.kill()
	_edge_tw = create_tween()
	_edge_tw.tween_property(_edge, "modulate:a", 0.0, 0.9)


func _sync_danger() -> void:
	var d: Dictionary = {}
	for id: Variant in _threat_until.keys():
		if float(_threat_until[id]) > _now:
			d[int(id)] = true
		else:
			_threat_until.erase(id)
	radar.danger = d


## Rivals currently flagged as a threat (arrows pulse red for them).
func threats() -> Array[int]:
	var out: Array[int] = []
	for id: Variant in _threat_until:
		if float(_threat_until[id]) > _now:
			out.append(int(id))
	return out


func _on_hit_taken(from_id: int, _src: String) -> void:
	_pulse_edge(0.5)
	if from_id > 0:
		_threat_until[from_id] = maxf(float(_threat_until.get(from_id, 0.0)), _now + 2.0)


# ---- the event feed -----------------------------------------------------------------------------

func _racer_word(id: int, victim: bool) -> String:
	if id == Net.my_id():
		return "you" if victim else "You"
	return party.racer_name(id)


## Our attack connected: a feed line here, and everyone else hears of it (hf message).
func _on_hit_landed(target_id: int, src: String) -> void:
	on_hit_event(Net.my_id(), target_id, src)
	if (target_id > 0 or target_id <= -1000) and Net.active:
		Net.send_party({"k": "hf", "v": target_id, "s": src})


## Somebody's item / move hit somebody: "Ana iced Bo!" (several victims of one blast share a line).
func on_hit_event(attacker: int, victim: int, src: String) -> void:
	if party == null:
		return
	var who: String = _racer_word(attacker, false)
	var vic: String = party.racer_name(victim) if victim <= -1000 else ("Dummy" if victim < 0 else _racer_word(victim, true))
	var key: String = "%d|%s" % [attacker, src]
	if not _hit_merge.is_empty() and str(_hit_merge["key"]) == key and _now - float(_hit_merge["t"]) < 0.9 \
			and is_instance_valid(_hit_merge["label"]) and not (_hit_merge["victims"] as Array).has(vic):
		(_hit_merge["victims"] as Array).append(vic)
		var text: String = PartyFeedText.hit_line(who, _hit_merge["victims"], src)
		(_hit_merge["label"] as Label).text = text
		feed_log[feed_log.size() - 1]["text"] = text
		return
	var l: Label = feed_line(PartyFeedText.hit_line(who, [vic], src), party.team_color_of(attacker), "hit", PartyFeedText.item_for(src))
	_hit_merge = {"key": key, "t": _now, "label": l, "victims": [vic]}


## A hit reported by another screen (hf message): show it unless it is ours already.
func on_remote_hit(from_id: int, victim: int, src: String) -> void:
	if from_id == Net.my_id():
		return
	on_hit_event(from_id, victim, src)


func _on_item_changed(id: String) -> void:
	if id != "":
		_held = id
	elif _held != "":
		# the slot emptied: that item was used (everyone else is told, for their feed and warnings)
		if Net.active and not party.practice and not party.slot_quiet:
			Net.send_party({"k": "use", "p": _held})
		_held = ""


## Kill-feed line (fades after a few seconds; newest at the bottom, FEED_MAX kept).
func feed(text: String, color: Color = UiKit.SOFT, kind: String = "", icon: String = "") -> void:
	if kind == "":
		kind = "ko" if text.contains("KO'd") else ("bonus" if text.contains("first through") or text.contains("First through") else "info")
	feed_line(text, color, kind, icon)


func feed_line(text: String, color: Color, kind: String, icon: String = "") -> Label:
	_hit_merge = {}
	var row: HBoxContainer = UiKit.hbox(6)
	row.alignment = BoxContainer.ALIGNMENT_END
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if icon != "":
		var ic := PartyIcon.new()
		ic.custom_minimum_size = Vector2(30, 30)
		ic.item_id = icon
		row.add_child(ic)
	var l: Label = UiKit.shadowed(UiKit.label(text, 20, color.lerp(Color.WHITE, 0.25), HORIZONTAL_ALIGNMENT_RIGHT), 5)
	row.add_child(l)
	_feed.add_child(row)
	feed_log.append({"text": text, "kind": kind, "icon": icon})
	while feed_log.size() > 60:
		feed_log.remove_at(0)
	while _feed.get_child_count() > FEED_MAX:
		var old: Node = _feed.get_child(0)
		_feed.remove_child(old)
		old.queue_free()
	# slide in from the right, then fade
	row.modulate.a = 0.0
	var tw: Tween = row.create_tween()
	tw.tween_property(row, "modulate:a", 1.0, 0.12)
	tw.tween_interval(5.0)
	tw.tween_property(row, "modulate:a", 0.0, 0.8)
	tw.tween_callback(row.queue_free)
	return l


# ---- announcements & the item roulette -------------------------------------------------------------

## Big centre call-out ("NINE-TAILED FOX!", "KO! +3").
func announce(text: String, color: Color = UiKit.GOLD) -> void:
	_announce.text = text
	_announce.add_theme_color_override("font_color", color)
	if _announce_tw != null and _announce_tw.is_valid():
		_announce_tw.kill()
	_announce.pivot_offset = _announce.size * 0.5
	_announce.scale = Vector2.ONE * 1.5
	_announce.modulate.a = 0.0
	_announce_tw = create_tween()
	_announce_tw.tween_property(_announce, "modulate:a", 1.0, 0.1)
	_announce_tw.parallel().tween_property(_announce, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_announce_tw.tween_interval(1.1)
	_announce_tw.tween_property(_announce, "modulate:a", 0.0, 0.4)


## The slot filled: the roulette spins ~0.8 s (ticking), then lands on the rolled item with a pop.
func item_rolled(id: String) -> void:
	roulette.start(id)
	if party != null and party.practice:
		_hint.text = "%s  -  %s" % [PartyNames.item_name(id), PartyNames.item_desc(id)]
		_hint.modulate.a = 1.0
		_fade_later(_hint, 5.0)


## The roulette stops on the real item: the icon slams in with a white flash and a ding.
func _land_roll() -> void:
	roulette.active = false
	_slot_icon.item_id = roulette.final_id
	_slot_icon.pivot_offset = _slot_icon.size * 0.5
	_slot_icon.scale = Vector2.ONE * 1.6
	_slot_icon.modulate = Color(2.2, 2.2, 2.2)
	var tw: Tween = create_tween().set_parallel(true)
	tw.tween_property(_slot_icon, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(_slot_icon, "modulate", Color.WHITE, 0.3)
	_sfx("land", 0.8)


# ---- round end, finishing, results -----------------------------------------------------------------

func show_round_over() -> void:
	_count.visible = false
	hide_finished()
	announce("ROUND OVER", Color.WHITE)


## We finished but the round runs on: a small bottom bar ("Finished 2nd - waiting for the
## others"), the round's countdown, and a Spectate button (focused, for the pad) when the level
## can follow a rival. A few seconds later the camera moves to a rival by itself.
func show_finished(place: int, can_spectate: bool, on_spectate: Callable) -> void:
	hide_finished()
	_finish_cb = on_spectate
	_finish_bar = UiKit.panel()
	_finish_bar.name = "FinishBar"
	_finish_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_finish_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_finish_bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_finish_bar.position.y -= 190.0
	var col: VBoxContainer = UiKit.vbox(8)
	_finish_bar.add_child(col)
	var what: String = "Finished %d%s" % [place, Hud._ordinal(place)] if place > 0 else "Finished"
	col.add_child(UiKit.label("%s - waiting for the others" % what, 22, UiKit.GOLD, HORIZONTAL_ALIGNMENT_CENTER))
	_finish_count = UiKit.label("", 20, Color(1.0, 0.6, 0.5), HORIZONTAL_ALIGNMENT_CENTER)
	_finish_count.name = "FinishCount"
	col.add_child(_finish_count)
	var bars: Array = _bar(Color(1, 1, 1, 0.15), Color(1.0, 0.55, 0.4), 8)
	(bars[0] as ColorRect).custom_minimum_size = Vector2(440, 8)
	_finish_fill = bars[1]
	col.add_child(bars[0])
	if can_spectate:
		var b: Button = UiKit.button("Spectate", func() -> void: on_spectate.call(), 240)
		b.name = "Spectate"
		var hrow: HBoxContainer = UiKit.hbox(14)
		hrow.alignment = BoxContainer.ALIGNMENT_CENTER
		hrow.add_child(b)
		hrow.add_child(UiKit.label("%s / %s  switch racer" % [Game.prompt("spectate_prev"), Game.prompt("spectate_next")], 17, UiKit.SOFT))
		col.add_child(hrow)
		b.grab_focus.call_deferred()
		_auto_spec_in = AUTO_SPECTATE_AFTER
	else:
		_auto_spec_in = -1.0
	_root.add_child(_finish_bar)
	_process_finish_bar(0.0)


func _process_finish_bar(dt: float) -> void:
	if _finish_bar == null or not is_instance_valid(_finish_bar):
		return
	var left: float = PartyRules.time_left(party.finish_times(), Game.course_time)
	if left >= 0.0:
		_finish_count.text = "Round ends in %d s" % int(ceil(left))
		_finish_fill.size.x = 440.0 * clampf(left / PartyRules.ROUND_GRACE, 0.0, 1.0)
	else:
		_finish_count.text = "Waiting for the others..."
		_finish_fill.size.x = 440.0
	if _auto_spec_in > 0.0 and _finish_bar.visible and not has_panel():
		_auto_spec_in -= dt
		if _auto_spec_in <= 0.0 and _finish_cb.is_valid():
			_finish_cb.call()


## While spectating the waiting bar steps aside (the spectate bar shows the controls);
## back from watching, it returns with Spectate focused again.
func on_spectating(on: bool) -> void:
	if _finish_bar == null or not is_instance_valid(_finish_bar):
		return
	_auto_spec_in = -1.0
	_finish_bar.visible = not on
	if not on:
		UiKit.focus_first(_finish_bar)


func hide_finished() -> void:
	if _finish_bar != null and is_instance_valid(_finish_bar):
		_finish_bar.queue_free()
	_finish_bar = null
	_auto_spec_in = -1.0


## A results panel (centred, dimmed background, takes mouse + pad input).
func add_panel(panel: Control) -> void:
	for c: Node in _panel_host.get_children():
		c.queue_free()
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.07, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel_host.add_child(dim)
	var centre: CenterContainer = UiKit.centered(panel)
	_panel_host.add_child(centre)
	_panel_host.modulate.a = 0.0
	create_tween().tween_property(_panel_host, "modulate:a", 1.0, 0.3)
	# the strip, arrows and warnings make way for the scoreboard
	standings.visible = false
	radar.visible = false


func has_panel() -> bool:
	return _panel_host.get_child_count() > 0


## Results panels: nothing focused (a stray mouse click) -> the first pad / arrow press
## finds the panel's first button again.
func _unhandled_input(event: InputEvent) -> void:
	if has_panel() and Game.is_menu_nav(event) and get_viewport().gui_get_focus_owner() == null:
		UiKit.focus_first(_panel_host)
		get_viewport().set_input_as_handled()

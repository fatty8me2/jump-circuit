class_name PartyPodium
extends Control
## The champion screen after the last round of a finite Party Cup: the top three racers (or the two teams)
## stand on pedestals wearing the cosmetics they raced in - CPUs too - in a little 3D set of their own. A drum
## roll reveals third and second place, then the champion appears to a fanfare and confetti and plays their
## victory pose (PlayerVisual.play_pose); the cup totals fade in beside them. Pad navigable: the screen starts
## on its main button, A confirms, any press while the reveal plays skips to the end.

const REVEAL_3RD: float = 0.5
const REVEAL_2ND: float = 1.3
const REVEAL_1ST: float = 2.4
const UI_AT: float = 3.2
const PEDESTAL_X: Array[float] = [0.0, -2.5, 2.5]
const PEDESTAL_H: Array[float] = [1.5, 1.0, 0.65]

var rules: PartyRules
var roster: Dictionary = {}
var sfx: PartySfx
## The podium entries (see entries()): [{rank, label, color, pts, ids}], 1st first.
var shown: Array[Dictionary] = []
## The button focused first.
var first: Control
## One RemoteRacer per racer on a pedestal: id -> RemoteRacer.
var racers: Dictionary = {}
var t: float = 0.0
var done: bool = false
var winner_pose: String = ""
var champion_id: int = 0

var _viewport: SubViewport
var _stage: Node3D
var _pedestals: Array[Node3D] = []
var _revealed: Array[bool] = [false, false, false]
var _banner: Label
var _side: Control
var _buttons: Array[BaseButton] = []
var _fx_done: bool = false


## The podium: individuals ranked by cup points (top 3), or the two teams (their best members stand on them).
static func entries(p_rules: PartyRules, p_roster: Dictionary) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var standings: Array = p_rules.cup_standings()
	if p_rules.is_team():
		var totals: Array[int] = PartyRules.team_totals(p_rules.cup, p_rules.teams)
		var order: Array[int] = [0, 1]
		if totals[1] > totals[0]:
			order = [1, 0]
		var rank: int = 1
		for team: int in order:
			var ids: Array[int] = []
			for e: Variant in standings:
				var id: int = int((e as Array)[0])
				if int(p_rules.teams.get(id, 0)) == team and ids.size() < 3:
					ids.append(id)
			out.append({"rank": rank, "label": "Team %s" % PartyNames.team_name(team), "color": PartyNames.team_color(team),
				"pts": totals[team], "ids": ids})
			rank += 1
		return out
	for i: int in mini(3, standings.size()):
		var id: int = int((standings[i] as Array)[0])
		var col: Color = Color.WHITE
		if p_roster.has(id):
			col = Settings.RACER_COLORS[int((p_roster[id] as Dictionary).get("color", 0)) % Settings.RACER_COLORS.size()]
		out.append({"rank": i + 1, "label": str(p_rules.names.get(id, "?")), "color": col, "pts": int((standings[i] as Array)[1]), "ids": [id]})
	return out


func setup(p_rules: PartyRules, p_roster: Dictionary, p_sfx: PartySfx, host: bool, on_lobby: Callable, on_leave: Callable) -> void:
	rules = p_rules
	roster = p_roster
	sfx = p_sfx
	shown = entries(rules, roster)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UiKit.theme()
	_build_ui(host, on_lobby, on_leave)
	if not shown.is_empty() and not (shown[0]["ids"] as Array).is_empty():
		champion_id = int((shown[0]["ids"] as Array)[0])
		var entry: Dictionary = roster.get(champion_id, {})
		winner_pose = Cosmetics.clean("pose", entry.get("pose"))


## The 3D set is built once we are in the tree (the racers' rigs are made in their _ready).
func _ready() -> void:
	_build_stage()
	move_child(get_child(get_child_count() - 1), 0)   # (the stage sits behind the text and buttons)
	start()


# ---- the 3D set -----------------------------------------------------------------------------------------

func _build_stage() -> void:
	var cont := SubViewportContainer.new()
	cont.set_anchors_preset(Control.PRESET_FULL_RECT)
	cont.stretch = true
	cont.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cont)
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_2X
	_viewport.handle_input_locally = false
	cont.add_child(_viewport)
	_stage = Node3D.new()
	_viewport.add_child(_stage)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.07, 0.16)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.6, 0.8)
	env.ambient_light_energy = 0.7
	env.glow_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	_stage.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-40, 25, 0)
	sun.light_energy = 1.2
	_stage.add_child(sun)
	var cam := Camera3D.new()
	cam.fov = 42.0
	_stage.add_child(cam)
	cam.position = Vector3(0, 2.6, 8.8)
	cam.rotation_degrees = Vector3(-7.5, 0, 0)
	# the floor disc and the pedestals
	var floor_mesh := CylinderMesh.new()
	floor_mesh.top_radius = 6.0
	floor_mesh.bottom_radius = 6.2
	floor_mesh.height = 0.2
	PartyFx.part(_stage, floor_mesh, PartyFx.solid_mat(Color(0.12, 0.14, 0.24), 0.0, 0.5, 0.2), Vector3(0, -0.1, 0))
	var colors: Array[Color] = [Color(1.0, 0.82, 0.25), Color(0.78, 0.82, 0.9), Color(0.85, 0.52, 0.3)]
	for i: int in 3:
		var holder := Node3D.new()
		holder.position = Vector3(PEDESTAL_X[i], 0, 0)
		holder.visible = false
		_stage.add_child(holder)
		var box := BoxMesh.new()
		box.size = Vector3(2.0, PEDESTAL_H[i], 2.0)
		PartyFx.part(holder, box, PartyFx.solid_mat(colors[i], 0.15, 0.35, 0.5), Vector3(0, PEDESTAL_H[i] * 0.5, 0))
		var num := Label3D.new()
		num.text = str(i + 1)
		num.font_size = 120
		num.pixel_size = 0.008
		num.outline_size = 20
		num.modulate = Color(0.15, 0.1, 0.0) if i == 0 else Color(0.1, 0.1, 0.15)
		num.outline_modulate = Color(1, 1, 1, 0.8)
		holder.add_child(num)
		num.position = Vector3(0, PEDESTAL_H[i] * 0.5, 1.02)
		_pedestals.append(holder)
	# the racers: one pedestal per entry, a team's members side by side on theirs
	for i: int in mini(shown.size(), 3):
		var ids: Array = shown[i]["ids"]
		for j: int in ids.size():
			var id: int = int(ids[j])
			var r := RemoteRacer.new()
			_pedestals[i].add_child(r)
			var entry: Dictionary = roster.get(id, {})
			r.setup(str(rules.names.get(id, "?")), shown[i]["color"] as Color)
			r.apply_cosmetics(entry)
			if rules.is_team():
				r.set_team(PartyNames.team_name(int(rules.teams.get(id, 0))), shown[i]["color"] as Color)
			var spread: float = 0.0 if ids.size() == 1 else (float(j) - float(ids.size() - 1) * 0.5) * 1.1
			r.position = Vector3(spread, PEDESTAL_H[i], 0)
			racers[id] = r


func _build_ui(host: bool, on_lobby: Callable, on_leave: Callable) -> void:
	_banner = UiKit.shadowed(UiKit.label("", 56, UiKit.GOLD, HORIZONTAL_ALIGNMENT_CENTER), 12)
	_banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_banner.custom_minimum_size = Vector2(900, 0)
	_banner.position = Vector2(-450, 30)
	_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_banner)
	var title: Label = UiKit.shadowed(UiKit.label("%s  -  CHAMPION" % PartyNames.CUP.to_upper(), 22, UiKit.TEAL, HORIZONTAL_ALIGNMENT_CENTER), 6)
	title.set_anchors_preset(Control.PRESET_CENTER_TOP)
	title.custom_minimum_size = Vector2(900, 0)
	title.position = Vector2(-450, 6)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)
	# the cup totals and the buttons, bottom right
	var side := UiKit.panel(Vector2(380, 0))
	side.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	side.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	side.grow_vertical = Control.GROW_DIRECTION_BEGIN
	side.position = Vector2(-24, -24)
	add_child(side)
	_side = side
	var box: VBoxContainer = UiKit.vbox(6)
	side.add_child(box)
	box.add_child(UiKit.label("CUP TOTALS", 16, UiKit.TEAL))
	if rules.is_team():
		var tt: Array[int] = PartyRules.team_totals(rules.cup, rules.teams)
		box.add_child(UiKit.label("%s  %d   :   %d  %s" % [PartyNames.team_name(0), tt[0], tt[1], PartyNames.team_name(1)], 22, Color.WHITE))
	var rank: int = 0
	for e: Variant in rules.cup_standings():
		rank += 1
		if rank > 8:
			break
		var id: int = int((e as Array)[0])
		var row: HBoxContainer = UiKit.hbox(10)
		var name_col: Color = Color.WHITE
		if rules.is_team():
			name_col = PartyNames.team_color(int(rules.teams.get(id, 0))).lerp(Color.WHITE, 0.3)
		var l1: Label = UiKit.label("%d." % rank, 18, UiKit.GOLD if rank == 1 else UiKit.SOFT)
		l1.custom_minimum_size = Vector2(28, 0)
		row.add_child(l1)
		var l2: Label = UiKit.label(str(rules.names.get(id, "?")) + ("  (you)" if id == Net.my_id() else ""), 18, name_col)
		l2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l2)
		row.add_child(UiKit.label(str(int((e as Array)[1])), 18, UiKit.GOLD, HORIZONTAL_ALIGNMENT_RIGHT))
		box.add_child(row)
	if host:
		var lobby: Button = UiKit.button("Back to the Lobby", on_lobby, 340)
		lobby.name = "PodiumLobby"
		box.add_child(lobby)
		_buttons.append(lobby)
		first = lobby
		var close: Button = UiKit.confirm_button("Close Session", "Press again to disconnect all", on_leave, 340)
		box.add_child(close)
		_buttons.append(close)
	else:
		var leave: Button = UiKit.confirm_button("Leave Party", "Press again to leave", on_leave, 340)
		leave.name = "PodiumLeave"
		box.add_child(leave)
		_buttons.append(leave)
		first = leave
		box.add_child(UiKit.label("The host takes you back to the lobby.", 14, UiKit.SOFT))
	side.modulate.a = 0.0
	for b: BaseButton in _buttons:
		b.disabled = true


# ---- the reveal ------------------------------------------------------------------------------------------------

func start() -> void:
	t = 0.0
	if sfx != null:
		sfx.play("drum", 0.9)


func _process(dt: float) -> void:
	for id: Variant in racers:
		var r: RemoteRacer = racers[id]
		if is_instance_valid(r):
			r.visual().animate(dt, Vector3.ZERO, true, Vector3(0, 0, 1))
	if done:
		return
	t += dt
	_reveal_step()
	if t >= UI_AT:
		_finish()


func _reveal_step() -> void:
	var at: Array[float] = [REVEAL_1ST, REVEAL_2ND, REVEAL_3RD]
	for i: int in mini(shown.size(), 3):
		if not _revealed[i] and t >= at[i]:
			_reveal(i)
	if _side != null:
		_side.modulate.a = clampf((t - REVEAL_1ST - 0.4) / 0.6, 0.0, 1.0)


func _reveal(i: int) -> void:
	_revealed[i] = true
	var holder: Node3D = _pedestals[i]
	holder.visible = true
	PartyFx.pop_in(holder, 0.5)
	var top: Vector3 = holder.position + Vector3(0, PEDESTAL_H[i] + 0.2, 0)
	PartyFx.burst(_stage, top, Color(1.0, 0.9, 0.5), 24, 4.0, 0.2, 0.7)
	if i == 0:
		_banner.text = str(shown[0]["label"]).to_upper()
		_banner.add_theme_color_override("font_color", (shown[0]["color"] as Color).lerp(UiKit.GOLD, 0.5))
		_banner.pivot_offset = _banner.size * 0.5
		_banner.scale = Vector2.ONE * 1.6
		create_tween().tween_property(_banner, "scale", Vector2.ONE, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if sfx != null:
			sfx.play("champion", 1.0)
		_confetti(top)
		# the champion's victory pose
		for id: Variant in (shown[0]["ids"] as Array):
			var r: RemoteRacer = racers.get(int(id))
			if r != null:
				var entry: Dictionary = roster.get(int(id), {})
				r.visual().play_pose(Cosmetics.clean("pose", entry.get("pose")), true, 0.2, false)
	elif sfx != null:
		sfx.play("pickup", 0.8, 1.0 + 0.2 * float(i))


func _confetti(top: Vector3) -> void:
	if _fx_done:
		return
	_fx_done = true
	for x: float in [-3.0, 0.0, 3.0]:
		PartyFx.confetti(_stage, Vector3(x, 5.0, 1.0), 70, 5.0, Vector3.DOWN, 70.0, 3.5)
	PartyFx.confetti(_stage, top + Vector3(0, 0.5, 0), 90, 8.0, Vector3.UP, 60.0, 2.4)
	PartyFx.star_ring(_stage, top + Vector3(0, 1.0, 0), Color(1.0, 0.9, 0.4), 12, 5.0, 0.4)


func _finish() -> void:
	if done:
		return
	done = true
	for i: int in mini(shown.size(), 3):
		if not _revealed[i]:
			_reveal(i)
	_side.modulate.a = 1.0
	for b: BaseButton in _buttons:
		b.disabled = false
	if is_instance_valid(first) and first.is_inside_tree():
		first.grab_focus()


func skip() -> void:
	if not done:
		t = UI_AT
		_reveal_step()
		_finish()


## A press while the reveal plays skips it (the press still navigates afterwards).
func _input(event: InputEvent) -> void:
	if done or t < 0.3:
		return
	if event.is_action_pressed("ui_accept") or event.is_action_pressed("ui_cancel") or event.is_action_pressed("ui_up") \
			or event.is_action_pressed("ui_down") or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed):
		skip()

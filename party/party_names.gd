class_name PartyNames
extends RefCounted
## EVERY player-facing name in Party Mode lives in this one table, so the owner can
## rename any mode, team, power-up or move in one place. (Nods, not trademarks: the
## game is published on GitHub.)

const MODES: Dictionary = {
	"race": "Race",
	"party": "Party",
	"team": "Team Party",
	"practice": "Party Practice",
}

const MODE_BLURBS: Dictionary = {
	"race": "The classic race. No items, no bumping - just the course.",
	"party": "Free-for-all. Item boxes, power-ups, shoving. Points for placing and for KOs.",
	"team": "Two teams. Same chaos, but your team's points are added together.",
	"practice": "Solo. Every item box gives the next power-up, and practice dummies take the hits.",
}

const CUP: String = "Party Cup"

const TEAMS: Array[String] = ["Blaze", "Tide"]
const TEAM_COLORS: Array[Color] = [Color(1.0, 0.38, 0.28), Color(0.3, 0.62, 1.0)]

## id -> display name, one-line description (HUD / practice), icon colour.
const ITEMS: Dictionary = {
	"fox": {"name": "Nine-Tailed Fox", "desc": "Blazing speed and huge jumps. Tap Attack: Claw (KO). Hold: Tailed Beast Bomb.", "color": Color(1.0, 0.5, 0.1)},
	"tunic": {"name": "Hero's Tunic", "desc": "Attack: Legend Blade (hold to spin). Use: throw the current tool. Cycle: next tool.", "color": Color(0.25, 0.8, 0.3)},
	"surge": {"name": "Golden Surge Hair", "desc": "Faster, double jump. Tap Attack: Dash Punch. Hold: charge the Energy Wave.", "color": Color(1.0, 0.86, 0.2)},
	"thunder": {"name": "Thunder Cloud", "desc": "Zaps every rival ahead of you: stunned and slowed.", "color": Color(0.6, 0.65, 1.0)},
	"slick": {"name": "Slick Puddle", "desc": "Drops a puddle behind you. Rivals who step in it spin out.", "color": Color(0.95, 0.85, 0.2)},
	"glove": {"name": "Spring Glove", "desc": "A boxing glove on a spring punches the rival in front of you.", "color": Color(1.0, 0.25, 0.25)},
	"magnet": {"name": "Mega Magnet", "desc": "For a few seconds, drags nearby rivals toward you - and off ledges.", "color": Color(0.9, 0.2, 0.3)},
	"shrink": {"name": "Shrink Ray", "desc": "Shrinks the rival in front: slower, weaker jumps, easier to bump.", "color": Color(0.95, 0.45, 1.0)},
	"swap": {"name": "Swap Warp", "desc": "Trade places with the racer directly ahead of you.", "color": Color(0.4, 1.0, 0.85)},
	"balloon": {"name": "Balloon Shield", "desc": "Soaks up the next hit and bounces it back at the attacker.", "color": Color(1.0, 0.55, 0.75)},
	"jetpack": {"name": "Jetpack", "desc": "A rocket burst up and forward, then a slow floaty glide. Hold Jump to thrust.", "color": Color(1.0, 0.62, 0.3)},
	"tornado": {"name": "Tornado", "desc": "Releases a tornado that wanders up the course flinging rivals.", "color": Color(0.7, 0.85, 0.9)},
	"gravity": {"name": "Gravity Bomb", "desc": "Thrown. Rivals caught in the blast float helplessly.", "color": Color(0.65, 0.35, 1.0)},
	"ice": {"name": "Ice Beam", "desc": "Freezes the rival in front of you in a block of ice.", "color": Color(0.55, 0.9, 1.0)},
}

## Named moves inside the transformations.
const MOVES: Dictionary = {
	"shove": "Shove",
	"claw": "Fox Claw",
	"beast_bomb": "Tailed Beast Bomb",
	"blade": "Legend Blade",
	"spin": "Spin Attack",
	"boomerang": "Boomerang",
	"hookshot": "Hookshot",
	"bombs": "Bombs",
	"dash_punch": "Dash Punch",
	"wave": "Energy Wave",
}

## Energy Wave charge chant, shown as the charge builds, then the release shout.
const WAVE_CHANT: Array[String] = ["Ka...", "Ka... me...", "Ka... me... ha...", "Ka... me... ha... me..."]
const WAVE_SHOUT: String = "WAVE!"


static func item_name(id: String) -> String:
	return str((ITEMS.get(id, {}) as Dictionary).get("name", id))


static func item_desc(id: String) -> String:
	return str((ITEMS.get(id, {}) as Dictionary).get("desc", ""))


static func item_color(id: String) -> Color:
	return (ITEMS.get(id, {}) as Dictionary).get("color", Color.WHITE)


static func move_name(id: String) -> String:
	return str(MOVES.get(id, id))


static func mode_name(id: String) -> String:
	return str(MODES.get(id, id))


static func team_name(team: int) -> String:
	return TEAMS[clampi(team, 0, TEAMS.size() - 1)]


static func team_color(team: int) -> Color:
	return TEAM_COLORS[clampi(team, 0, TEAM_COLORS.size() - 1)]

extends Node
## Local progress (user://progress.json): completion flags and personal bests.

const PATH: String = "user://progress.json"
## Course layout revision per level id. Bump a level's number when its course is
## rebuilt: bests set on an older layout move to "legacy_best" on load, because
## they can no longer be beaten or compared (unlocks and run counts are kept).
## Ids not listed here (the playground) are rev 1.
const LAYOUT_REV: Dictionary = {"gardens": 3, "foundry": 3, "balance": 3, "clockwork": 3, "reef": 1, "orbital": 1, "ascent": 3}

var data: Dictionary = {"levels": {}, "game_completed": false}
## Tests point this somewhere else so they never touch a real save.
var path_override: String = ""


func _ready() -> void:
	load_data()


func _path() -> String:
	return PATH if path_override == "" else path_override


## Loads the save, falling back to the backup copy when the main file is damaged.
## Whatever is read is sanitized, so a hand-edited file can't break the accessors.
func load_data() -> void:
	data = {"levels": {}, "game_completed": false}
	var main: String = _path()
	var parsed: Variant = _read_dict(main)
	# read but not a valid save (a file that merely couldn't be opened is left alone):
	# keep the evidence, and stop the next save from backing it up over a good .bak
	if parsed == null and FileAccess.file_exists(main) and FileAccess.get_open_error() == OK:
		DirAccess.rename_absolute(ProjectSettings.globalize_path(main), ProjectSettings.globalize_path(main + ".corrupt"))
		push_warning("SaveData: %s is damaged; kept it as .corrupt and loading the backup" % main)
	if parsed == null:
		parsed = _read_dict(main + ".bak")
	if parsed != null:
		data = _sanitize(parsed as Dictionary)
		_migrate()


## The parsed file as a Dictionary, or null when it is missing or not valid JSON.
func _read_dict(p: String) -> Variant:
	if not FileAccess.file_exists(p):
		return null
	var f: FileAccess = FileAccess.open(p, FileAccess.READ)
	if f == null:
		return null
	var j := JSON.new()
	if j.parse(f.get_as_text()) != OK:
		return null
	return j.data if j.data is Dictionary else null


## Rebuilds the save keeping only fields of the expected types.
func _sanitize(v: Dictionary) -> Dictionary:
	var out: Dictionary = {"levels": {}, "game_completed": v.get("game_completed") is bool and bool(v["game_completed"])}
	var levels: Variant = v.get("levels")
	if not (levels is Dictionary):
		return out
	for key: Variant in (levels as Dictionary):
		var e: Variant = levels[key]
		if not (key is String) or not (e is Dictionary):
			continue
		var src: Dictionary = e
		var entry: Dictionary = {}
		if src.get("completed") is bool:
			entry["completed"] = src["completed"]
		for k: String in ["best", "legacy_best"]:
			if _is_num(src.get(k)) and float(src[k]) >= 0.0:
				entry[k] = float(src[k])
		for k: String in ["runs", "rev"]:
			if _is_num(src.get(k)):
				entry[k] = int(src[k])
		for k: String in ["fewest_falls", "legacy_fewest_falls"]:
			if _is_num(src.get(k)) and float(src[k]) >= 0.0:
				entry[k] = int(src[k])
		if src.get("splits") is Array:
			var splits: Array = []
			for s: Variant in (src["splits"] as Array):
				splits.append(float(s) if _is_num(s) else -1.0)
			entry["splits"] = splits
		out["levels"][key] = entry
	return out


static func _is_num(v: Variant) -> bool:
	return v is float or v is int


## Moves records set on an older course layout out of the way (see LAYOUT_REV).
## Only in memory: the next save writes it, so loading never rewrites the file.
func _migrate() -> void:
	for id: String in data["levels"]:
		var entry: Dictionary = data["levels"][id]
		var rev: int = int(LAYOUT_REV.get(id, 1))
		if int(entry.get("rev", 1)) == rev:
			continue
		if entry.has("best"):
			entry["legacy_best"] = entry["best"]
			entry.erase("best")
		if entry.has("fewest_falls"):
			entry["legacy_fewest_falls"] = entry["fewest_falls"]
			entry.erase("fewest_falls")
		entry.erase("splits")
		entry["rev"] = rev


## Writes to a temp file first and swaps it in only once it is complete, keeping
## the previous save as .bak - a crash or a full disk can't wipe the progress.
func save_data() -> void:
	var main: String = _path()
	var tmp: String = main + ".tmp"
	var f: FileAccess = FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_warning("SaveData: can't write %s" % tmp)
		return
	var ok: bool = f.store_string(JSON.stringify(data, "  "))
	ok = ok and f.get_error() == OK
	f.close()
	if not ok:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
		push_warning("SaveData: writing %s failed; kept the previous save" % tmp)
		return
	if FileAccess.file_exists(main):
		DirAccess.copy_absolute(ProjectSettings.globalize_path(main), ProjectSettings.globalize_path(main + ".bak"))
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(tmp), ProjectSettings.globalize_path(main)) != OK:
		push_warning("SaveData: couldn't replace %s" % main)


func is_completed(level_id: String) -> bool:
	return data["levels"].has(level_id) and bool(data["levels"][level_id].get("completed", false))


func best_time(level_id: String) -> float:
	if not data["levels"].has(level_id):
		return -1.0
	return float(data["levels"][level_id].get("best", -1.0))


## Returns true when this run is a new personal best. `splits` (run time at each
## checkpoint, -1 for skipped ones) is kept alongside the best time.
func record_finish(level_id: String, time: float, falls: int = -1, splits: Array = []) -> bool:
	var entry: Dictionary = data["levels"].get(level_id, {})
	var prev: float = float(entry.get("best", -1.0))
	# compared at the shown resolution, so a "new best" never reads the same as the old one
	var is_best: bool = prev < 0.0 or centiseconds(time) < centiseconds(prev)
	entry["completed"] = true
	entry["runs"] = int(entry.get("runs", 0)) + 1
	entry["rev"] = int(LAYOUT_REV.get(level_id, 1))
	if falls >= 0 and (not entry.has("fewest_falls") or falls < int(entry["fewest_falls"])):
		entry["fewest_falls"] = falls
	if is_best:
		entry["best"] = time
		if splits.is_empty():
			entry.erase("splits")
		else:
			entry["splits"] = splits.duplicate()
	data["levels"][level_id] = entry
	save_data()
	return is_best


func fewest_falls(level_id: String) -> int:
	if not data["levels"].has(level_id):
		return -1
	return int(data["levels"][level_id].get("fewest_falls", -1))


## Checkpoint times of the personal-best run ([] when there is none).
func best_splits(level_id: String) -> Array:
	if not data["levels"].has(level_id):
		return []
	var s: Variant = (data["levels"][level_id] as Dictionary).get("splits", [])
	return s if s is Array else []


func set_game_completed() -> void:
	data["game_completed"] = true
	save_data()


func wipe() -> void:
	delete_files()
	data = {"levels": {}, "game_completed": false}
	save_data()


## Removes the save and its backup/temp/corrupt siblings (tests clean up with this).
func delete_files() -> void:
	for suffix: String in ["", ".bak", ".tmp", ".corrupt"]:
		var p: String = _path() + suffix
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


## Whole hundredths of a second, as shown. The epsilon absorbs the float error that
## builds up summing 1/120 s ticks (60 s arrives as 59.9999999999972).
static func centiseconds(t: float) -> int:
	return floori(t * 100.0 + 0.000001)


## m:ss.cc, truncated like a stopwatch (never "0:60.00").
@warning_ignore("integer_division")
static func format_time(t: float) -> String:
	if t < 0.0:
		return "--:--.--"
	var cs: int = centiseconds(t)
	return "%d:%02d.%02d" % [cs / 6000, (cs / 100) % 60, cs % 100]

extends Node
## Local progress (user://progress.json): completion flags and personal bests.

const PATH: String = "user://progress.json"

var data: Dictionary = {"levels": {}, "game_completed": false}
## Tests point this somewhere else so they never touch a real save.
var path_override: String = ""


func _ready() -> void:
	load_data()


func _path() -> String:
	return PATH if path_override == "" else path_override


func load_data() -> void:
	data = {"levels": {}, "game_completed": false}
	if not FileAccess.file_exists(_path()):
		return
	var f: FileAccess = FileAccess.open(_path(), FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if parsed is Dictionary and (parsed as Dictionary).has("levels"):
		data = parsed


func save_data() -> void:
	var f: FileAccess = FileAccess.open(_path(), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(data, "  "))


func is_completed(level_id: String) -> bool:
	return data["levels"].has(level_id) and bool(data["levels"][level_id].get("completed", false))


func best_time(level_id: String) -> float:
	if not data["levels"].has(level_id):
		return -1.0
	return float(data["levels"][level_id].get("best", -1.0))


## Returns true when this run is a new personal best.
func record_finish(level_id: String, time: float, falls: int = -1) -> bool:
	var entry: Dictionary = data["levels"].get(level_id, {})
	var prev: float = float(entry.get("best", -1.0))
	var is_best: bool = prev < 0.0 or time < prev
	entry["completed"] = true
	entry["runs"] = int(entry.get("runs", 0)) + 1
	if falls >= 0 and (not entry.has("fewest_falls") or falls < int(entry["fewest_falls"])):
		entry["fewest_falls"] = falls
	if is_best:
		entry["best"] = time
	data["levels"][level_id] = entry
	save_data()
	return is_best


func fewest_falls(level_id: String) -> int:
	if not data["levels"].has(level_id):
		return -1
	return int(data["levels"][level_id].get("fewest_falls", -1))


func set_game_completed() -> void:
	data["game_completed"] = true
	save_data()


func wipe() -> void:
	data = {"levels": {}, "game_completed": false}
	save_data()


static func format_time(t: float) -> String:
	if t < 0.0:
		return "--:--.--"
	var m: int = int(t) / 60
	return "%d:%05.2f" % [m, t - float(m * 60)]

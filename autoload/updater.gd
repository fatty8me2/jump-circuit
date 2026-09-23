extends Node
## Update check: once per launch, asks GitHub for the latest release of the game's
## repository and compares its tag (vMAJOR.MINOR.PATCH) with this build's
## application/config/version. A newer one sets `available` and emits
## update_available; the title screen then offers to open the release page.
## Silent on any failure (offline, rate limit, odd tag) - it never blocks play.
## Release tags without a version number (e.g. test builds) are ignored.

signal update_available(info: Dictionary)

const REPO: String = "fatty8me2/jump-circuit"
const API_URL: String = "https://api.github.com/repos/%s/releases/latest"
const PREFS_PATH: String = "user://update.cfg"
const TIMEOUT_S: float = 8.0

## {version, tag, url, name, notes} of a newer release, or empty.
var available: Dictionary = {}
## True once the prompt has been shown this launch (it only nags once).
var prompted: bool = false

var _http: HTTPRequest


func _ready() -> void:
	# never from automated runs, tools or the headless test suite
	if DisplayServer.get_name() == "headless":
		return
	for a: String in OS.get_cmdline_user_args():
		if a == "--no-update-check":
			return
	check()


func current_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))


func check() -> void:
	if _http != null:
		return
	_http = HTTPRequest.new()
	_http.timeout = TIMEOUT_S
	add_child(_http)
	_http.request_completed.connect(_on_response)
	var headers: PackedStringArray = ["User-Agent: JumpCircuit/%s" % current_version(), "Accept: application/vnd.github+json"]
	if _http.request(API_URL % REPO, headers) != OK:
		_done()


func _on_response(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_done()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var data: Variant = JSON.parse_string(body.get_string_from_utf8())
	if not (data is Dictionary):
		return
	var info: Dictionary = parse_release(data as Dictionary)
	if info.is_empty() or compare_versions(str(info["version"]), current_version()) <= 0:
		return
	if str(info["version"]) == skipped_version():
		return
	available = info
	update_available.emit(info)


func _done() -> void:
	if _http != null:
		_http.queue_free()
		_http = null


## Pulls what the prompt needs out of a GitHub release JSON; {} when the tag has no version.
static func parse_release(rel: Dictionary) -> Dictionary:
	if bool(rel.get("draft", false)) or bool(rel.get("prerelease", false)):
		return {}
	var tag: String = str(rel.get("tag_name", ""))
	var version: String = version_from_tag(tag)
	if version == "":
		return {}
	var notes: String = str(rel.get("body", "")).strip_edges()
	if notes.length() > 600:
		notes = notes.left(600).strip_edges() + " ..."
	return {"version": version, "tag": tag, "url": str(rel.get("html_url", "https://github.com/%s/releases/latest" % REPO)),
		"name": str(rel.get("name", tag)), "notes": notes}


## "v1.2.0" / "1.2" / "jump-circuit-v1.2.3" -> "1.2.0" / "1.2.0" / "1.2.3"; "" when there is none.
static func version_from_tag(tag: String) -> String:
	var re := RegEx.new()
	re.compile("(?:^|[^0-9.])v?(\\d+)\\.(\\d+)(?:\\.(\\d+))?(?:$|[^0-9.])")
	var m: RegExMatch = re.search(tag)
	if m == null:
		return ""
	var patch: String = m.get_string(3) if m.get_string(3) != "" else "0"
	return "%d.%d.%d" % [int(m.get_string(1)), int(m.get_string(2)), int(patch)]


## -1 / 0 / 1 like a comparator, numeric per part ("1.10.0" > "1.9.3").
static func compare_versions(a: String, b: String) -> int:
	var pa: PackedStringArray = a.split(".")
	var pb: PackedStringArray = b.split(".")
	for i: int in maxi(pa.size(), pb.size()):
		var x: int = int(pa[i]) if i < pa.size() else 0
		var y: int = int(pb[i]) if i < pb.size() else 0
		if x != y:
			return 1 if x > y else -1
	return 0


func open_download() -> void:
	if not available.is_empty():
		OS.shell_open(str(available["url"]))


## "Skip this version": no prompt again until a newer one than this is released.
func skip_version() -> void:
	if available.is_empty():
		return
	var cfg := ConfigFile.new()
	cfg.set_value("update", "skipped", str(available["version"]))
	cfg.save(PREFS_PATH)
	available = {}


func skipped_version() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(PREFS_PATH) != OK:
		return ""
	return str(cfg.get_value("update", "skipped", ""))

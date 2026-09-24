extends Node
## Checks GitHub for a newer version and installs its Windows ZIP beside the running game.
## The installed version, saves, and settings are kept in their existing locations.

signal update_available(info: Dictionary)
signal install_status_changed(message: String)
signal install_progress(downloaded_bytes: int, total_bytes: int)
signal install_failed(message: String)

const REPO: String = "fatty8me2/jump-circuit"
const API_URL: String = "https://api.github.com/repos/%s/releases/latest"
const PREFS_PATH: String = "user://update.cfg"
const CHECK_TIMEOUT_S: float = 8.0
const DOWNLOAD_TIMEOUT_S: float = 240.0
const REQUIRED_UPDATE_FILES: Array[String] = ["JumpCircuit.exe", "JumpCircuit.pck", "LICENSES.md"]

const WINDOWS_INSTALLER_SCRIPT: String = """
param(
    [int]$WaitForPid,
    [string]$ZipPath,
    [string]$InstallDir,
    [string]$GamePath,
    [string]$Version
)
$ErrorActionPreference = "Stop"
$stage = Join-Path $env:TEMP ("JumpCircuit-update-" + [guid]::NewGuid().ToString("N"))
$backup = Join-Path $stage "backup"
$files = @("JumpCircuit.pck", "LICENSES.md", "JumpCircuit.exe")
try {
    try { Wait-Process -Id $WaitForPid -ErrorAction Stop } catch { }
    New-Item -ItemType Directory -Path $stage -Force | Out-Null
    Expand-Archive -LiteralPath $ZipPath -DestinationPath $stage -Force
    foreach ($name in $files) {
        if (-not (Test-Path -LiteralPath (Join-Path $stage $name) -PathType Leaf)) {
            throw ("The update archive is missing " + $name)
        }
    }
    New-Item -ItemType Directory -Path $backup -Force | Out-Null
    foreach ($name in $files) {
        $destination = Join-Path $InstallDir $name
        if (Test-Path -LiteralPath $destination -PathType Leaf) {
            Copy-Item -LiteralPath $destination -Destination (Join-Path $backup $name) -Force
        }
    }
    try {
        foreach ($name in $files) {
            Copy-Item -LiteralPath (Join-Path $stage $name) -Destination (Join-Path $InstallDir $name) -Force
        }
        Start-Process -FilePath $GamePath -WorkingDirectory $InstallDir
    } catch {
        foreach ($name in $files) {
            $destination = Join-Path $InstallDir $name
            $oldFile = Join-Path $backup $name
            try {
                if (Test-Path -LiteralPath $oldFile -PathType Leaf) {
                    Copy-Item -LiteralPath $oldFile -Destination $destination -Force
                } elseif (Test-Path -LiteralPath $destination -PathType Leaf) {
                    Remove-Item -LiteralPath $destination -Force
                }
            } catch { }
        }
        throw
    }
    Remove-Item -LiteralPath $ZipPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
} catch {
    $message = "Could not install Jump Circuit v" + $Version + ": " + $_.Exception.Message + "`nThe previous version will be opened."
    try {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show($message, "Jump Circuit Update", "OK", "Error") | Out-Null
    } catch { }
    Remove-Item -LiteralPath $ZipPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path -LiteralPath $GamePath -PathType Leaf) {
        Start-Process -FilePath $GamePath -WorkingDirectory $InstallDir
    }
}
"""

## {version, tag, url, name, notes, download_url, asset_name, asset_size, asset_digest} or empty.
var available: Dictionary = {}
## True while downloading or handing the install off to Windows.
var installing: bool = false
## True once the update prompt has been shown this launch.
var prompted: bool = false

var _http: HTTPRequest
var _download_http: HTTPRequest
var _download_path: String = ""
var _last_progress_bytes: int = -1


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		return
	for argument: String in OS.get_cmdline_user_args():
		if argument == "--no-update-check":
			return
	check()


func _process(_delta: float) -> void:
	if _download_http == null:
		return
	var downloaded: int = _download_http.get_downloaded_bytes()
	if downloaded == _last_progress_bytes:
		return
	_last_progress_bytes = downloaded
	var total: int = _download_http.get_body_size()
	if total <= 0:
		total = int(available.get("asset_size", 0))
	install_progress.emit(downloaded, total)


func current_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))


func check() -> void:
	if _http != null or installing:
		return
	_http = HTTPRequest.new()
	_http.timeout = CHECK_TIMEOUT_S
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


## Requires the versioned Windows ZIP so the client can install without opening a browser.
static func parse_release(rel: Dictionary) -> Dictionary:
	if bool(rel.get("draft", false)) or bool(rel.get("prerelease", false)):
		return {}
	var tag: String = str(rel.get("tag_name", ""))
	var version: String = version_from_tag(tag)
	if version == "":
		return {}
	var expected_asset: String = "JumpCircuit-v%s.zip" % version
	var download_url: String = ""
	var asset_size: int = 0
	var asset_digest: String = ""
	var assets: Variant = rel.get("assets", [])
	if assets is Array:
		for item: Variant in assets:
			if not (item is Dictionary):
				continue
			var asset: Dictionary = item as Dictionary
			if str(asset.get("name", "")) != expected_asset:
				continue
			download_url = str(asset.get("browser_download_url", ""))
			asset_size = int(asset.get("size", 0))
			asset_digest = str(asset.get("digest", ""))
			break
	var expected_prefix: String = "https://github.com/%s/releases/download/" % REPO
	if not download_url.begins_with(expected_prefix) or asset_size <= 0:
		return {}
	var notes: String = str(rel.get("body", "")).strip_edges()
	if notes.length() > 600:
		notes = notes.left(600).strip_edges() + " ..."
	return {
		"version": version,
		"tag": tag,
		"url": str(rel.get("html_url", "")),
		"name": str(rel.get("name", tag)),
		"notes": notes,
		"download_url": download_url,
		"asset_name": expected_asset,
		"asset_size": asset_size,
		"asset_digest": asset_digest,
	}


## "v1.2.0" / "1.2" / "jump-circuit-v1.2.3" -> "1.2.0" / "1.2.0" / "1.2.3".
static func version_from_tag(tag: String) -> String:
	var re := RegEx.new()
	re.compile("(?:^|[^0-9.])v?(\\d+)\\.(\\d+)(?:\\.(\\d+))?(?:$|[^0-9.])")
	var match: RegExMatch = re.search(tag)
	if match == null:
		return ""
	var patch: String = match.get_string(3) if match.get_string(3) != "" else "0"
	return "%d.%d.%d" % [int(match.get_string(1)), int(match.get_string(2)), int(patch)]


## -1 / 0 / 1 like a comparator ("1.10.0" > "1.9.3").
static func compare_versions(a: String, b: String) -> int:
	var parts_a: PackedStringArray = a.split(".")
	var parts_b: PackedStringArray = b.split(".")
	for index: int in maxi(parts_a.size(), parts_b.size()):
		var value_a: int = int(parts_a[index]) if index < parts_a.size() else 0
		var value_b: int = int(parts_b[index]) if index < parts_b.size() else 0
		if value_a != value_b:
			return 1 if value_a > value_b else -1
	return 0


func install_update() -> void:
	if installing or available.is_empty():
		return
	if OS.get_name() != "Windows":
		_fail_install("Automatic installation is available in the Windows game build.")
		return
	var executable: String = OS.get_executable_path()
	if executable.get_file().to_lower() != "jumpcircuit.exe":
		_fail_install("Launch JumpCircuit.exe to install updates automatically.")
		return
	var download_url: String = str(available.get("download_url", ""))
	if not download_url.begins_with("https://github.com/%s/releases/download/" % REPO):
		_fail_install("The update download is unavailable. Try again later.")
		return
	var updates_dir: String = ProjectSettings.globalize_path("user://updates")
	if not DirAccess.dir_exists_absolute(updates_dir):
		var make_dir_error: Error = DirAccess.make_dir_recursive_absolute(updates_dir)
		if make_dir_error != OK and not DirAccess.dir_exists_absolute(updates_dir):
			_fail_install("Could not create the update download folder.")
			return
	_download_path = updates_dir.path_join("JumpCircuit-v%s-%d.zip" % [available["version"], Time.get_ticks_msec()])
	_download_http = HTTPRequest.new()
	_download_http.timeout = DOWNLOAD_TIMEOUT_S
	_download_http.body_size_limit = -1
	_download_http.download_file = _download_path
	_download_http.request_completed.connect(_on_download_completed)
	add_child(_download_http)
	installing = true
	_last_progress_bytes = -1
	install_status_changed.emit("Connecting to the update server...")
	var headers: PackedStringArray = ["User-Agent: JumpCircuit/%s" % current_version(), "Accept: application/octet-stream"]
	var request_error: Error = _download_http.request(download_url, headers)
	if request_error != OK:
		_fail_install("Could not start the update download.")


func _on_download_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	var request: HTTPRequest = _download_http
	_download_http = null
	if request != null:
		request.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_fail_install("The update download failed (HTTP %d). Check your connection and retry." % response_code)
		return
	install_status_changed.emit("Checking the downloaded update...")
	if not _verify_download():
		_fail_install("The downloaded update failed its integrity check. Please retry.")
		return
	if not _archive_has_game_files():
		_fail_install("The downloaded update is missing required game files.")
		return
	if not _start_windows_installer():
		return
	install_status_changed.emit("Installing v%s and restarting..." % available["version"])
	get_tree().quit()


func _verify_download() -> bool:
	var file: FileAccess = FileAccess.open(_download_path, FileAccess.READ)
	if file == null:
		return false
	var expected_size: int = int(available.get("asset_size", 0))
	var actual_size: int = file.get_length()
	file.close()
	if expected_size > 0 and actual_size != expected_size:
		return false
	var digest: String = str(available.get("asset_digest", ""))
	if digest == "":
		return true
	if not digest.begins_with("sha256:"):
		return false
	return _sha256_file(_download_path) == digest.substr(7).to_lower()


func _sha256_file(path: String) -> String:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		file.close()
		return ""
	while file.get_position() < file.get_length():
		var remaining: int = file.get_length() - file.get_position()
		var chunk: PackedByteArray = file.get_buffer(mini(1024 * 1024, remaining))
		if chunk.is_empty() or context.update(chunk) != OK:
			file.close()
			return ""
	file.close()
	return context.finish().hex_encode().to_lower()


func _archive_has_game_files() -> bool:
	var archive := ZIPReader.new()
	if archive.open(_download_path) != OK:
		return false
	var files: PackedStringArray = archive.get_files()
	if files.size() != REQUIRED_UPDATE_FILES.size():
		archive.close()
		return false
	for expected_file: String in REQUIRED_UPDATE_FILES:
		if not files.has(expected_file):
			archive.close()
			return false
	archive.close()
	return true


func _start_windows_installer() -> bool:
	var updates_dir: String = _download_path.get_base_dir()
	var script_path: String = updates_dir.path_join("install_update.ps1")
	var script_file: FileAccess = FileAccess.open(script_path, FileAccess.WRITE)
	if script_file == null:
		_fail_install("Could not prepare the update installer.")
		return false
	script_file.store_string(WINDOWS_INSTALLER_SCRIPT)
	script_file.close()
	var executable: String = OS.get_executable_path()
	var powershell: String = OS.get_environment("WINDIR").path_join("System32/WindowsPowerShell/v1.0/powershell.exe")
	if not FileAccess.file_exists(powershell):
		powershell = "powershell.exe"
	var arguments := PackedStringArray([
		"-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden", "-ExecutionPolicy", "Bypass",
		"-File", _quote_windows_argument(script_path),
		"-WaitForPid", str(OS.get_process_id()),
		"-ZipPath", _quote_windows_argument(_download_path),
		"-InstallDir", _quote_windows_argument(executable.get_base_dir()),
		"-GamePath", _quote_windows_argument(executable),
		"-Version", str(available["version"]),
	])
	if OS.create_process(powershell, arguments, false) <= 0:
		_fail_install("Could not start the Windows update installer.")
		return false
	return true


func _quote_windows_argument(value: String) -> String:
	return "\"%s\"" % value.replace("\"", "\\\"")


func _fail_install(message: String) -> void:
	installing = false
	if _download_http != null:
		_download_http.cancel_request()
		_download_http.queue_free()
		_download_http = null
	install_status_changed.emit(message)
	install_failed.emit(message)


## "Skip this version": no prompt again until a newer one is released.
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

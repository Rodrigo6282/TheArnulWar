extends Node
## Update check against the GitHub Releases of the project. At start-up it asks for the latest
## release; if its version is newer than ours, the MULTIJUGADOR screen offers to update (online
## games need the same version on every PC: net.gd rejects different versions in `hello`).
## Updating downloads the installer asset to user://, launches it and closes the game.

signal found
signal progress(done: int, total: int)
signal failed(msg: String)

const API := "https://api.github.com/repos/Rodrigo6282/TheArnulWar/releases/latest"

var current := ""
var latest := ""
var installer_url := ""
var installer_size := 0
var page_url := ""
var newer := false
var dismissed := false
var downloading := false
var _req: HTTPRequest
var _dl: HTTPRequest
var _path := ""


static func ver_cmp(a: String, b: String) -> int:
	var pa := a.trim_prefix("v").split(".")
	var pb := b.trim_prefix("v").split(".")
	for i in maxi(pa.size(), pb.size()):
		var x := int(pa[i]) if i < pa.size() else 0
		var y := int(pb[i]) if i < pb.size() else 0
		if x != y:
			return 1 if x > y else -1
	return 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	current = str(ProjectSettings.get_setting("application/config/version", "0"))
	var args := OS.get_cmdline_user_args()
	# --fakever=1.0 pretends to be an old version (to test the update window)
	for a in args:
		if a.begins_with("--fakever="):
			current = a.get_slice("=", 1)
			check()
			return
	# no network calls from the automated checks
	for a in args:
		if a.begins_with("--autotest") or a.begins_with("--shot") or a.begins_with("--perf") or a.begins_with("--mptest") or a == "--noupdate":
			return
	check()


func check() -> void:
	if _req:
		return
	_req = HTTPRequest.new()
	_req.timeout = 15.0
	add_child(_req)
	_req.request_completed.connect(_on_checked)
	_req.request(API, ["User-Agent: TheArnulWar-updater", "Accept: application/vnd.github+json"])


func _on_checked(result: int, code: int, _h: PackedStringArray, body: PackedByteArray) -> void:
	_req.queue_free()
	_req = null
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var d = JSON.parse_string(body.get_string_from_utf8())
	if not (d is Dictionary):
		return
	latest = str(d.get("tag_name", "")).trim_prefix("v")
	page_url = str(d.get("html_url", ""))
	for a in d.get("assets", []):
		var nm := str(a.get("name", ""))
		if nm.to_lower().ends_with(".exe") and "instalador" in nm.to_lower():
			installer_url = str(a.get("browser_download_url", ""))
			installer_size = int(a.get("size", 0))
	newer = latest != "" and ver_cmp(latest, current) > 0
	if newer:
		found.emit()


## Download the installer, run it and quit (the installer replaces this version).
func download() -> void:
	if downloading:
		return
	if installer_url == "":
		OS.shell_open(page_url if page_url != "" else "https://github.com/Rodrigo6282/TheArnulWar/releases/latest")
		return
	downloading = true
	_path = OS.get_user_data_dir().path_join("TheArnulWar_%s_Instalador.exe" % latest)
	_dl = HTTPRequest.new()
	_dl.download_file = _path
	_dl.timeout = 0.0
	_dl.max_redirects = 10
	add_child(_dl)
	_dl.request_completed.connect(_on_downloaded)
	var err := _dl.request(installer_url, ["User-Agent: TheArnulWar-updater"])
	if err != OK:
		_fail("No se pudo iniciar la descarga.")


func _process(_d: float) -> void:
	if downloading and _dl:
		progress.emit(_dl.get_downloaded_bytes(), maxi(_dl.get_body_size(), installer_size))


func _on_downloaded(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
	_dl.queue_free()
	_dl = null
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or not FileAccess.file_exists(_path):
		_fail("La descarga falló. Comprueba tu conexión e inténtalo otra vez.")
		return
	var pid := OS.create_process(_path, [])
	if pid <= 0:
		_fail("No se pudo abrir el instalador. Está en: %s" % _path)
		return
	get_tree().quit()


func _fail(msg: String) -> void:
	downloading = false
	failed.emit(msg)

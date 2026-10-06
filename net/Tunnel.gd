class_name Tunnel
extends Node

## Gives a hosted game a public, secure (wss://) address with no router setup, using
## Cloudflare's free "quick tunnel" (the cloudflared tool, Apache-2.0 licensed).
## The tunnel's name is the room code: "brave-lemon-kite-maple" means
## wss://brave-lemon-kite-maple.trycloudflare.com. A new name every time you host.
## cloudflared is used from next to the game exe if present, else downloaded once into
## user:// from a pinned release and checked against its SHA-256 before it ever runs.

signal status_changed(text: String)
## live = true once a real connection got through; false if Cloudflare was too slow to
## confirm (the code usually starts working a minute later).
signal opened(room_code: String, live: bool)
signal failed(reason: String)

## Pinned so a future cloudflared release can't change behaviour under us. To update:
## take the new tag and its windows-amd64.exe sha256 from the GitHub release page.
const CLOUDFLARED_VERSION := "2026.10.0"
const CLOUDFLARED_SHA256 := "86aee4017b26625cee8484c113558f48effa4cd47f7aa05fcf425604e5d2b23c"
const DOWNLOAD_URL := "https://github.com/cloudflare/cloudflared/releases/download/%s/cloudflared-windows-amd64.exe" % CLOUDFLARED_VERSION
const BINARY_NAME := "cloudflared.exe"
const DOMAIN := ".trycloudflare.com"
## Seconds to wait for Cloudflare to hand out an address, then for it to answer.
const URL_TIMEOUT := 45.0
## Remembers the running tunnel's process id, so a tunnel left over from a crash
## (or the editor's Stop button) is shut down next time.
const PID_FILE := "user://cloudflared.pid"
const REACH_TIMEOUT := 60.0

var room_code: String = ""
var _pid: int = -1
var _generation: int = 0

## Quick tunnels need the cloudflared program, which this game runs on Windows.
static func is_supported() -> bool:
	return OS.get_name() == "Windows"

## "brave-lemon-kite-maple" -> "wss://brave-lemon-kite-maple.trycloudflare.com"
static func code_to_url(code: String) -> String:
	return "wss://%s%s" % [code.strip_edges().to_lower(), DOMAIN]

## Looks like a room code (several words joined by dashes, no dots or port)? Codes are
## 4 words; requiring 3+ words keeps PC names like DESKTOP-AB12 from counting.
static func is_room_code(text: String) -> bool:
	var t := text.strip_edges()
	return t.count("-") >= 2 and not "." in t and not ":" in t and not " " in t

## Start a tunnel to the local game server on `port`. Emits opened(code) or failed(reason).
func open(port: int) -> void:
	close()
	_generation += 1
	var generation := _generation
	var exe := await _find_or_download()
	if generation != _generation:
		return # closed while downloading
	if exe == "":
		failed.emit("Couldn't download Cloudflare's tunnel tool. Check your internet connection.")
		return
	_stop_leftover_tunnel()
	# A log per game run, so an older tunnel's address can never be read by mistake
	var log_name := "cloudflared-%d.log" % OS.get_process_id()
	_delete_old_logs(log_name)
	var log_path := ProjectSettings.globalize_path("user://" + log_name)
	DirAccess.remove_absolute(log_path)
	_pid = OS.create_process(exe, ["tunnel", "--no-autoupdate", "--url", "http://127.0.0.1:%d" % port, "--logfile", log_path])
	if _pid <= 0:
		failed.emit("Couldn't start Cloudflare's tunnel tool.")
		return
	var pid_file := FileAccess.open(PID_FILE, FileAccess.WRITE)
	if pid_file:
		pid_file.store_string(str(_pid))
	status_changed.emit("Getting a room code...")
	var url := await _wait_for_url(log_path, generation)
	if generation != _generation:
		return
	if url == "":
		close()
		failed.emit("Cloudflare didn't hand out a room code. Check your internet connection and try again.")
		return
	room_code = url.trim_prefix("https://").trim_suffix(DOMAIN)
	status_changed.emit("Opening the room...")
	var live := await _wait_until_reachable(url, generation)
	if generation == _generation:
		opened.emit(room_code, live)

func close() -> void:
	_generation += 1
	if _pid > 0:
		OS.kill(_pid)
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PID_FILE))
	_pid = -1
	room_code = ""

## Kills the tunnel a previous run left behind, only if that process id is still cloudflared.
func _stop_leftover_tunnel() -> void:
	if not FileAccess.file_exists(PID_FILE):
		return
	var old_pid := FileAccess.get_file_as_string(PID_FILE).strip_edges().to_int()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PID_FILE))
	if old_pid <= 0:
		return
	# (OS.is_process_running only knows processes this run started, so ask Windows instead)
	var output: Array = []
	OS.execute("tasklist", ["/FI", "PID eq %d" % old_pid, "/FO", "CSV", "/NH"], output)
	if not output.is_empty() and BINARY_NAME in str(output[0]).to_lower():
		OS.kill(old_pid)

func _notification(what: int) -> void:
	# Don't leave cloudflared running after the game closes
	if what == NOTIFICATION_PREDELETE or what == NOTIFICATION_WM_CLOSE_REQUEST:
		close()

## Logs from earlier game runs are useless once those runs are gone.
func _delete_old_logs(keep: String) -> void:
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	for file in dir.get_files():
		if file.begins_with("cloudflared") and file.ends_with(".log") and file != keep:
			dir.remove(file)

func _find_or_download() -> String:
	# A copy shipped next to the game is the player's own choice; use it as is
	var beside := OS.get_executable_path().get_base_dir().path_join(BINARY_NAME)
	if FileAccess.file_exists(beside):
		return beside
	var cached := ProjectSettings.globalize_path("user://" + BINARY_NAME)
	if FileAccess.file_exists(cached):
		if FileAccess.get_sha256(cached) == CLOUDFLARED_SHA256:
			return cached
		DirAccess.remove_absolute(cached) # other version or damaged: fetch the pinned one
	var http := HTTPRequest.new()
	http.download_file = cached + ".part"
	http.max_redirects = 10
	add_child(http)
	var done := [false, 0, 0] # finished, result, http code
	http.request_completed.connect(func(result, code, _h, _b):
		done[0] = true
		done[1] = result
		done[2] = code)
	if http.request(DOWNLOAD_URL) != OK:
		http.queue_free()
		return ""
	while not done[0]:
		var total := http.get_body_size()
		var got := http.get_downloaded_bytes()
		status_changed.emit("Downloading Cloudflare's tunnel tool (one time only)... %s" % (
			"%d%%" % (100 * got / total) if total > 0 else "%d MB" % (got / 1048576)))
		await get_tree().create_timer(0.5).timeout
	http.queue_free()
	if done[1] != HTTPRequest.RESULT_SUCCESS or done[2] != 200 \
			or FileAccess.get_sha256(cached + ".part") != CLOUDFLARED_SHA256:
		DirAccess.remove_absolute(cached + ".part") # failed, or not the file we expect: never run it
		return ""
	DirAccess.rename_absolute(cached + ".part", cached)
	return cached

## cloudflared writes the public address into its log once the tunnel exists.
func _wait_for_url(log_path: String, generation: int) -> String:
	var pattern := RegEx.create_from_string("https://([a-z0-9-]+)\\.trycloudflare\\.com")
	var deadline := Time.get_ticks_msec() + int(URL_TIMEOUT * 1000.0)
	while Time.get_ticks_msec() < deadline and generation == _generation:
		if not OS.is_process_running(_pid):
			return ""
		var text := FileAccess.get_file_as_string(log_path)
		for found in pattern.search_all(text):
			if found.get_string(1) != "api": # cloudflared also logs its own API address
				return found.get_string()
		await get_tree().create_timer(0.25).timeout
	return ""

## A brand-new tunnel takes a while to go live (Cloudflare answers with its own error page
## until then). Waits until a real WebSocket connection gets through to the game, the same
## kind of connection a friend makes. Returns false if that didn't happen in time.
func _wait_until_reachable(url: String, generation: int) -> bool:
	var ws_url := url.replace("https://", "wss://")
	var deadline := Time.get_ticks_msec() + int(REACH_TIMEOUT * 1000.0)
	while Time.get_ticks_msec() < deadline and generation == _generation:
		var ws := WebSocketPeer.new()
		ws.handshake_timeout = 8.0
		if ws.connect_to_url(ws_url) == OK:
			var state := WebSocketPeer.STATE_CONNECTING
			while state == WebSocketPeer.STATE_CONNECTING:
				await get_tree().process_frame
				ws.poll()
				state = ws.get_ready_state()
			if state == WebSocketPeer.STATE_OPEN:
				ws.close()
				return true
		await get_tree().create_timer(2.0).timeout
	return false

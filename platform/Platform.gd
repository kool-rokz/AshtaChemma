class_name Platform
extends RefCounted

## The one place that knows which platform the game runs on. Everything that differs
## between desktop, web, phones and consoles goes through here, so a port swaps these
## and leaves the game alone:
##   - transport(): how players connect (WebSocket today; WebRTC, a relay, or a
##     console's own online service later)
##   - room_service(): how a host gets a room code (the Cloudflare tunnel, desktop only)
##   - storage(): where settings live (user:// files; a console's save data)
##   - system_player_name(): the platform account's name, when it has one
##   - invite_code() / read_clipboard() / paste hooks: links and pasting
##   - default_quality() / default_ui_scale() / is_handheld(): starting settings
## Game code never calls OS.create_process, opens a URL or a file path itself.

static var _storage: Storage
## Web: kept alive while JavaScript may call them.
static var _web_callbacks: Array[JavaScriptObject] = []
static var _web_paste_callback: JavaScriptObject

static func is_web() -> bool:
	return OS.has_feature("web")

static func is_mobile() -> bool:
	return OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")

## A small screen held in the hands (phones; a console's handheld mode later).
static func is_handheld() -> bool:
	return is_mobile()

# --- services ---
static func transport() -> Transport:
	return WebSocketTransport.new()

## null when this platform can't give out room codes.
static func room_service() -> RoomService:
	return Tunnel.new() if Tunnel.is_supported() else null

static func storage() -> Storage:
	if _storage == null:
		_storage = Storage.new()
	return _storage

## The name of the platform's signed-in account ("" = the player types a name).
## Consoles return the system nickname here, and the menu shows it read-only.
static func system_player_name() -> String:
	return ""

# --- starting settings ---
static func default_quality() -> String:
	return Settings.QUALITY_LOW if is_mobile() else Settings.QUALITY_HIGH

static func default_ui_scale() -> float:
	return 1.3 if is_handheld() else 1.0

# --- links and pasting ---
## Web invite links: .../index.html?room=brave-lemon-kite-maple gives that room code.
static func invite_code() -> String:
	if not is_web():
		return ""
	var room: Variant = JavaScriptBridge.eval("new URLSearchParams(window.location.search).get('room') || ''")
	return str(room).strip_edges() if room != null else ""

## Reads the clipboard and calls done(text). Web: the clipboard if the page may read it
## (not inside itch.io's frame), else the browser's own text box, where pasting always
## works. done is not called if the player cancels.
static func read_clipboard(done: Callable, prompt := "Paste here:") -> void:
	if not is_web():
		done.call(DisplayServer.clipboard_get())
		return
	var clipboard: Variant = JavaScriptBridge.get_interface("navigator").clipboard
	if clipboard == null:
		_ask_browser(done, prompt)
		return
	var on_text := JavaScriptBridge.create_callback(func(args: Array): done.call(str(args[0])))
	var on_error := JavaScriptBridge.create_callback(func(_args: Array): _ask_browser(done, prompt))
	_web_callbacks = [on_text, on_error]
	clipboard.readText().then(on_text, on_error)

static func _ask_browser(done: Callable, prompt: String) -> void:
	var typed: Variant = JavaScriptBridge.get_interface("window").prompt(prompt, "")
	if typed != null and str(typed).strip_edges() != "":
		done.call(str(typed))

## Godot's web runtime calls preventDefault() on every key press on its canvas, which
## also cancels the browser's paste. While a screen with text boxes is open, a capture
## listener lets Ctrl/Cmd+V through to the browser (Godot never sees it), and the
## "paste" event that follows calls on_paste(text). Other platforms paste natively.
const WEB_PASTE_HOOK := """
if (!window.ashtaPasteHook) {
	window.ashtaPasteHook = true;
	window.addEventListener('keydown', function (e) {
		if (window.ashtaPasteEnabled && (e.ctrlKey || e.metaKey) && (e.key === 'v' || e.key === 'V')) {
			e.stopImmediatePropagation();
		}
	}, true);
}
window.ashtaPasteEnabled = true;
"""

static func begin_paste_hook(on_paste: Callable) -> void:
	if not is_web():
		return
	end_paste_hook()
	JavaScriptBridge.eval(WEB_PASTE_HOOK)
	_web_paste_callback = JavaScriptBridge.create_callback(func(args: Array):
		var data: Variant = args[0].clipboardData
		if data != null:
			on_paste.call(str(data.getData("text"))))
	JavaScriptBridge.get_interface("window").addEventListener("paste", _web_paste_callback)

static func end_paste_hook() -> void:
	if not is_web():
		return
	JavaScriptBridge.eval("window.ashtaPasteEnabled = false;")
	if _web_paste_callback:
		JavaScriptBridge.get_interface("window").removeEventListener("paste", _web_paste_callback)
		_web_paste_callback = null

## Web: the browser's paste event does the pasting, so a Ctrl+V that still reaches Godot
## must be dropped (its own paste would use its internal clipboard, usually stale there).
static func is_native_paste_blocked(event: InputEvent) -> bool:
	return is_web() and event is InputEventKey and event.pressed and event.keycode == KEY_V \
		and (event.ctrl_pressed or event.meta_pressed)

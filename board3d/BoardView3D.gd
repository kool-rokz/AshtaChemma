class_name BoardView3D
extends Node3D

## The match as players see it: the board drawn in chalk on a mud courtyard, every pawn
## a Kondapalli figure, seen from the viewer's own side (camera "Seated 50°").
## A view only. It never changes the game:
##   - pawns: each figure follows its (hidden) 2D Pawn through a fixed board mapping, so
##     moves, stacking and timing are exactly the rules' own. Jumps the 2D pawns make in
##     one frame (a capture or Banish sending a pawn home, a swap) are shown as arcs.
##   - highlights: drawn from the board's TileHighlighter state (homebases, the inner
##     ring arrow, move preview, card targets, marked squares) and each Pawn's
##     is_highlighted / status_color, which BoardPresenter and the card UI decide.
##   - pointer: raycast onto the board and reported through Board.point_at / press_tile
##     and Pawn.point / press, the same signals 2D input used, so MatchController and
##     BoardPresenter work unchanged. Touch has no hover, so the first tap on a pawn or
##     square that can be picked previews it and a second tap picks it. Keyboard and pad
##     players pick with PadCursor; the square in focus gets a chalk ring.
##   - reactions: attack / celebrate / sad (see PawnFigure), from GameManager's signals.
## Disabled when headless (tests), like every view.

@export var game: GameManager
## Read only, for whose side to view from (local_seat; offline: whoever is playing).
@export var controller: MatchController

## Camera: degrees above the board, field of view, distance. "Seated 50°", aimed a little
## towards the viewer so the board sits above the hand of cards.
const PITCH := 50.0
const FOV := 38.0
const DISTANCE := 9.2
const AIM_SHIFT := 0.7
## A push-in for big moments (a capture, a win): "Low 35°", closer.
const CLOSE_PITCH := 35.0
const CLOSE_DISTANCE := 7.6
const CLOSE_HOLD := 1.4
const TURN_TIME := 0.9
const HOP_HEIGHT := 0.32
const TURN_SPEED := 10.0
## A pawn picked by the pointer must be this close (board units) to the pointed spot.
const PICK_RADIUS := 0.38
## Figures sharing a square shrink less than the 2D pawns do, to stay readable.
const STACK_SHRINK := 0.55
const MARK_GOLD := Color(1.0, 0.85, 0.4)
const LOCKED_GREY := Color(0.55, 0.52, 0.5)
const END_COLORS := {
	GameManager.MoveEnd.NORMAL: Color(1.0, 0.8, 0.3),
	GameManager.MoveEnd.SAFE: Color(0.3, 0.9, 0.95),
	GameManager.MoveEnd.CAPTURE: Color(1.0, 0.3, 0.25),
	GameManager.MoveEnd.HOME: Color(0.75, 0.5, 1.0),
}

var camera: Camera3D
var _enabled := false
var _lights: Dictionary
## Pawn -> PawnFigure
var _figures: Dictionary = {}
var _last_pos: Dictionary = {}
## Pawns whose figure is playing an arc (not following its 2D pawn for now).
var _animating: Dictionary = {}
## Pawn -> ring (movable) and Pawn -> dome (a lasting effect like Aegis)
var _rings: Dictionary = {}
var _domes: Dictionary = {}
## Chalk marks drawn from the highlighter state, by group, with what they were made from.
var _marks: Dictionary = {}
var _mark_keys: Dictionary = {}
var _view := {"pitch": PITCH, "yaw": 0.0, "distance": DISTANCE}
var _view_tween: Tween
var _side := -1
var _hovered_pawn: Pawn
## Pawn -> how high its figure was hopping last frame (a landing makes a step sound).
var _hop_height: Dictionary = {}
var _last_hello_msec := 0
## Touch: the square last tapped once (its preview showing, a second tap picks it).
var _tapped_tile := -1
var _celebrate_player := -1
var _origin_2d := Vector2.ZERO
var _tile_2d := 1.0

func _ready() -> void:
	_enabled = DisplayServer.get_name() != "headless" and game != null
	if not _enabled:
		return
	BoardWorld.add_floor(self)
	BoardWorld.add_chalk_board(self)
	_lights = BoardWorld.add_lighting(self, Settings.light())
	BoardWorld.apply_quality(_lights, get_viewport(), Settings.quality())
	camera = Camera3D.new()
	camera.fov = FOV
	add_child(camera)
	camera.make_current()
	get_viewport().size_changed.connect(_frame_for_aspect)
	_frame_for_aspect()
	game.board.external_pointer = true
	game.board.visible = false
	game.pawns_root.visible = false
	game.board.highlighter.changed.connect(_sync_marks)
	game.setup_done.connect(_spawn_figures)
	game.snapshot_loaded.connect(_spawn_figures)
	game.turn_changed.connect(func(_p): _face_viewer_side(true))
	game.pawn_captured.connect(_on_captured)
	game.pawn_sent_home.connect(_on_sent_home)
	game.pawns_swapped.connect(_on_swapped)
	game.pawn_moved.connect(_on_pawn_moved)
	game.roll_result.connect(_on_roll)
	game.turn_forfeited.connect(_on_forfeited)
	game.game_over.connect(_on_game_over)
	var input := GameInput.ensure(get_tree())
	input.changed.connect(func(_device): _sync_marks())
	Sound.ensure(get_tree())
	_start_sound.call_deferred()
	if not game.players.is_empty():
		_spawn_figures()

## The board was framed for 16:9. Wider screens see more mud at the sides; narrower
## ones (tablets, some phones held sideways) keep the board's width instead of cropping it.
func _frame_for_aspect() -> void:
	var size := get_viewport().get_visible_rect().size
	var wide := size.y <= 0.0 or size.x / size.y >= 16.0 / 9.0
	camera.keep_aspect = Camera3D.KEEP_HEIGHT if wide else Camera3D.KEEP_WIDTH
	if not wide:
		camera.fov = rad_to_deg(2.0 * atan(tan(deg_to_rad(FOV) / 2.0) * 16.0 / 9.0))
	else:
		camera.fov = FOV

func set_light(mode: String) -> void:
	if _enabled:
		BoardWorld.set_light(_lights, mode)
		Sound.ambience(AMBIENCE.get(mode, &""))

## The courtyard's sound: the music (already playing from the menu) and the light's
## ambience (crickets at dusk, birds at dawn).
const AMBIENCE := {BoardWorld.DUSK: &"amb_dusk", BoardWorld.DAWN: &"amb_dawn"}

func _start_sound() -> void:
	Sound.music(&"courtyard_dusk")
	Sound.ambience(AMBIENCE.get(Settings.light(), &""))

## Where a 2D board position (pixels) is on the 3D board.
func to_board(point: Vector2) -> Vector3:
	return Vector3((point.x - _origin_2d.x) / _tile_2d, 0.0, (point.y - _origin_2d.y) / _tile_2d)

## The same mapping for any 2D board (squares 1 unit, the home square at the origin).
static func map_point(board: Board, point: Vector2) -> Vector3:
	var origin := board.get_square_position(board.board_data.home_index)
	var tile := board.get_tile_size() * board.global_scale.x
	return Vector3((point.x - origin.x) / tile, 0.0, (point.y - origin.y) / tile)

## The discard pile: on the mud by the viewer's left, across from their shells.
const DISCARD_SPOT := Vector3(-3.3, 0.0, 1.6)

var _discards: Array[Node3D] = []

## Where played cards land on screen (CardHUD flies them there).
func discard_screen_point() -> Vector2:
	return camera.unproject_position(_discard_position()) if _enabled else Vector2.ZERO

func _discard_position() -> Vector3:
	return Basis(Vector3.UP, deg_to_rad(_view["yaw"])) * DISCARD_SPOT

## A played card lands on the pile (a lacquered disc in the card's colour).
func add_discard(card: CardData) -> void:
	if not _enabled:
		return
	var disc := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.3
	mesh.bottom_radius = 0.31
	mesh.height = 0.015
	disc.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = card.color.darkened(0.25)
	mat.roughness = 0.4
	disc.material_override = mat
	var at := _discard_position()
	disc.position = at + Vector3(randf_range(-0.06, 0.06), 0.008 + _discards.size() * 0.016, randf_range(-0.06, 0.06))
	disc.rotation.y = randf() * TAU
	add_child(disc)
	_discards.append(disc)
	CardFx.dust(self, at)

## The figure showing `pawn` (null if none), for effects that act on a pawn.
func figure_of(pawn: Pawn) -> PawnFigure:
	return _figures.get(pawn)

func team_figures(player: int) -> Array:
	return _team_figures(player)

## Screen point -> spot on the board plane (null if the ray misses it).
func pointer_on_board(screen: Vector2) -> Variant:
	return Plane(Vector3.UP, 0.0).intersects_ray(camera.project_ray_origin(screen), camera.project_ray_normal(screen))

func _spawn_figures() -> void:
	for pawn in _figures:
		(_figures[pawn] as Node).queue_free()
	for node in _rings.values() + _domes.values():
		(node as Node).queue_free()
	_figures.clear()
	_rings.clear()
	_domes.clear()
	_animating.clear()
	var board := game.board
	_origin_2d = board.get_square_position(board.board_data.home_index)
	_tile_2d = board.get_tile_size() * board.global_scale.x
	for pawn in game.get_all_pawns():
		var player: Dictionary = game.players[pawn.team_id]
		var fig := PawnFigure.create(player.get("figure", ""), player.get("color_name", "Red"))
		add_child(fig)
		_figures[pawn] = fig
		_last_pos[pawn] = pawn.global_position
		pawn.input_pickable = false
		if not pawn.hovered.is_connected(_on_pawn_hovered):
			pawn.hovered.connect(_on_pawn_hovered)
	_face_viewer_side(false)
	_process(0.0)
	_sync_marks()

# --- following the 2D pawns ---
func _process(delta: float) -> void:
	if not _enabled:
		return
	for pawn: Pawn in _figures:
		if not is_instance_valid(pawn):
			continue
		var fig: PawnFigure = _figures[pawn]
		var base := to_board(pawn.global_position)
		var size := lerpf(1.0, pawn.scale.x, STACK_SHRINK)
		if not _animating.has(pawn):
			# The 2D pawn's move "jump" (its sprite grows while hopping) lifts the figure
			var hop := maxf(pawn.sprite.scale.x - 1.0, 0.0) / 0.2 * HOP_HEIGHT
			if hop < 0.01 and _hop_height.get(pawn, 0.0) >= 0.01:
				Sound.play(&"pawn_step") # landed on the next square
			_hop_height[pawn] = hop
			fig.position = base + Vector3.UP * hop
			fig.scale = Vector3.ONE * size
			var moved: Vector2 = pawn.global_position - _last_pos[pawn]
			var target := _rest_yaw(pawn) if moved.length() < 0.5 else atan2(-moved.x, -moved.y)
			fig.rotation.y = lerp_angle(fig.rotation.y, target, minf(1.0, delta * TURN_SPEED))
		_last_pos[pawn] = pawn.global_position
		_update_pawn_marks(pawn, fig, size)

## Standing figures face the viewer, each turned a little differently.
func _rest_yaw(pawn: Pawn) -> float:
	return deg_to_rad(_view["yaw"]) + PI + deg_to_rad(float((pawn.team_id * 4 + pawn.get_index()) % 5) * 12.0 - 24.0)

## Movable-pawn rings and lasting-effect domes follow their figures.
func _update_pawn_marks(pawn: Pawn, fig: PawnFigure, size: float) -> void:
	var ring: MeshInstance3D = _rings.get(pawn)
	if pawn.is_highlighted and ring == null:
		ring = CardFx.chalk_mark(self, fig.position, MARK_GOLD, true, 0.3)
		_rings[pawn] = ring
	elif not pawn.is_highlighted and ring != null:
		ring.queue_free()
		_rings.erase(pawn)
		ring = null
	if ring:
		var pulse := 0.92 + 0.08 * sin(Time.get_ticks_msec() / 160.0)
		ring.position = Vector3(fig.position.x, 0.006, fig.position.z)
		ring.scale = Vector3.ONE * 0.62 * size * pulse
	var dome: MeshInstance3D = _domes.get(pawn)
	var shielded := pawn.status_color.a > 0.0
	if shielded and dome == null:
		dome = CardFx.shield(self, fig.position)
		_domes[pawn] = dome
	elif not shielded and dome != null:
		dome.queue_free()
		_domes.erase(pawn)
		dome = null
	if dome:
		dome.position = Vector3(fig.position.x, 0.0, fig.position.z)
		(dome.material_override as ShaderMaterial).set_shader_parameter("tint", pawn.status_color)

# --- chalk marks from the highlighter state ---
func _sync_marks() -> void:
	if not _enabled:
		return
	var s := game.board.highlighter.state()
	var homes := []
	for entry in s["homebases"]:
		homes.append([entry["tile"], entry["color"], entry["tile"] == s["active_homebase"]])
	_sync_group("homebases", homes, func(e: Array) -> Array[Node]:
		var mark := CardFx.chalk_mark(self, BoardWorld.square_position(e[0]), e[1], true, 0.5)
		mark.scale = Vector3.ONE * (1.0 if e[2] else 0.9)
		(mark.material_override as ShaderMaterial).set_shader_parameter("glow", 1.0 if e[2] else 0.3)
		return [mark])
	var arrow := [s["arrow_from"], s["arrow_to"], s["arrow_unlocked"], s["active_color"]] if s["arrow_from"] >= 0 else []
	_sync_group("arrow", [arrow] if not arrow.is_empty() else [], func(e: Array) -> Array[Node]:
		return _chalk_arrow(e[0], e[1], e[3] if e[2] else LOCKED_GREY, not e[2]))
	var marked := []
	for tile in s["marked_tiles"]:
		marked.append([tile, s["marked_tiles"][tile]])
	_sync_group("marked", marked, func(e: Array) -> Array[Node]:
		return [CardFx.chalk_mark(self, BoardWorld.square_position(e[0]), e[1], false, 0.9)])
	var preview := []
	var tiles: Array = s["preview_tiles"]
	for i in tiles.size():
		preview.append([tiles[i], i + 1, i == tiles.size() - 1, s["preview_end"]])
	_sync_group("preview", preview, func(e: Array) -> Array[Node]:
		var at := BoardWorld.square_position(e[0])
		if e[2]:
			var end := CardFx.chalk_mark(self, at, END_COLORS[e[3]], true, 0.25)
			(end.material_override as ShaderMaterial).set_shader_parameter("glow", 1.0)
			return [end, _chalk_number(at, e[1])]
		var dot := CardFx.chalk_mark(self, at, MARK_GOLD, true, 0.15)
		dot.scale = Vector3.ONE * 0.35
		return [dot, _chalk_number(at, e[1])])
	var focus := [[s["hovered_tile"]]] if GameInput.is_focus_driven() and s["hovered_tile"] >= 0 else []
	_sync_group("focus", focus, func(e: Array) -> Array[Node]:
		var ring := CardFx.chalk_mark(self, BoardWorld.square_position(e[0]), Color(1, 1, 1), true, 0.4)
		ring.scale = Vector3.ONE * 1.2
		return [ring])
	var targets := []
	for tile in s["target_tiles"]:
		targets.append([tile])
	_sync_group("targets", targets, func(e: Array) -> Array[Node]:
		var mark := CardFx.chalk_mark(self, BoardWorld.square_position(e[0]), MARK_GOLD, true, 0.3)
		mark.scale = Vector3.ONE * 1.05
		return [mark])

## Rebuilds one group of marks only when what it shows has changed, so hovering around
## doesn't keep redrawing the marks that stay the same.
func _sync_group(group: String, entries: Array, make: Callable) -> void:
	if _mark_keys.get(group) == entries:
		return
	for node in _marks.get(group, []):
		if is_instance_valid(node):
			node.queue_free()
	var nodes: Array[Node] = []
	for e in entries:
		nodes.append_array(make.call(e))
	_marks[group] = nodes
	_mark_keys[group] = entries.duplicate(true)

## A chalk arrow from one square into the next (the inner-ring entry), with a chalked
## "locked" note while the player still needs a capture.
func _chalk_arrow(from_tile: int, to_tile: int, color: Color, locked: bool) -> Array[Node]:
	var a := BoardWorld.square_position(from_tile)
	var b := BoardWorld.square_position(to_tile)
	var dir := (b - a).normalized()
	var start := a + dir * 0.25
	var tip := b - dir * 0.2
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color * 0.4
	mat.roughness = 1.0
	var shaft := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.07, 0.004, (tip - start).length() - 0.16)
	shaft.mesh = box
	shaft.material_override = mat
	shaft.position = (start + tip - dir * 0.16) / 2.0 + Vector3.UP * 0.008
	shaft.basis = Basis.looking_at(dir, Vector3.UP)
	add_child(shaft)
	var head := MeshInstance3D.new()
	var prism := PrismMesh.new()
	prism.size = Vector3(0.24, 0.2, 0.004)
	head.mesh = prism
	head.material_override = mat
	head.position = tip - dir * 0.1 + Vector3.UP * 0.008
	# Lie flat, pointing along the arrow
	head.basis = Basis.looking_at(Vector3.DOWN, dir)
	add_child(head)
	var nodes: Array[Node] = [shaft, head]
	if locked:
		var note := _chalk_label((start + tip) / 2.0 + dir.cross(Vector3.UP) * 0.18, "locked", 56)
		note.modulate = Color(LOCKED_GREY, 0.95)
		nodes.append(note)
	return nodes

func _chalk_number(at: Vector3, n: int) -> Label3D:
	return _chalk_label(at + Vector3(-0.3, 0, -0.28), str(n), 64)

func _chalk_label(at: Vector3, text: String, font_size: int) -> Label3D:
	var label := Label3D.new()
	label.text = text
	label.font = GameFonts.chalk()
	label.font_size = font_size
	label.pixel_size = 0.0028
	label.outline_size = 0
	label.modulate = Color(0.96, 0.94, 0.88, 0.9)
	label.double_sided = true
	label.position = at + Vector3.UP * 0.007
	# Lying on the ground, the right way up for the viewer
	label.rotation = Vector3(-PI / 2.0, deg_to_rad(_view["yaw"]), 0)
	add_child(label)
	return label

# --- camera ---
## Which board side this screen sees from: the local player's online, the current
## player's offline (passing one screen round the table).
func _viewer_side() -> int:
	var player := game.current_player_index
	if controller and controller.local_seat >= 0:
		player = controller.local_seat
	return game.player_seats[player] if player < game.player_seats.size() else 0

func _face_viewer_side(animate: bool) -> void:
	var side := _viewer_side()
	if side == _side and animate:
		return
	_side = side
	var yaw := side * 90.0
	var target := {"pitch": PITCH, "distance": DISTANCE,
		"yaw": _view["yaw"] + wrapf(yaw - _view["yaw"], -180.0, 180.0)}
	_tween_view(target, TURN_TIME if animate else 0.0)

func _tween_view(target: Dictionary, seconds: float) -> void:
	if _view_tween:
		_view_tween.kill()
	if seconds <= 0.0:
		_view.merge(target, true)
		_apply_camera()
		return
	var from := _view.duplicate()
	_view_tween = create_tween()
	_view_tween.tween_method(func(t: float):
		for key in target:
			_view[key] = lerpf(from[key], target[key], t)
		_apply_camera(), 0.0, 1.0, seconds).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

func _apply_camera() -> void:
	var pitch := deg_to_rad(_view["pitch"])
	var yaw := deg_to_rad(_view["yaw"])
	var toward_viewer := Vector3(sin(yaw), 0, cos(yaw))
	var aim := toward_viewer * AIM_SHIFT
	camera.position = aim + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * float(_view["distance"])
	camera.look_at(aim, Vector3.UP)

## A moment's push-in (a capture, a win), then back to the seated view.
func _push_in() -> void:
	var back := {"pitch": PITCH, "distance": DISTANCE}
	if _view_tween:
		_view_tween.kill()
	var from := _view.duplicate()
	_view_tween = create_tween()
	_view_tween.tween_method(func(t: float):
		_view["pitch"] = lerpf(from["pitch"], CLOSE_PITCH, t)
		_view["distance"] = lerpf(from["distance"], CLOSE_DISTANCE, t)
		_apply_camera(), 0.0, 1.0, 0.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_view_tween.tween_interval(CLOSE_HOLD)
	_view_tween.tween_method(func(t: float):
		_view["pitch"] = lerpf(CLOSE_PITCH, back["pitch"], t)
		_view["distance"] = lerpf(CLOSE_DISTANCE, back["distance"], t)
		_apply_camera(), 0.0, 1.0, 0.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

# --- pointer ---
func _unhandled_input(event: InputEvent) -> void:
	if not _enabled or not event is InputEventMouse or _figures.is_empty():
		return
	var hit: Variant = pointer_on_board(event.position)
	var tile := -1
	var pawn: Pawn = null
	if hit != null:
		tile = _tile_at(hit)
		pawn = _pawn_at(hit)
	if event is InputEventMouseMotion:
		if not GameInput.is_touch(): # a touch drag isn't hovering
			_point(pawn, tile)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if GameInput.is_touch() and _first_tap(pawn, tile):
			return
		_tapped_tile = -1
		if pawn:
			pawn.press()
		game.board.press_tile(tile)

func _point(pawn: Pawn, tile: int) -> void:
	game.board.point_at(tile)
	if pawn != _hovered_pawn:
		if _hovered_pawn and is_instance_valid(_hovered_pawn):
			_hovered_pawn.point(false)
		_hovered_pawn = pawn
		if pawn:
			pawn.point(true)

## Touch: a first tap on something pickable (a ringed pawn, a card's target square)
## only shows it, as hovering would. Returns true if this tap was that first one.
func _first_tap(pawn: Pawn, tile: int) -> bool:
	var pickable: bool = (pawn != null and pawn.is_highlighted) \
		or (pawn == null and tile in game.board.highlighter.state()["target_tiles"])
	if not pickable or tile == _tapped_tile:
		return false
	_tapped_tile = tile
	_point(pawn, tile)
	return true

func _tile_at(point: Vector3) -> int:
	var n := game.board.board_data.get_grid_size()
	var x := floori(point.x + n / 2.0)
	var y := floori(point.z + n / 2.0)
	return x + y * n if x >= 0 and y >= 0 and x < n and y < n else -1

## The figure nearest the pointed spot (highlighted ones first, so a movable pawn in a
## stack is easy to pick), or null.
func _pawn_at(point: Vector3) -> Pawn:
	var best: Pawn = null
	var best_score := INF
	for pawn: Pawn in _figures:
		var at: Vector3 = (_figures[pawn] as Node3D).position
		var d := Vector2(at.x - point.x, at.z - point.z).length()
		if d > PICK_RADIUS:
			continue
		var score := d - (0.2 if pawn.is_highlighted else 0.0)
		if score < best_score:
			best_score = score
			best = pawn
	return best

# --- reactions and arcs ---
func _team_figures(player: int) -> Array:
	return _figures.keys().filter(func(p): return p.team_id == player).map(func(p): return _figures[p])

## The attacker attacks where it landed; the captured pawn is sad, then tumbles back to
## its homebase (its 2D pawn is already there).
func _on_captured(attacker: Pawn, victim: Pawn) -> void:
	if not _figures.has(victim):
		return
	_figures[attacker].play(PawnFigure.ATTACK)
	_figures[victim].play(PawnFigure.SAD)
	Sound.play(&"pawn_capture")
	_push_in()
	_animating[victim] = true
	await get_tree().create_timer(0.45).timeout
	await _knock_home(victim)
	cheer(attacker.team_id, &"celebrate_capture")

## The whole team cheers together (their figures' voices as a chorus) with the moment's
## own cue: a capture's drum flourish, an escape's sigh of relief...
func cheer(player: int, cue: StringName) -> void:
	Sound.play(cue)
	for fig in _team_figures(player):
		fig.play(PawnFigure.CELEBRATE)

## A near miss: an opponent landed one step short of (or past) a pawn it could have
## captured. A heartbeat and a whoosh, and that pawn's team flinches, trembles and sags
## in relief, each figure in its own voice (PawnFigure.relieve).
func _on_pawn_moved(pawn: Pawn, _from_tile: int, _to_tile: int, _steps: int) -> void:
	var teams := {}
	for spared in game.get_near_misses(pawn):
		teams[spared.team_id] = true
	if teams.is_empty():
		return
	await get_tree().create_timer(0.25).timeout
	Sound.play(&"near_miss")
	for team in teams:
		for fig in _team_figures(team):
			(fig as PawnFigure).relieve(randf() * 0.12)

## Pointing at (or pad-focusing) a pawn that can be picked: its figure says hello.
func _on_pawn_hovered(pawn: Pawn) -> void:
	if pawn.is_highlighted and _figures.has(pawn) and Time.get_ticks_msec() - _last_hello_msec > 250:
		_last_hello_msec = Time.get_ticks_msec()
		(_figures[pawn] as PawnFigure).voice(PawnFigure.IDLE)

func _on_sent_home(pawn: Pawn, _from_tile: int) -> void:
	if not _figures.has(pawn) or _animating.has(pawn):
		return
	_figures[pawn].play(PawnFigure.SAD)
	_animating[pawn] = true
	await _knock_home(pawn)

func _knock_home(pawn: Pawn) -> void:
	Sound.play(&"pawn_sent_home")
	await CardFx.knock_home(_figures[pawn], to_board(pawn.global_position))
	_animating.erase(pawn)

func _on_swapped(a: Pawn, b: Pawn) -> void:
	if not (_figures.has(a) and _figures.has(b)):
		return
	_animating[a] = true
	_animating[b] = true
	Sound.play(&"pawn_swap")
	await CardFx.swap(_figures[a], _figures[b], Color(0.5, 0.8, 1.0))
	_animating.erase(a)
	_animating.erase(b)

func _on_roll(value: int) -> void:
	if value in GameManager.BONUS_THROWS:
		# Wait a frame: if this was the third 4/8 in a row the throws are lost instead
		_celebrate_player = game.current_player_index
		_flush_celebration.call_deferred()

func _flush_celebration() -> void:
	if _celebrate_player >= 0:
		for fig in _team_figures(_celebrate_player):
			fig.play(PawnFigure.CELEBRATE)
	_celebrate_player = -1

func _on_forfeited(player: int, _values: Array[int]) -> void:
	_celebrate_player = -1
	for fig in _team_figures(player):
		fig.play(PawnFigure.SAD)

func _on_game_over(winner: int) -> void:
	_push_in()
	for pawn: Pawn in _figures:
		_figures[pawn].play(PawnFigure.CELEBRATE if pawn.team_id == winner else PawnFigure.SAD)

class_name BoardPresenter
extends Node

## Board feedback for this screen, drawn from GameManager's signals: which pawns can
## move (pulsing rings), the active player's homebase and inner-ring arrow, and the
## hovered move preview. Created by the HUD; GameManager never calls into it.
## Online, only the seat whose turn it is sees its choices highlighted.

## The hovered move preview changed ({} = none). Same keys as GameManager.get_move_preview.
signal preview_changed(info: Dictionary)

var _gm: GameManager
var _hud: HUD
var _movable: Array[Pawn] = []
var _hovered_pawn: Pawn = null
var _hovered_tile: int = -1

func bind(gm: GameManager, hud: HUD) -> void:
	_gm = gm
	_hud = hud
	var homebases: Array[Dictionary] = []
	for i in gm.players.size():
		homebases.append({"tile": gm.get_homebase_tile(i), "color": gm.get_player_color(i)})
	_highlighter().set_homebases(homebases)
	for pawn in gm.get_all_pawns():
		pawn.hovered.connect(_on_pawn_hovered)
		pawn.unhovered.connect(_on_pawn_unhovered)
	gm.board.tile_hovered.connect(_on_tile_hovered)
	gm.movable_pawns_changed.connect(_on_movable_pawns_changed)
	gm.turn_changed.connect(func(_p): _update_markers())
	gm.inner_ring_unlocked.connect(func(_p): _update_markers())
	gm.snapshot_loaded.connect(_update_markers)

func _highlighter() -> TileHighlighter:
	return _gm.board.highlighter

func _on_movable_pawns_changed(pawns: Array[Pawn]) -> void:
	_movable = pawns
	var show := _hud.is_local_turn()
	for pawn in _gm.pawn_containers[_gm.current_player_index].get_children():
		if pawn is Pawn:
			pawn.set_highlighted(show and pawns.has(pawn))
	if pawns.is_empty():
		for pawn in _gm.get_all_pawns():
			pawn.set_highlighted(false)
	_refresh_preview()

## Homebase glow + inner-ring entry arrow for whoever is playing now.
func _update_markers() -> void:
	var player := _gm.current_player_index
	var entry := _gm.get_inner_ring_entry(player)
	_highlighter().set_active_player(_gm.get_homebase_tile(player), entry[0], entry[1],
		_gm.get_player_color(player), _gm.is_unlocked(player))

func _on_pawn_hovered(pawn: Pawn) -> void:
	_hovered_pawn = pawn
	_refresh_preview()

func _on_pawn_unhovered(pawn: Pawn) -> void:
	if _hovered_pawn == pawn:
		_hovered_pawn = null
		_refresh_preview()

func _on_tile_hovered(tile_index: int) -> void:
	_hovered_tile = tile_index
	_refresh_preview()

## Preview for the hovered pawn, else for a movable pawn on the hovered tile.
func _refresh_preview() -> void:
	var info := _preview_for(_hovered_pawn)
	if info.is_empty() and _hovered_tile >= 0:
		for pawn in _gm.get_pawns_at_tile(_hovered_tile):
			info = _preview_for(pawn)
			if not info.is_empty():
				break
	if info.is_empty():
		_highlighter().clear_move_preview()
	else:
		_highlighter().show_move_preview(info["tiles"], info["end"])
	preview_changed.emit(info)

func _preview_for(pawn: Pawn) -> Dictionary:
	if pawn == null or not _movable.has(pawn) or not _hud.is_local_turn():
		return {}
	return _gm.get_move_preview(pawn)

class_name TileHighlighter
extends Node2D

## Draws on top of the board art (below pawns): homebases in player colours (the active
## player's pulses), safe-square crosses, the active player's inner-ring entry arrow,
## the tile under the mouse, and a numbered preview of a pending move.

enum PreviewEnd { NORMAL, SAFE, CAPTURE, HOME }

const SAFE_MARK_COLOR := Color(0.25, 0.25, 0.3, 0.55)
const HOVER_COLOR := Color(1, 1, 1, 0.8)
const PATH_COLOR := Color(1.0, 0.82, 0.25, 0.35)
const END_COLORS := {
	PreviewEnd.NORMAL: Color(1.0, 0.75, 0.1, 0.6),
	PreviewEnd.SAFE: Color(0.15, 0.75, 0.8, 0.6),
	PreviewEnd.CAPTURE: Color(0.95, 0.15, 0.15, 0.7),
	PreviewEnd.HOME: Color(0.6, 0.35, 0.95, 0.6),
}

var board: Board

var hovered_tile: int = -1:
	set(value):
		hovered_tile = value
		queue_redraw()

## Inner-ring entry arrow before the player has a capture.
const LOCKED_ARROW_COLOR := Color(0.35, 0.35, 0.4, 0.75)

var _preview_tiles: Array[int] = []
var _preview_end: PreviewEnd = PreviewEnd.NORMAL
## [{"tile": int, "color": Color}] per player.
var _homebases: Array[Dictionary] = []
var _active_homebase: int = -1
var _active_color: Color = Color.WHITE
var _arrow_from: int = -1
var _arrow_to: int = -1
var _arrow_unlocked: bool = false

func _ready() -> void:
	set_process(false)

func _process(_delta: float) -> void:
	queue_redraw() # animates the active homebase pulse

func set_homebases(entries: Array[Dictionary]) -> void:
	_homebases = entries
	queue_redraw()

## Highlights whose turn it is and their inner-ring entry (grey + lock until unlocked).
func set_active_player(homebase: int, arrow_from: int, arrow_to: int, color: Color, unlocked: bool) -> void:
	_active_homebase = homebase
	_arrow_from = arrow_from
	_arrow_to = arrow_to
	_active_color = color
	_arrow_unlocked = unlocked
	set_process(true)
	queue_redraw()

## Tiles in travel order; the last one is the destination.
func show_move_preview(tiles: Array[int], end: PreviewEnd) -> void:
	_preview_tiles = tiles
	_preview_end = end
	queue_redraw()

func clear_move_preview() -> void:
	if _preview_tiles.is_empty():
		return
	_preview_tiles = []
	queue_redraw()

func _draw() -> void:
	var data := board.board_data
	var tile := board.get_tile_size()
	var half := tile / 2.0 - 3.0
	var font := ThemeDB.fallback_font

	# Homebases: every player's in their colour; the active one pulses
	for entry in _homebases:
		var c: Vector2 = data.square_coordinates[entry["tile"]]
		var rect := Rect2(c - Vector2(half, half), Vector2(half, half) * 2.0)
		var fill: Color = entry["color"]
		fill.a = 0.35
		draw_rect(rect, fill)
		if entry["tile"] == _active_homebase:
			var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() / 220.0)
			var border: Color = entry["color"]
			border.a = lerpf(0.5, 1.0, pulse)
			draw_rect(rect.grow(lerpf(1.0, 4.0, pulse)), border, false, 4.0)
	
	# Safe squares: the traditional cross
	for index in data.safe_squares:
		var c: Vector2 = data.square_coordinates[index]
		draw_line(c + Vector2(-half, -half) * 0.7, c + Vector2(half, half) * 0.7, SAFE_MARK_COLOR, 3.0, true)
		draw_line(c + Vector2(-half, half) * 0.7, c + Vector2(half, -half) * 0.7, SAFE_MARK_COLOR, 3.0, true)

	# Inner-ring entry arrow for the active player
	if _arrow_from >= 0 and _arrow_to >= 0:
		_draw_entry_arrow(data.square_coordinates[_arrow_from], data.square_coordinates[_arrow_to], tile)
	
	# Move preview: every tile passed, numbered, destination coloured by outcome
	for i in _preview_tiles.size():
		var c: Vector2 = data.square_coordinates[_preview_tiles[i]]
		var is_end := i == _preview_tiles.size() - 1
		var rect := Rect2(c - Vector2(half, half), Vector2(half, half) * 2.0)
		var color: Color = END_COLORS[_preview_end] if is_end else PATH_COLOR
		draw_rect(rect, color)
		if is_end:
			var border := color
			border.a = 1.0
			draw_rect(rect, border, false, 3.0)
		draw_string(font, c + Vector2(-half + 4, -half + 16), str(i + 1),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.1, 0.1, 0.1, 0.9))

	# Tile under the mouse
	if hovered_tile >= 0:
		var c: Vector2 = data.square_coordinates[hovered_tile]
		draw_rect(Rect2(c - Vector2(half, half), Vector2(half, half) * 2.0), HOVER_COLOR, false, 2.0)

func _draw_entry_arrow(from: Vector2, to: Vector2, tile: float) -> void:
	var dir := (to - from).normalized()
	var start := from + dir * tile * 0.15
	var tip := to - dir * tile * 0.1
	var color := _active_color if _arrow_unlocked else LOCKED_ARROW_COLOR
	var side := dir.orthogonal() * 11.0
	var head_base := tip - dir * 18.0
	# White underlay keeps the arrow readable on light tiles
	draw_line(start, head_base, Color(1, 1, 1, 0.9), 11.0, true)
	draw_line(start, head_base, color, 7.0, true)
	draw_colored_polygon(PackedVector2Array([tip, head_base + side, head_base - side]), color)
	if not _arrow_unlocked:
		# Padlock: shackle + body, centred on the shaft
		var mid := (start + head_base) / 2.0
		draw_arc(mid + Vector2(0, -4), 5.0, PI, TAU, 12, Color(0.15, 0.15, 0.18), 2.5, true)
		draw_rect(Rect2(mid + Vector2(-7, -4), Vector2(14, 11)), Color(0.15, 0.15, 0.18))

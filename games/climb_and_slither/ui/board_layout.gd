class_name ClimbBoardLayout
extends RefCounted
## Where squares and pawns go on screen. Pure math: no nodes, no textures, nothing to do with the
## rules (the UI only places what the view tells it, rule 12).
##
## Squares are numbered 1..size from the bottom-left and snake back and forth ("boustrophedon"):
## the bottom row runs left to right, the next right to left, and so on. Square 0 (not on the
## board yet) is a start strip under the board, one cell tall, with a slot per seat.
##
## `cell` is the side of one square in pixels and `origin` the top-left of the board, both from
## fit(). Positions are in the same coordinate space as `origin`.

const START_STRIP_CELLS: float = 1.0
## Pawn offsets from a square's centre, in cells, for 1 to 4 pawns sharing a square.
const _SLOTS: Array = [
	[Vector2(0.0, 0.0)],
	[Vector2(-0.19, 0.04), Vector2(0.19, 0.04)],
	[Vector2(0.0, -0.16), Vector2(-0.2, 0.14), Vector2(0.2, 0.14)],
	[Vector2(-0.19, -0.12), Vector2(0.19, -0.12), Vector2(-0.19, 0.16), Vector2(0.19, 0.16)],
]

var size: int
var columns: int
var rows: int


func _init(board_size: int, board_columns: int) -> void:
	size = board_size
	columns = board_columns
	rows = board_size / board_columns


## The cell of a square as (column, row counted from the top). Square 0 is (0, rows): the start strip.
func cell_of(square: int) -> Vector2i:
	if square <= 0:
		return Vector2i(0, rows)
	var index: int = square - 1
	var row_from_bottom: int = index / columns
	var column_in_row: int = index % columns
	var column: int = column_in_row if row_from_bottom % 2 == 0 else columns - 1 - column_in_row
	return Vector2i(column, rows - 1 - row_from_bottom)


## The square on a cell, or -1 if the cell is off the board. (0, rows) is the start strip: 0.
func square_at(column: int, row_from_top: int) -> int:
	if row_from_top == rows and column == 0:
		return 0
	if column < 0 or column >= columns or row_from_top < 0 or row_from_top >= rows:
		return -1
	var row_from_bottom: int = rows - 1 - row_from_top
	var column_in_row: int = column if row_from_bottom % 2 == 0 else columns - 1 - column
	return row_from_bottom * columns + column_in_row + 1


## Total height in cells including the start strip.
func total_rows() -> float:
	return float(rows) + START_STRIP_CELLS


## The biggest whole-pixel cell that lets board plus start strip fit in `area` with `margin` all
## round, and where to put it so it is centred. Returns {cell, origin, board_rect, full_rect}.
func fit(area: Vector2, margin: float) -> Dictionary:
	var available: Vector2 = area - Vector2(margin, margin) * 2.0
	var cell: float = maxf(1.0, floorf(minf(available.x / float(columns), available.y / total_rows())))
	var board_size: Vector2 = Vector2(float(columns), float(rows)) * cell
	var full_size: Vector2 = Vector2(float(columns), total_rows()) * cell
	var origin: Vector2 = ((area - full_size) / 2.0).floor()
	return {
		"cell": cell,
		"origin": origin,
		"board_rect": Rect2(origin, board_size),
		"full_rect": Rect2(origin, full_size),
	}


## The centre of a square's cell. Square 0 is the start strip's first slot.
func center(square: int, cell: float, origin: Vector2) -> Vector2:
	var at: Vector2i = cell_of(square)
	return origin + (Vector2(float(at.x), float(at.y)) + Vector2(0.5, 0.5)) * cell


## The slot for the seat-th player waiting on the start strip (square 0).
func start_slot(seat: int, cell: float, origin: Vector2) -> Vector2:
	return origin + Vector2(float(seat) + 0.5, float(rows) + 0.5) * cell


## Offsets from a square's centre for `count` pawns sharing it, in cells.
static func pawn_offsets(count: int) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for offset: Vector2 in _SLOTS[clampi(count, 1, 4) - 1]:
		out.append(offset)
	return out


## Where every pawn rests, as {player_id: Vector2}. `seat_order` is the players in seat order;
## pawns sharing a square take their slots in seat order, so the same position always looks the
## same on every screen. Pawns on square 0 wait on the start strip, one slot per seat.
func pawn_positions(positions: Dictionary, seat_order: Array, cell: float, origin: Vector2) -> Dictionary:
	var by_square: Dictionary = {}
	for seat: int in seat_order.size():
		var player_id: String = seat_order[seat]
		var square: int = int(positions.get(player_id, 0))
		if not by_square.has(square):
			by_square[square] = []
		(by_square[square] as Array).append(player_id)
	var out: Dictionary = {}
	for square: int in by_square:
		var sharing: Array = by_square[square]
		if square <= 0:
			for player_id: String in sharing:
				out[player_id] = start_slot(seat_order.find(player_id), cell, origin)
			continue
		var offsets: Array[Vector2] = pawn_offsets(sharing.size())
		var middle: Vector2 = center(square, cell, origin)
		for i: int in sharing.size():
			out[sharing[i]] = middle + offsets[i] * cell
	return out

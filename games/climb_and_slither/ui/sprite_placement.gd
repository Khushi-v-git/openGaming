class_name ClimbSpritePlacement
extends RefCounted
## Where a snake or ladder sprite goes, from the squares it joins. Pure math (see ClimbArt for
## the anchor data): every transform maps the sprite's anchor points exactly onto the centres of
## the two squares, so a snake's head sits on the square it starts from and its tail on the one it
## ends on, a ladder's foot on its lower square and its top on its upper square.
##
## A Transform2D maps sprite pixels (origin top-left) to the board's coordinates.

## How wide a snake's body is drawn, in cells, when it is shown at its natural length.
const SNAKE_BODY_CELLS: float = 0.30
## Snake art is stretched along its length by at most this range before thickness follows.
const SNAKE_THICKNESS_MIN: float = 0.8
const SNAKE_THICKNESS_MAX: float = 1.6
## Preference against re-using a sprite when choosing snake art (keeps the colours varied).
const SNAKE_REUSE_PENALTY: float = 0.35
## How wide a ladder is drawn, in cells.
const LADDER_WIDTH_CELLS: float = 0.55


## An affine map that sends the sprite's `tail` anchor to `tail_pos` and its `head` anchor to
## `head_pos`. Along the head-tail axis the sprite is stretched to fit exactly; across it the
## thickness follows the stretch gently. A snake that points left is mirrored so it is never
## drawn upside down. Returns {transform, stretch, thickness, flipped}.
static func snake_transform(art: Dictionary, head_pos: Vector2, tail_pos: Vector2, cell: float) -> Dictionary:
	var a_tail: Vector2 = art["tail"]
	var natural: Vector2 = (art["head"] as Vector2) - a_tail
	var natural_length: float = natural.length()
	var e1: Vector2 = natural / natural_length
	var e2: Vector2 = Vector2(-e1.y, e1.x)

	var target: Vector2 = head_pos - tail_pos
	var length: float = maxf(target.length(), 0.001)
	var f1: Vector2 = target / length
	var flipped: bool = f1.x < -0.001
	var f2: Vector2 = Vector2(-f1.y, f1.x) * (-1.0 if flipped else 1.0)

	var reference: float = SNAKE_BODY_CELLS * cell / float(art["body_width"])  # px per sprite px at natural proportions
	var stretch: float = length / (natural_length * reference)
	var along: float = length / natural_length
	var across: float = reference * clampf(sqrt(stretch), SNAKE_THICKNESS_MIN, SNAKE_THICKNESS_MAX)

	# board = tail_pos + f1 * (along * u) + f2 * (across * w), with (u, w) the sprite point's
	# coordinates in the head-tail frame. As a matrix on (x, y): columns are the images of x and y.
	var x_axis: Vector2 = f1 * along * e1.x + f2 * across * e2.x
	var y_axis: Vector2 = f1 * along * e1.y + f2 * across * e2.y
	var linear: Transform2D = Transform2D(x_axis, y_axis, Vector2.ZERO)
	var origin: Vector2 = tail_pos - linear * a_tail
	return {"transform": Transform2D(x_axis, y_axis, origin), "stretch": stretch, "thickness": across, "flipped": flipped}


## The natural length of a snake sprite, in cells, when drawn at its normal body width.
static func snake_natural_cells(art: Dictionary) -> float:
	var span: float = ((art["head"] as Vector2) - (art["tail"] as Vector2)).length()
	return span * SNAKE_BODY_CELLS / float(art["body_width"])


## Picks a sprite (an index into `arts`) for each snake from its length in cells: the one that
## needs the least stretching, but repeated use of the same sprite costs a little, so colours vary.
## Deterministic: the same board always gets the same snakes.
static func choose_snake_arts(lengths_in_cells: Array, arts: Array) -> Array[int]:
	var uses: Array[int] = []
	uses.resize(arts.size())
	uses.fill(0)
	var chosen: Array[int] = []
	for length: float in lengths_in_cells:
		var best: int = 0
		var best_cost: float = INF
		for i: int in arts.size():
			var cost: float = absf(log(maxf(length, 0.01) / snake_natural_cells(arts[i]))) + SNAKE_REUSE_PENALTY * float(uses[i])
			if cost < best_cost - 0.000001:
				best_cost = cost
				best = i
		uses[best] += 1
		chosen.append(best)
	return chosen


## The pieces of a ladder between its foot and top squares: a top piece, as many segments as fit,
## and a bottom piece, each with the transform that places it. `geometry` is ClimbArt's ladder
## data. Width is constant; the segments are stretched along the ladder by a little so the pieces
## meet exactly. The top anchor lands on `top_pos` and the foot anchor on `foot_pos`.
## Returns [{kind: "top"|"segment"|"bottom", transform, size}], drawn in that order.
static func ladder_pieces(geometry: Dictionary, top_pos: Vector2, foot_pos: Vector2, cell: float) -> Array[Dictionary]:
	var width_scale: float = LADDER_WIDTH_CELLS * cell / float(geometry["width"])
	var top_anchor: Vector2 = geometry["top_anchor"]
	var foot_anchor: Vector2 = geometry["foot_anchor"]
	var top_size: Vector2 = geometry["top_size"]
	var segment_size: Vector2 = geometry["segment_size"]
	var bottom_size: Vector2 = geometry["bottom_size"]

	var span: Vector2 = foot_pos - top_pos
	var length: float = maxf(span.length(), 0.001)
	var along: Vector2 = span / length  # from the top towards the foot
	var across: Vector2 = Vector2(along.y, -along.x)  # image +x; (x right, y down) stays a proper rotation

	var top_rest: float = (top_size.y - top_anchor.y) * width_scale
	var foot_part: float = foot_anchor.y * width_scale
	var middle: float = length - top_rest - foot_part
	var segment_pitch: float = segment_size.y * width_scale
	var count: int = maxi(0, roundi(middle / segment_pitch))

	var pieces: Array[Dictionary] = []
	pieces.append(_piece("top", top_size, top_pos, along, across, width_scale, width_scale, -top_anchor.y * width_scale, top_anchor.x))
	if count > 0:
		var pitch: float = middle / float(count)
		for i: int in count:
			pieces.append(_piece("segment", segment_size, top_pos, along, across, width_scale, pitch / segment_size.y, top_rest + float(i) * pitch, top_anchor.x))
	pieces.append(_piece("bottom", bottom_size, top_pos, along, across, width_scale, width_scale, length - foot_part, foot_anchor.x))
	return pieces


static func _piece(kind: String, size: Vector2, top_pos: Vector2, along: Vector2, across: Vector2, scale_across: float, scale_along: float, edge_distance: float, centre_x: float) -> Dictionary:
	# the piece's top edge sits `edge_distance` down the ladder from the top anchor
	var origin: Vector2 = top_pos + along * edge_distance - across * (centre_x * scale_across)
	return {"kind": kind, "size": size, "transform": Transform2D(across * scale_across, along * scale_along, origin)}

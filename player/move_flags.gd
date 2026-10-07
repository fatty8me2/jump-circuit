class_name MoveFlags
extends RefCounted
## The move bits a pose packet carries beside position / velocity / grounded / seq, so a remote
## racer (and a ghost) can show the wall run, the mantle, the wall kick and the knock flail.
## One small int on the wire; a packet without it (an older client) means "no move".
## WALL and MANTLE are states; KICK and KNOCK are one-off events the sender keeps raised for
## EVENT_HOLD seconds, so a couple of lost packets cannot drop them. The receiver acts on a
## bit's rising edge.

const WALL: int = 1          # running on a wall-run panel
const WALL_RIGHT: int = 2    # ... with the wall on their right (only meaningful with WALL)
const MANTLE: int = 4        # hauling up over a ledge
const KICK: int = 8          # just kicked off a wall
const KNOCK: int = 16        # just thrown by a hazard
const ALL: int = 31
## Seconds the sender holds a one-off bit (a few poses at 15 Hz).
const EVENT_HOLD: float = 0.3


## Any value off the wire as a valid flags int (garbage is "no move").
static func clean(v: Variant) -> int:
	if typeof(v) != TYPE_INT and typeof(v) != TYPE_FLOAT:
		return 0
	if typeof(v) == TYPE_FLOAT and not is_finite(float(v)):
		return 0
	var f: int = int(v)
	if f < 0 or f > ALL:
		return 0
	if f & WALL == 0:
		f &= ~WALL_RIGHT
	return f


## -1 wall on the left, +1 on the right, 0 none (PlayerVisual.wall_roll).
static func wall_side(f: int) -> float:
	if f & WALL == 0:
		return 0.0
	return 1.0 if f & WALL_RIGHT != 0 else -1.0

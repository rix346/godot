extends RefCounted
## Your base: where every run starts. No enemies and no fog, and you can build.
## LAYOUT is the starting map (drawn by Rihards), one character per tile:
##   .  floor              #  wall (players can take it down)
##   T  tree               ~  water              f  campfire
##   O  the portal down to depth 1
##   @  where you appear
## Players add and remove walls with the mouse. Only those changes are saved,
## so LAYOUT can still be edited later without wiping anyone's base.

const LAYOUT: Array[String] = [
	"TTTT.....TT.....TTT......TTTTT",
	"TTT..............T.........TTT",
	"TT..#######.TT.......TT.....TT",
	"T...#.....#.........TT...TT..T",
	"....#.@...#.....T.........TT..",
	"....#.....#....TTT............",
	"....#.....#........TT.........",
	"....##.####.TT....TT...#.#....",
	"T...........TT..........O.....",
	"TT.....................#.#....",
	"T.............................",
	"........f......T.............T",
	"....~~........TTT.....T.....TT",
	"...~~~~.......TTTT...TTT......",
	"...~~~~.........T....T........",
	"T...~~...T...T...............T",
	"TT......TT..........T......TTT",
	"TTTT.......TT......TT.....TTTT",
]
## Things you can't walk through or build over. Their art is art/<name>.png.
const PROPS := {"T": "tree", "~": "water", "f": "campfire"}
## Every itch.io browser game shares one storage, so the name has to be unique.
const SAVE_PATH := "user://dungeons_to_the_bottom_base.json"


## The LAYOUT character at `cell`, or "" outside the map.
static func tile(cell: Vector2i) -> String:
	if cell.y < 0 or cell.y >= LAYOUT.size() or cell.x < 0 or cell.x >= LAYOUT[cell.y].length():
		return ""
	return LAYOUT[cell.y][cell.x]


## The walls the player built ("placed") and the LAYOUT walls they took down
## ("removed"), as saved at `path`. Both lists are empty when there's no save.
static func load_changes(path: String) -> Dictionary:
	var changes := {placed = [], removed = []}
	if not FileAccess.file_exists(path):
		return changes
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		return changes
	for key in changes:
		var cells = data.get(key, [])
		if typeof(cells) != TYPE_ARRAY:
			continue
		for v in cells:
			if typeof(v) == TYPE_ARRAY and v.size() == 2:
				changes[key].append(Vector2i(int(v[0]), int(v[1])))
	return changes


## Saves how `floor_cells` differs from LAYOUT: walls built on open ground,
## and LAYOUT walls taken down. Returns false if the file can't be written.
static func save_changes(path: String, floor_cells: Dictionary) -> bool:
	var placed := []
	var removed := []
	for y in LAYOUT.size():
		for x in LAYOUT[y].length():
			var c := Vector2i(x, y)
			if LAYOUT[y][x] == "." and not floor_cells.has(c):
				placed.append([x, y])
			elif LAYOUT[y][x] == "#" and floor_cells.has(c):
				removed.append([x, y])
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify({version = 1, placed = placed, removed = removed}))
	f.close()
	return true

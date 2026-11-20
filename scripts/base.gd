extends RefCounted
## Your base: where every run starts. No enemies and no fog, and you can build.
## LAYOUT is the starting map (drawn by Rihards), one character per tile:
##   .  floor              #  wall (players can take it down)
##   T  tree (walk into it to chop it down for wood)
##   ~  water              f  campfire
##   O  the portal down to depth 1
##   @  where you appear
## Players chop trees, and add and remove walls with the mouse. Only those
## changes (and the wood) are saved, so LAYOUT can still be edited later
## without wiping anyone's base.

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
const WOOD_PER_TREE := 2  # wood you get for chopping down one tree
const WALL_COST := 1  # wood a wall costs to build; taking a wall down gives it back


## The LAYOUT character at `cell`, or "" outside the map.
static func tile(cell: Vector2i) -> String:
	if cell.y < 0 or cell.y >= LAYOUT.size() or cell.x < 0 or cell.x >= LAYOUT[cell.y].length():
		return ""
	return LAYOUT[cell.y][cell.x]


## What the player changed, as saved at `path`: the trees they chopped down
## ("chopped"), the walls they built ("placed", on open ground or where a tree
## was), the LAYOUT walls they took down ("removed"), and their wood. All
## empty, and 0 wood, when there's no save yet.
static func load_changes(path: String) -> Dictionary:
	var changes := {chopped = [], placed = [], removed = [], wood = 0}
	if not FileAccess.file_exists(path):
		return changes
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		return changes
	for key in ["chopped", "placed", "removed"]:
		var cells = data.get(key, [])
		if typeof(cells) != TYPE_ARRAY:
			continue
		for v in cells:
			if typeof(v) == TYPE_ARRAY and v.size() == 2:
				changes[key].append(Vector2i(int(v[0]), int(v[1])))
	var wood = data.get("wood", 0)
	if typeof(wood) in [TYPE_INT, TYPE_FLOAT]:
		changes.wood = maxi(0, int(wood))
	return changes


## Saves how the base differs from LAYOUT (see load_changes), plus the wood.
## `props` holds the trees, water and campfire still standing. Returns false
## if the file can't be written.
static func save_changes(path: String, floor_cells: Dictionary, props: Dictionary, wood: int) -> bool:
	var chopped := []
	var placed := []
	var removed := []
	for y in LAYOUT.size():
		for x in LAYOUT[y].length():
			var c := Vector2i(x, y)
			var ch := LAYOUT[y][x]
			if ch == "T" and not props.has(c):
				chopped.append([x, y])
			if ch in [".", "T"] and not floor_cells.has(c) and not props.has(c):
				placed.append([x, y])
			elif ch == "#" and floor_cells.has(c):
				removed.append([x, y])
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify({version = 1, chopped = chopped, placed = placed, removed = removed, wood = wood}))
	f.close()
	return true

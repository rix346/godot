extends "res://scripts/enemy.gd"
## The Cow, the boss of every 5th depth (BOSS_EVERY in main.gd). Between plain
## melee hits it winds up one of three big attacks, and marks the tiles each
## one will hit before it lands:
## - Line blast: the row or column you stand in turns red, and explodes next turn.
## - Charge: an orange path to where you're heading; next turn it dashes along it.
## - Stomp: it stands still while the 5x5 area around it is red, and after 3
##   turns that area explodes.
## It only walks toward you every other turn, so it's easier to get away from.

enum Plan { NONE, LINE, DASH, STOMP }

const SPECIAL_EVERY := 3  # its turns from one big attack landing to winding up the next
const SPECIAL_RANGE := 8  # it only winds up a big attack when it can see you this close
const STOMP_TURNS := 3
const STOMP_CHANCE := 0.6  # when you're within 2 tiles; otherwise line blast or charge
const LINE_MULT := 1.5  # damage of the big attacks, times the Cow's attack
const DASH_MULT := 2.0
const STOMP_MULT := 2.5
const COINS := 5
const RED := Color(1, 0.15, 0.1)
const ORANGE := Color(1, 0.55, 0.1)

var plan := Plan.NONE  # the big attack it's winding up
var plan_turns := 0  # its turns until that attack lands
var special_in := 2  # its turns until the next big attack; a short breather when you arrive
var _walk := false  # flips every time it could walk, so it only walks every other turn


## Depth 5: 60 HP, 4 attack, 50 XP. Every depth after that: +8 HP, +1 attack, +10 XP.
func setup_boss(depth: int) -> void:
	display_name = "Cow"
	glyph = "C"
	color = Color(0.92, 0.9, 0.85)
	max_hp = 20 + 8 * depth
	hp = max_hp
	attack = depth - 1
	xp_value = 10 * depth
	load_art("cow")


func coin_drop() -> int:
	return COINS


## Its whole turn. main.gd calls this instead of the normal enemy turn.
func boss_turn(game) -> void:
	var player = game.player
	if plan != Plan.NONE:
		plan_turns -= 1
		if plan_turns <= 0:
			_unleash(game)
		queue_redraw()
		return
	special_in -= 1
	var d: int = game._dist(grid_pos, player.grid_pos)
	if special_in <= 0 and d <= SPECIAL_RANGE and game._line_of_sight(grid_pos, player.grid_pos):
		if game._cheb(grid_pos, player.grid_pos) <= 2 and randf() < STOMP_CHANCE:
			plan_stomp(game)
		elif randf() < 0.5:
			plan_line(game)
		else:
			plan_dash(game)
		queue_redraw()
	elif d == 1:
		game._attack(self, player)
	else:
		_walk = not _walk
		if _walk and d <= AGGRO_RANGE:
			game._step_toward(self, player.grid_pos)


## Line blast: the row or column you stand in, out to the walls. It picks one
## you can step out of, so a corridor can't trap you.
func plan_line(game) -> void:
	var p: Vector2i = game.player.grid_pos
	var axes := [Vector2i.RIGHT, Vector2i.DOWN]
	axes.shuffle()
	var axis: Vector2i = axes[0]
	var side := Vector2i(axis.y, axis.x)
	if not (game.floor_cells.has(p + side) or game.floor_cells.has(p - side)):
		axis = axes[1]
	_set_plan(Plan.LINE, 1, RED)
	danger.append(p)
	for dir in [axis, -axis]:
		var c: Vector2i = p + dir
		while game.floor_cells.has(c):
			danger.append(c)
			c += dir
	game._log("The Cow's eyes glow red. Get out of the line!")


## Charge: a straight run at where you'll be next turn, guessed as one more
## step the way you just moved (or where you stand, if you didn't move). If a
## wall is in the way it does a line blast instead.
func plan_dash(game) -> void:
	var p: Vector2i = game.player.grid_pos
	var path := _charge_path(game, p + game.last_step)
	if path.is_empty():
		path = _charge_path(game, p)
	if path.is_empty():
		plan_line(game)
		return
	_set_plan(Plan.DASH, 1, ORANGE)
	danger.assign(path)
	game._log("The Cow lowers its horns. It's going to charge!")


## Stomp: it stays put for STOMP_TURNS turns, then the 5x5 around it explodes.
func plan_stomp(game) -> void:
	_set_plan(Plan.STOMP, STOMP_TURNS, RED)
	for x in range(-2, 3):
		for y in range(-2, 3):
			var c := grid_pos + Vector2i(x, y)
			if game.floor_cells.has(c):
				danger.append(c)
	game._log("The Cow stamps its hooves. Get away from it!")


func _set_plan(new_plan: Plan, turns: int, col: Color) -> void:
	plan = new_plan
	plan_turns = turns
	danger_color = col
	danger.clear()


## The straight run from the Cow to `aim`, or empty if a wall or another enemy
## is in the way.
func _charge_path(game, aim: Vector2i) -> Array[Vector2i]:
	var path := walk_line(grid_pos, aim)
	for c in path:
		if not game.floor_cells.has(c) or game._enemy_at(c):
			path.clear()
			break
	return path


func _unleash(game) -> void:
	var player = game.player
	match plan:
		Plan.LINE:
			game._explode(danger)
			if player.grid_pos in danger:
				game._hit(self, player, ceili(attack * LINE_MULT), "blasted")
		Plan.STOMP:
			game._explode(danger)
			if player.grid_pos in danger:
				game._hit(self, player, ceili(attack * STOMP_MULT), "stomped")
		Plan.DASH:
			_charge(game)
	plan = Plan.NONE
	danger.clear()
	special_in = SPECIAL_EVERY


## Runs along the marked path. If you're still on it, it stops right in front
## of you and rams you.
func _charge(game) -> void:
	var player = game.player
	var start := grid_pos
	var rammed := false
	for c in danger:
		if c == player.grid_pos:
			rammed = true
			break
		if not game.floor_cells.has(c) or game._enemy_at(c):
			break
		grid_pos = c
	var tw := _new_motion()
	tw.tween_property(self, "position", Vector2(grid_pos * TILE), 0.04 * game._dist(start, grid_pos))
	if grid_pos != start:
		game._zap(start, grid_pos, ORANGE)
	if rammed:
		var push := Vector2(player.grid_pos - grid_pos) * 8
		tw.tween_property(self, "position", Vector2(grid_pos * TILE) + push, 0.05)
		tw.tween_property(self, "position", Vector2(grid_pos * TILE), 0.07)
		game._hit(self, player, ceili(attack * DASH_MULT), "rammed")
	else:
		game._log("The Cow's charge misses you.")


## Tiles on a straight line from a to b, a itself left out. Each step is up,
## down, left or right, so a charge never squeezes between two walls.
static func walk_line(a: Vector2i, b: Vector2i) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	var n := (b - a).abs()
	var step := (b - a).sign()
	var c := a
	var done := Vector2i.ZERO
	while done.x < n.x or done.y < n.y:
		if (1 + 2 * done.x) * n.y < (1 + 2 * done.y) * n.x:
			c.x += step.x
			done.x += 1
		else:
			c.y += step.y
			done.y += 1
		cells.append(c)
	return cells


func _draw() -> void:
	super()
	if plan == Plan.STOMP:
		_draw_mark(str(plan_turns))  # countdown to the explosion
	elif plan != Plan.NONE:
		_draw_mark("!")


## Big red text in the top-right corner of the tile.
func _draw_mark(text: String) -> void:
	var font := ThemeDB.fallback_font
	var pos := Vector2(TILE - 12, 15)
	draw_string_outline(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 4, Color.BLACK)
	draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, RED)

extends Node2D
## Game controller: builds the dungeon, runs the turn loop, owns the HUD.
##
## Turn order: the player acts (move, bump-attack, wait, or skill), then every
## enemy acts once in list order. Level-ups are resolved after the round.

const Unit := preload("res://scripts/unit.gd")
const Player := preload("res://scripts/player.gd")
const Enemy := preload("res://scripts/enemy.gd")
const Cow := preload("res://scripts/cow.gd")
const Cards := preload("res://scripts/cards.gd")
const LevelUpUI := preload("res://scripts/level_up_ui.gd")
const ShopUI := preload("res://scripts/shop_ui.gd")
const CardPickerUI := preload("res://scripts/card_picker_ui.gd")

const W := 30
const H := 18
const TILE := Unit.TILE
const MAX_ROOMS := 9
const EXTRA_CORRIDORS := 2  # extra links between random rooms, so maps have loops
const MAX_ENEMIES := 20  # 3 + 2 per depth reaches this on depth 9; deeper floors get tougher, not fuller
const BOSS_EVERY := 5  # every 5th depth is a cave with a boss and no other enemies
const CAVE_FILL := 0.42  # share of a boss cave that is floor
const BOSS_SPAWN_DIST := 8  # the boss starts at least this many steps from you
const DIRS: Array[Vector2i] = [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
const SIGHT := 7
const FIREBALL_RANGE := 6
const CHAIN_JUMP_RANGE := 3
const DESCEND_HEAL := 0.3  # part of max HP you get back on every trip down the stairs
const MELEE_MULT := 2  # walking into an enemy hits for 2x your attack, unless you hold a ranged weapon
const SHOP_CHANCE := 0.4  # chance a cleared floor gets a shopkeeper (from depth 2)
const SHOP_FIRST_DEPTH := 2
const COIN_SIZE := 16  # coins on the ground are drawn at half a tile
const GOLD := Color(1.0, 0.84, 0.3)  # coins, the shop sign and the Break Wall outline
const DIRECTION_KEYS := {
	KEY_UP: Vector2i.UP, KEY_W: Vector2i.UP, KEY_DOWN: Vector2i.DOWN, KEY_S: Vector2i.DOWN,
	KEY_LEFT: Vector2i.LEFT, KEY_A: Vector2i.LEFT, KEY_RIGHT: Vector2i.RIGHT, KEY_D: Vector2i.RIGHT,
}

enum State { PLAYER_TURN, LEVEL_UP, DEAD, SHOP, PICKER }
const _SEQ := [51, 59, 41, 49, 60, 53, 40, 50, 63, 54, 42, 97]

var state := State.PLAYER_TURN
var depth := 1
var turn := 1
var floor_cells := {}  # Vector2i -> true
var rooms: Array[Rect2i] = []
var visible_cells := {}  # in the player's line of sight right now
var _aim = null  # enemy picked with the mouse for a ranged weapon
var _reticle: Line2D
var seen_cells := {}  # explored on this floor; drawn dimmed when not visible
var stairs := Vector2i(-1, -1)
var coins := {}  # Vector2i -> coins lying on that tile
var shop := Vector2i(-1, -1)  # the shopkeeper's tile, (-1, -1) if this floor has none
var shop_stock: Array = []  # [{card, sold}] for sale on this floor
var floors_without_shop := 0
var breaking := false  # Break Wall is waiting for a direction
var last_step := Vector2i.ZERO  # your move this turn (zero if you didn't move); the Cow aims its charge with it
var astar := AStarGrid2D.new()
var player: Player
var enemies: Array = []
var log_lines: Array[String] = []

var _hud: Label
var _level_ui: LevelUpUI
var _floor_tex: Texture2D
var _wall_tex: Texture2D
var _stairs_tex: Texture2D
var _coin_tex: Texture2D
var _shop_tex: Texture2D
var _hud_layer: CanvasLayer
var _purse: TextureRect  # HUD coin icon; Coin Magnet coins fly here
var _purse_label: Label
var _shop_ui: ShopUI
var _picker: CardPickerUI
var _seq_pos := 0
var _seq_last := 0
var _danger_layer: Node2D  # frames boss attack tiles above the units


func _ready() -> void:
	randomize()
	_coin_tex = _load_art("coin")
	_shop_tex = _load_art("shopkeeper")
	_build_hud()
	_danger_layer = Node2D.new()
	_danger_layer.z_index = 4
	_danger_layer.draw.connect(_draw_danger_frames)
	add_child(_danger_layer)
	player = Player.new()
	player.died.connect(_on_player_died)
	add_child(player)
	_new_floor()
	_log("Arrows/WASD move & attack, Space waits, 1-3 use skills.")
	_refresh_hud()


# --- Dungeon -----------------------------------------------------------------

func _new_floor() -> void:
	for e in enemies:
		e.queue_free()
	enemies.clear()
	stairs = Vector2i(-1, -1)
	coins.clear()
	shop = Vector2i(-1, -1)
	shop_stock = []
	breaking = false
	seen_cells.clear()
	# Boss caves always use the depth 1 tiles.
	var art_depth := 1 if is_boss_floor() else depth
	_floor_tex = _depth_art("floor", art_depth)
	_wall_tex = _depth_art("wall", art_depth)
	_stairs_tex = _depth_art("stairs", art_depth)
	if is_boss_floor():
		_carve_cave()
		player.place(Vector2i(W / 2, H / 2))
		_spawn_boss()
	else:
		_carve_map()
		player.place(rooms[0].get_center())
		_spawn_enemies(mini(3 + depth * 2, MAX_ENEMIES))
	_update_fov()


func is_boss_floor() -> bool:
	return depth % BOSS_EVERY == 0


## Non-overlapping rectangular rooms, chained left to right by L-shaped
## corridors (plus a few extra links), so every floor tile is reachable.
func _carve_map() -> void:
	floor_cells.clear()
	rooms.clear()
	for attempt in 100:
		if rooms.size() >= MAX_ROOMS:
			break
		var size := Vector2i(randi_range(4, 8), randi_range(3, 6))
		var room := Rect2i(Vector2i(randi_range(1, W - size.x - 1), randi_range(1, H - size.y - 1)), size)
		if not rooms.any(func(other): return other.grow(1).intersects(room)):
			rooms.append(room)
	rooms.sort_custom(func(a, b): return a.position.x < b.position.x)
	for i in rooms.size():
		for x in range(rooms[i].position.x, rooms[i].end.x):
			for y in range(rooms[i].position.y, rooms[i].end.y):
				floor_cells[Vector2i(x, y)] = true
		if i > 0:
			_carve_corridor(rooms[i - 1].get_center(), rooms[i].get_center())
	for i in EXTRA_CORRIDORS:
		_carve_corridor(rooms.pick_random().get_center(), rooms.pick_random().get_center())
	_build_astar()


## Boss floors are one big cave, carved like the very first version of the
## game: a random walk from the centre until CAVE_FILL of the map is floor,
## so every tile can be reached. Caves have no rooms.
func _carve_cave() -> void:
	floor_cells.clear()
	rooms.clear()
	var pos := Vector2i(W / 2, H / 2)
	while floor_cells.size() < int(W * H * CAVE_FILL):
		floor_cells[pos] = true
		pos = (pos + DIRS.pick_random()).clamp(Vector2i(1, 1), Vector2i(W - 2, H - 2))
	_build_astar()


## Pathfinding grid for enemies: walls are solid.
func _build_astar() -> void:
	astar.region = Rect2i(0, 0, W, H)
	astar.cell_size = Vector2(1, 1)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()
	for x in W:
		for y in H:
			astar.set_point_solid(Vector2i(x, y), not floor_cells.has(Vector2i(x, y)))


func _carve_corridor(a: Vector2i, b: Vector2i) -> void:
	var corner := Vector2i(b.x, a.y) if randf() < 0.5 else Vector2i(a.x, b.y)
	for leg in [[a, corner], [corner, b]]:
		var c: Vector2i = leg[0]
		var step: Vector2i = (leg[1] - c).sign()
		floor_cells[c] = true
		while c != leg[1]:
			c += step
			floor_cells[c] = true


## Recomputes what the player can see and hides enemies outside it.
func _update_fov() -> void:
	visible_cells.clear()
	var p := player.grid_pos
	if player.night_vision:
		# Night Vision: every floor tile and the walls around it are lit.
		for c in floor_cells:
			for x in range(c.x - 1, c.x + 2):
				for y in range(c.y - 1, c.y + 2):
					visible_cells[Vector2i(x, y)] = true
		seen_cells.merge(visible_cells)
	else:
		for x in range(maxi(0, p.x - SIGHT), mini(W, p.x + SIGHT + 1)):
			for y in range(maxi(0, p.y - SIGHT), mini(H, p.y + SIGHT + 1)):
				var c := Vector2i(x, y)
				if (c - p).length_squared() <= SIGHT * SIGHT and _line_of_sight(p, c):
					visible_cells[c] = true
					seen_cells[c] = true
	for e in enemies:
		e.visible = visible_cells.has(e.grid_pos)
	queue_redraw()


## True if nothing but floor lies strictly between a and b (walls at b are
## themselves visible).
func _line_of_sight(a: Vector2i, b: Vector2i) -> bool:
	var d := b - a
	var n := maxi(absi(d.x), absi(d.y))
	for i in range(1, n):
		var t := float(i) / n
		if not floor_cells.has(Vector2i(roundi(a.x + d.x * t), roundi(a.y + d.y * t))):
			return false
	return true


## Deeper floors get a tougher mix (Enemy.random_kind) and more elites.
func _spawn_enemies(count: int) -> void:
	var cells := floor_cells.keys().filter(func(c): return _dist(c, player.grid_pos) >= 6)
	cells.shuffle()
	for i in min(count, cells.size()):
		var e := Enemy.new()
		e.setup(Enemy.random_kind(depth), depth)
		if randf() < Enemy.elite_chance(depth):
			e.make_elite()
		_add_enemy(e, cells[i])


## The Cow, somewhere in the cave away from you.
func _spawn_boss() -> void:
	var cells := floor_cells.keys().filter(func(c): return _dist(c, player.grid_pos) >= BOSS_SPAWN_DIST)
	if cells.is_empty():
		cells = floor_cells.keys().filter(func(c): return c != player.grid_pos)
	var boss := Cow.new()
	boss.setup_boss(depth)
	_add_enemy(boss, cells.pick_random())


func _add_enemy(e, cell: Vector2i) -> void:
	e.place(cell)
	e.died.connect(_on_enemy_died)
	add_child(e)
	enemies.append(e)


## The boss of this floor, or null.
func _boss():
	for e in enemies:
		if e.has_method("boss_turn"):
			return e
	return null


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(W * TILE, H * TILE)), Color.BLACK)
	for x in W:
		for y in H:
			var c := Vector2i(x, y)
			if not seen_cells.has(c):
				continue
			var is_floor := floor_cells.has(c)
			var tex := _floor_tex if is_floor else _wall_tex
			if tex:
				draw_texture_rect(tex, Rect2(Vector2(c * TILE), Vector2(TILE, TILE)), false)
			else:
				var col := Color(0.16, 0.16, 0.2) if is_floor else Color(0.05, 0.05, 0.07)
				draw_rect(Rect2(Vector2(c * TILE), Vector2(TILE - 1, TILE - 1)), col)
	if stairs.x >= 0 and seen_cells.has(stairs):
		if _stairs_tex:
			draw_texture_rect(_stairs_tex, Rect2(Vector2(stairs * TILE), Vector2(TILE, TILE)), false)
		else:
			draw_rect(Rect2(Vector2(stairs * TILE) + Vector2(4, 4), Vector2(TILE - 8, TILE - 8)), Color(0.95, 0.8, 0.2))
			draw_string(ThemeDB.fallback_font, Vector2(stairs * TILE) + Vector2(4, 22), ">", HORIZONTAL_ALIGNMENT_CENTER, TILE - 8, 16, Color.BLACK)
	if shop.x >= 0 and seen_cells.has(shop):
		if _shop_tex:
			draw_texture_rect(_shop_tex, Rect2(Vector2(shop * TILE), Vector2(TILE, TILE)), false)
		else:
			draw_rect(Rect2(Vector2(shop * TILE) + Vector2(3, 3), Vector2(TILE - 6, TILE - 6)), Color(0.55, 0.35, 0.8))
			draw_string(ThemeDB.fallback_font, Vector2(shop * TILE) + Vector2(3, 22), "$", HORIZONTAL_ALIGNMENT_CENTER, TILE - 6, 16, GOLD)
	for c in coins:
		if seen_cells.has(c):
			# One coin centred on the tile; a pile shows up to 3, stacked.
			var corner := Vector2(c * TILE) + Vector2(TILE - COIN_SIZE, TILE - COIN_SIZE) / 2
			for i in mini(coins[c], 3):
				var r := Rect2(corner + Vector2(i * 3, -i * 3), Vector2(COIN_SIZE, COIN_SIZE))
				if _coin_tex:
					draw_texture_rect(_coin_tex, r, false)
				else:
					draw_circle(r.get_center(), COIN_SIZE / 2.0, GOLD)
	for c in seen_cells:
		if not visible_cells.has(c):
			draw_rect(Rect2(Vector2(c * TILE), Vector2(TILE, TILE)), Color(0, 0, 0, 0.6))
	# A boss attack that's winding up: the tiles it will hit next.
	for e in enemies:
		for c in e.danger:
			if seen_cells.has(c):
				draw_rect(Rect2(Vector2(c * TILE), Vector2(TILE, TILE)), Color(e.danger_color, 0.35))
	_danger_layer.queue_redraw()
	if breaking:
		# Break Wall: outline the walls next to you that can be smashed.
		for dir in DIRS:
			var c: Vector2i = player.grid_pos + dir
			if not floor_cells.has(c) and _can_break(c):
				draw_rect(Rect2(Vector2(c * TILE) + Vector2(1, 1), Vector2(TILE - 2, TILE - 2)), GOLD, false, 2)


## Frames around the boss attack tiles, drawn over the units, so you can see
## when you're standing in one.
func _draw_danger_frames() -> void:
	for e in enemies:
		for c in e.danger:
			if seen_cells.has(c):
				_danger_layer.draw_rect(Rect2(Vector2(c * TILE) + Vector2(1, 1), Vector2(TILE - 2, TILE - 2)), Color(e.danger_color, 0.9), false, 2)


## Tile art for depth `d`: <name>_<d>.png, else the nearest shallower
## <name>_<n>.png, else <name>.png. So floor_1 and floor_4 make depths 1-3
## and 4+ look different.
func _depth_art(art_name: String, d: int) -> Texture2D:
	for n in range(d, 0, -1):
		var tex := _load_art("%s_%d" % [art_name, n])
		if tex:
			return tex
	return _load_art(art_name)


## res://art/<art_name>.png, or null so the caller falls back to plain colours.
func _load_art(art_name: String) -> Texture2D:
	var path := "res://art/%s.png" % art_name
	return load(path) if ResourceLoader.exists(path) else null


# --- Input & turn loop -------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_aim_at(Vector2i((get_global_mouse_position() / TILE).floor()))
		return
	if not (event is InputEventKey and event.pressed):
		return
	if event.keycode == KEY_ESCAPE and breaking:
		_aim_break_wall(KEY_ESCAPE)
		return
	if event.keycode == KEY_ESCAPE and state not in [State.LEVEL_UP, State.SHOP, State.PICKER]:
		get_tree().change_scene_to_file("res://scenes/title.tscn")
		return
	if state == State.DEAD:
		if event.keycode == KEY_R:
			get_tree().reload_current_scene()
		return
	if state != State.PLAYER_TURN:
		return
	if not event.echo and _follow_keys(event):
		get_viewport().set_input_as_handled()
		return

	var acted := false
	last_step = Vector2i.ZERO
	if breaking:
		if event.echo:
			return  # a held skill key shouldn't cancel its own aim
		acted = _aim_break_wall(event.keycode)
	elif DIRECTION_KEYS.has(event.keycode):
		acted = _player_step(DIRECTION_KEYS[event.keycode])
	else:
		match event.keycode:
			KEY_SPACE, KEY_PERIOD:
				acted = true
				_shoot()
			KEY_1, KEY_2, KEY_3:
				acted = _use_skill(event.keycode - KEY_1)
	if acted:
		get_viewport().set_input_as_handled()
		_end_player_turn()


## Move, or attack if an enemy is in the way. Returns false if nothing happened.
func _player_step(dir: Vector2i) -> bool:
	var target := player.grid_pos + dir
	if target == shop:
		_open_shop()  # browsing is free: no turn passes
		return false
	var enemy = _enemy_at(target)
	if enemy:
		_player_attack(enemy, dir)
		return true
	if not floor_cells.has(target):
		return false
	if player.weapon.get("reach", 1) >= 2:
		var far = _enemy_at(target + dir)
		if far and far.visible:
			_player_attack(far, dir)
			return true
	player.move_to(target)
	last_step = dir
	_pick_up_coins(target)
	if target == stairs:
		_descend()
	else:
		_shoot()
	return true


## Next floor, and you get DESCEND_HEAL of your max HP back on the way down.
func _descend() -> void:
	depth += 1
	_new_floor()
	var before := player.hp
	player.heal(ceili(player.max_hp * DESCEND_HEAL))
	var healed := player.hp - before
	last_step = Vector2i.ZERO
	_log("You descend to depth %d%s." % [depth, " and recover %d HP" % healed if healed > 0 else ""])
	var boss = _boss()
	if boss:
		_log("Boss floor! The %s is somewhere in this cave." % boss.display_name)


# --- Ranged weapons ------------------------------------------------------------

## Fires the equipped ranged weapon at its target (see _bow_target). Called on
## every step: moving or waiting, not melee attacks or skills.
func _shoot() -> void:
	var w: Dictionary = player.weapon
	if w.get("ranged", 0) == 0:
		return
	_update_fov()  # aim from where the player stands now
	var targets := []
	var target = _bow_target()
	while target != null and targets.size() < w.get("arrows", 1):
		targets.append(target)
		target = _nearest_shootable(targets)
	for e in targets:
		_zap(player.grid_pos, e.grid_pos, Color(1, 0.95, 0.7))
		var dmg := ceili(player.attack * w.get("shot_mult", 1.0))
		_hit(player, e, maxi(1, roundi(dmg * e.arrow_mult)), "shot")  # bosses shrug off most of it


## The mouse-picked enemy while it can still be shot, else the nearest one.
func _bow_target():
	if _aim != null and (not is_instance_valid(_aim) or not _can_shoot(_aim)):
		_aim = null
	return _aim if _aim != null else _nearest_shootable()


func _nearest_shootable(exclude := []):
	var best = null
	for e in enemies:
		if e in exclude or not _can_shoot(e):
			continue
		if best == null or _dist(e.grid_pos, player.grid_pos) < _dist(best.grid_pos, player.grid_pos):
			best = e
	return best


## In range (counting diagonals as 1), in sight and not blocked by walls.
func _can_shoot(e) -> bool:
	return e.is_alive() and visible_cells.has(e.grid_pos) \
		and _cheb(e.grid_pos, player.grid_pos) <= player.weapon.get("ranged", 0) \
		and _line_of_sight(player.grid_pos, e.grid_pos)


## Left click on an enemy picks it as the ranged target (free, no turn used).
func _aim_at(cell: Vector2i) -> void:
	if state != State.PLAYER_TURN or player.weapon.get("ranged", 0) == 0:
		return
	var e = _enemy_at(cell)
	if e and _can_shoot(e):
		_aim = e
		_update_reticle()


## Box around the current ranged target: red when picked with the mouse,
## yellow when chosen automatically.
func _update_reticle() -> void:
	if _reticle == null:
		_reticle = Line2D.new()
		_reticle.width = 2
		_reticle.z_index = 5
		_reticle.closed = true
		for p in [Vector2(1, 1), Vector2(TILE - 1, 1), Vector2(TILE - 1, TILE - 1), Vector2(1, TILE - 1)]:
			_reticle.add_point(p)
		add_child(_reticle)
	var target = _bow_target() if state != State.DEAD else null
	_reticle.visible = target != null
	if target:
		_reticle.position = Vector2(target.grid_pos * TILE)
		_reticle.default_color = Color(1, 0.3, 0.3) if target == _aim else Color(1, 0.9, 0.4)


func _end_player_turn() -> void:
	player.end_turn()
	_run_enemies()
	if state != State.DEAD and player.poison_turns > 0:
		player.poison_turns -= 1
		player.queue_redraw()
		_log("Poison deals 1 damage.")
		player.take_damage(1)
	if state == State.DEAD:
		_refresh_hud()
		return
	if player.shield_turns > 0:
		player.shield_turns -= 1
		player.queue_redraw()
	_update_fov()
	turn += 1
	_check_level_up()
	_refresh_hud()


func _run_enemies() -> void:
	for e in enemies.duplicate():
		if state == State.DEAD:
			return
		if not is_instance_valid(e) or not e.is_alive() or e.tick_rest():
			continue
		for i in e.actions:
			if state == State.DEAD or not e.is_alive():
				break
			_enemy_act(e)


func _enemy_act(e) -> void:
	if e.has_method("boss_turn"):
		e.boss_turn(self)
		return
	var d := _dist(e.grid_pos, player.grid_pos)
	if d == 1:
		_attack(e, player)
	elif d <= e.attack_range and _clear_line(e.grid_pos, player.grid_pos):
		_zap(e.grid_pos, player.grid_pos, Color(1, 0.9, 0.5))
		_attack(e, player, true)
	elif d <= Enemy.AGGRO_RANGE:
		_step_toward(e, player.grid_pos)


## One step along the shortest path to `target`, unless someone is in the way.
func _step_toward(e, target: Vector2i) -> void:
	var path := astar.get_id_path(e.grid_pos, target)
	if path.size() > 1 and not _enemy_at(path[1]) and path[1] != player.grid_pos:
		e.move_to(path[1])


func _check_level_up() -> void:
	while player.pending_levels > 0:
		var choices := Cards.roll_choices(player)
		if choices.is_empty():
			player.pending_levels = 0  # everything maxed out
			break
		state = State.LEVEL_UP
		_level_ui.show_choices(player, choices)
		return
	state = State.PLAYER_TURN


func _on_card_chosen(card: Dictionary) -> void:
	_gain_card(card)
	player.pending_levels -= 1
	_log("Picked %s." % card.name)
	_check_level_up()
	_refresh_hud()


## Applies a card from a level-up or the shop, plus what it changes on the map.
func _gain_card(card: Dictionary) -> void:
	Cards.apply(player, card)
	if card.id == "coin_magnet":
		_magnet_coins()
	_update_fov()  # Night Vision lights up the floor right away


# --- Coins & shop --------------------------------------------------------------

## Tougher enemies are more likely to drop a coin, elites always drop one and
## a boss drops a pile (see Enemy.coin_drop).
func _drop_coin(e) -> void:
	var n: int = e.coin_drop()
	if n == 0:
		return
	if player.coin_magnet:
		player.coins += n
		for i in n:
			_fly_coin(e.grid_pos, i * 0.1)
	else:
		coins[e.grid_pos] = coins.get(e.grid_pos, 0) + n
		queue_redraw()


func _pick_up_coins(cell: Vector2i) -> void:
	var n: int = coins.get(cell, 0)
	if n == 0:
		return
	coins.erase(cell)
	player.coins += n
	player.popup("+%d coin%s" % [n, "s" if n > 1 else ""], GOLD)
	queue_redraw()


## Coin Magnet pulls in every coin already lying on this floor.
func _magnet_coins() -> void:
	for c in coins:
		player.coins += coins[c]
		_fly_coin(c)
	coins.clear()
	queue_redraw()


## A coin that flies from a map tile to the HUD coin counter, after `delay`
## seconds (so a pile flies one coin after another).
func _fly_coin(cell: Vector2i, delay := 0.0) -> void:
	if _coin_tex == null:
		return
	var coin := Sprite2D.new()
	coin.texture = _coin_tex
	coin.scale = Vector2(COIN_SIZE, COIN_SIZE) / _coin_tex.get_size()
	coin.position = Vector2(cell * TILE) + Vector2(TILE, TILE) / 2
	_hud_layer.add_child(coin)
	var tw := coin.create_tween()
	if delay > 0:
		tw.tween_interval(delay)
	tw.tween_property(coin, "position", _purse.global_position + _purse.size / 2, 0.5) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_callback(coin.queue_free)


## Called when the last enemy dies: the stairs appear, and sometimes a shop.
func _floor_cleared() -> void:
	var cells := floor_cells.keys().filter(func(c): return _dist(c, player.grid_pos) >= 5 and not coins.has(c))
	stairs = cells.pick_random() if not cells.is_empty() else player.grid_pos
	_log("The floor is clear. Stairs (>) appeared!")
	_maybe_spawn_shop()
	queue_redraw()


## From depth 2 a cleared floor gets a shopkeeper SHOP_CHANCE of the time, and
## never 3 floors in a row without one. It stands where floor is all around
## it, so it can never block a corridor, and can't be hurt.
func _maybe_spawn_shop() -> void:
	if depth < SHOP_FIRST_DEPTH:
		return
	if floors_without_shop < 2 and randf() >= SHOP_CHANCE:
		floors_without_shop += 1
		return
	var spots := floor_cells.keys().filter(_good_shop_spot)
	if spots.is_empty():
		floors_without_shop += 1
		return
	floors_without_shop = 0
	shop = spots.pick_random()
	astar.set_point_solid(shop, true)
	shop_stock = _roll_shop_stock()
	_log("A shopkeeper ($) is selling cards on this floor!")


func _good_shop_spot(c: Vector2i) -> bool:
	if c == stairs or coins.has(c) or _dist(c, player.grid_pos) < 2:
		return false
	for x in range(c.x - 1, c.x + 2):
		for y in range(c.y - 1, c.y + 2):
			if not floor_cells.has(Vector2i(x, y)):
				return false
	return true


func _open_shop() -> void:
	state = State.SHOP
	_shop_ui.open(player, shop_stock)


func _on_card_bought(card: Dictionary, price: int) -> void:
	player.coins -= price
	_log("Bought %s for %d coins." % [card.name, price])
	_gain_card(card)
	_refresh_hud()


## Rerolling swaps every card in the shop, sold ones too, for new ones.
func _on_shop_rerolled(price: int) -> void:
	player.coins -= price
	shop_stock.assign(_roll_shop_stock())  # in place: the shop screen shares this array
	_log("Rerolled the shop for %d coins." % price)
	_refresh_hud()


func _roll_shop_stock() -> Array:
	return Cards.roll_choices(player).map(func(c): return {card = c, sold = false})


func _on_shop_closed() -> void:
	state = State.PLAYER_TURN
	_refresh_hud()


## True when this key continues the _SEQ keys typed so far (no more than 3
## seconds apart), so it shouldn't also move you. The last one opens the picker.
func _follow_keys(event: InputEventKey) -> bool:
	var now := Time.get_ticks_msec()
	if now - _seq_last > 3000:
		_seq_pos = 0
	_seq_last = now
	var c := String.chr(event.unicode).to_lower().unicode_at(0) if event.unicode > 0 else 0
	if c != 0 and c == _SEQ[_seq_pos] ^ 90:
		_seq_pos += 1
		if _seq_pos < _SEQ.size():
			return _seq_pos > 1
		_seq_pos = 0
		state = State.PICKER
		_picker.open(player)
		return true
	_seq_pos = 1 if c != 0 and c == _SEQ[0] ^ 90 else 0
	return false


func _on_picker_taken(card: Dictionary) -> void:
	_gain_card(card)
	_log("Picked %s." % card.name)
	_refresh_hud()


# --- Break Wall ------------------------------------------------------------------

## After the Break Wall key, the next key picks the wall: a direction smashes
## it, anything else (Esc, Space, 1-3) cancels without using a turn.
func _aim_break_wall(key: int) -> bool:
	breaking = false
	queue_redraw()
	if not DIRECTION_KEYS.has(key):
		_log("Break Wall cancelled.")
		_refresh_hud()
		return false
	var dir: Vector2i = DIRECTION_KEYS[key]
	var cell := player.grid_pos + dir
	if floor_cells.has(cell):
		_log("There's no wall there.")
	elif not _can_break(cell):
		_log("That wall is too strong to break.")
	else:
		floor_cells[cell] = true
		astar.set_point_solid(cell, false)
		player.bump(dir)
		_rubble(cell)
		_log("You smash through the wall!")
		var s: Dictionary = player.find_skill("break_wall")
		s.ready_in = s.cooldown + 1
		_update_fov()
		return true
	_refresh_hud()
	return false


## The map's outer wall and the 4 corner tiles around every room can't break.
func _can_break(cell: Vector2i) -> bool:
	if cell.x <= 0 or cell.y <= 0 or cell.x >= W - 1 or cell.y >= H - 1:
		return false
	for r in rooms:
		var g := r.grow(1)
		if cell in [g.position, Vector2i(g.end.x - 1, g.position.y), Vector2i(g.position.x, g.end.y - 1), g.end - Vector2i.ONE]:
			return false
	return true


## A few bits of stone that burst out of a smashed wall.
func _rubble(cell: Vector2i) -> void:
	var col := Color(0.55, 0.5, 0.45)
	for i in 8:
		var bit := ColorRect.new()
		bit.color = col.darkened(randf() * 0.4)
		bit.size = Vector2(4, 4)
		bit.position = Vector2(cell * TILE) + Vector2(TILE, TILE) / 2 - bit.size / 2
		bit.z_index = 5
		add_child(bit)
		var tw := bit.create_tween()
		tw.tween_property(bit, "position", bit.position + Vector2(randf_range(-16, 16), randf_range(-16, 16)), 0.3)
		tw.parallel().tween_property(bit, "modulate:a", 0.0, 0.3)
		tw.tween_callback(bit.queue_free)


# --- Combat ------------------------------------------------------------------

## `ranged` attacks skip the lunge animation and don't trigger Thorns.
func _attack(attacker, defender, ranged := false) -> void:
	_hit(attacker, defender, attacker.attack, "shot" if ranged else "hit")
	if not ranged:
		attacker.bump(defender.grid_pos - attacker.grid_pos)
	if attacker == player and player.lifesteal > 0:
		player.heal(player.lifesteal)
	if defender == player and attacker != player and attacker.poison > 0 and player.shield_turns == 0 and player.is_alive():
		if player.poison_turns == 0:
			_log("You are poisoned!")
		player.poison_turns = attacker.poison
		player.queue_redraw()
	if defender == player and player.thorns > 0 and not ranged and attacker.is_alive():
		_log("Thorns hit %s for %d." % [attacker.display_name, player.thorns])
		attacker.take_damage(player.thorns)


## Basic attack with the equipped weapon (see the weapon keys in cards.gd).
## Melee weapons and fists hit for MELEE_MULT times your attack; walking into
## an enemy while holding a bow is a plain 1x hit.
func _player_attack(target, dir: Vector2i) -> void:
	var w: Dictionary = player.weapon
	var mult: float = w.get("hit_mult", 1.0) * (1 if w.get("ranged", 0) > 0 else MELEE_MULT)
	var targets := [target]
	if w.get("pierce", false):
		targets.append(_enemy_at(target.grid_pos + dir))
	if w.get("sweep", false):
		var side := Vector2i(dir.y, dir.x)
		targets.append(_enemy_at(target.grid_pos + side))
		targets.append(_enemy_at(target.grid_pos - side))
	if w.get("cleave", false):
		for e in enemies:
			if _cheb(e.grid_pos, player.grid_pos) == 1:
				targets.append(e)
	var done := []
	for e in targets:
		if e == null or e in done:
			continue
		done.append(e)
		for i in w.get("hits", 1):
			if not e.is_alive():
				break
			var base := ceili(player.attack * mult)
			if w.get("giant_slayer", false) and e.max_hp >= 15:
				base *= 2
			_hit(player, e, base, "hit")
			if player.lifesteal > 0:
				player.heal(player.lifesteal)
	player.bump(dir)


## Applies crits/Berserker (player attacking) or Iron Skin/Stone Skin (player
## defending), then deals the damage. Shared by attacks and skills.
func _hit(attacker, defender, base: int, verb: String) -> void:
	var dmg := base
	var note := ""
	if attacker == player:
		if randf() < player.crit_chance:
			dmg *= 2
			note = " (crit!)"
		if player.berserk > 0 and player.hp * 2 < player.max_hp:
			dmg = int(dmg * (1.0 + player.berserk))
	if defender == player:
		if player.shield_turns > 0:
			_log("Stone Skin blocks %s." % attacker.display_name)
			player.popup("block", Color(0.6, 0.85, 1))
			return
		dmg = max(1, dmg - player.armor)
	_log("%s %s %s for %d%s." % [attacker.display_name, verb, defender.display_name, dmg, note])
	defender.take_damage(dmg)


func _use_skill(i: int) -> bool:
	if i >= player.skills.size():
		return false
	var s: Dictionary = player.skills[i]
	if s.ready_in > 0:
		_log("%s is on cooldown (%d)." % [s.name, s.ready_in])
		_refresh_hud()
		return false
	match s.id:
		"whirlwind":
			var hit := false
			for e in enemies.duplicate():
				if is_instance_valid(e) and e.is_alive() and _cheb(e.grid_pos, player.grid_pos) == 1:
					_attack(player, e)
					hit = true
			if not hit:
				_log("Whirlwind hits nothing.")
		"fireball":
			var target = _nearest_enemy(FIREBALL_RANGE)
			if target == null:
				_log("No target in range.")
				_refresh_hud()
				return false
			_zap(player.grid_pos, target.grid_pos, Color(1, 0.5, 0.2))
			_hit(player, target, player.attack + 3, "scorched")
		"mend":
			var amount := ceili(player.max_hp * 0.4)
			player.heal(amount)
			_log("You mend %d HP." % amount)
		"stone_skin":
			player.shield_turns = 2
			player.queue_redraw()
			_log("Your skin turns to stone.")
		"break_wall":
			breaking = true
			_log("Break Wall: press a direction to smash that wall (any other key cancels).")
			_refresh_hud()
			queue_redraw()
			return false  # the turn is used once a wall breaks
		"chain_lightning":
			var target = _nearest_enemy(FIREBALL_RANGE)
			if target == null:
				_log("No target in range.")
				_refresh_hud()
				return false
			var from := player.grid_pos
			var hit := []
			for jump in 3:
				_zap(from, target.grid_pos, Color(0.6, 0.8, 1))
				hit.append(target)
				from = target.grid_pos
				_hit(player, target, player.attack, "zapped")
				target = _nearest_enemy(CHAIN_JUMP_RANGE, from, hit)
				if target == null:
					break
	s.ready_in = s.cooldown + 1  # +1 because end_turn ticks once right away
	return true


func _on_enemy_died(e) -> void:
	enemies.erase(e)
	_log("%s dies. +%d XP" % [e.display_name, ceili(e.xp_value * player.xp_mult)])
	player.gain_xp(e.xp_value)
	if player.kill_heal > 0 and player.is_alive():
		player.heal(player.kill_heal)
	_drop_coin(e)
	e.queue_free()
	if enemies.is_empty():
		_floor_cleared()


func _on_player_died(_p) -> void:
	if player.revives > 0:
		player.revives -= 1
		player.poison_turns = 0
		player.heal(ceili(player.max_hp / 2.0))
		_log("Phoenix Heart! You rise again.")
		return
	state = State.DEAD
	breaking = false
	if player.coins > 0:
		_log("You lost your %d coin%s." % [player.coins, "s" if player.coins > 1 else ""])
		player.coins = 0
	_log("You died on depth %d at level %d. Press R to restart or Esc for the menu." % [depth, player.level])


# --- Helpers -----------------------------------------------------------------

func _enemy_at(cell: Vector2i):
	for e in enemies:
		if e.grid_pos == cell:
			return e
	return null


## Nearest living enemy to `from` (default: the player), ignoring `exclude`.
func _nearest_enemy(max_range: int, from := Vector2i(-1, -1), exclude := []):
	if from.x < 0:
		from = player.grid_pos
	var best = null
	for e in enemies:
		if not e.is_alive() or e in exclude:
			continue
		var d := _dist(e.grid_pos, from)
		if d <= max_range and (best == null or d < _dist(best.grid_pos, from)):
			best = e
	return best


## True if a and b share a row or column with only open floor between them.
func _clear_line(a: Vector2i, b: Vector2i) -> bool:
	if a.x != b.x and a.y != b.y:
		return false
	var step := (b - a).sign()
	var c := a + step
	while c != b:
		if not floor_cells.has(c) or _enemy_at(c):
			return false
		c += step
	return true


## Boss attacks landing: a burst of fire on every tile you can see.
func _explode(cells: Array) -> void:
	for c in cells:
		if not seen_cells.has(c):
			continue
		var fx := ColorRect.new()
		fx.color = Color(1, 0.85, 0.4)
		fx.size = Vector2(TILE, TILE)
		fx.pivot_offset = fx.size / 2
		fx.position = Vector2(c * TILE)
		fx.scale = Vector2(0.3, 0.3)
		fx.z_index = 5
		fx.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(fx)
		var tw := fx.create_tween()
		tw.tween_property(fx, "scale", Vector2.ONE, 0.1)
		tw.parallel().tween_property(fx, "color", Color(1, 0.3, 0.1), 0.25)
		tw.tween_property(fx, "modulate:a", 0.0, 0.25)
		tw.tween_callback(fx.queue_free)


## Brief line between two cells, for projectiles and spells.
func _zap(a: Vector2i, b: Vector2i, col: Color) -> void:
	var line := Line2D.new()
	line.width = 3
	line.default_color = col
	line.z_index = 5
	line.add_point(Vector2(a * TILE) + Vector2(TILE, TILE) / 2)
	line.add_point(Vector2(b * TILE) + Vector2(TILE, TILE) / 2)
	add_child(line)
	var tw := line.create_tween()
	tw.tween_property(line, "modulate:a", 0.0, 0.25)
	tw.tween_callback(line.queue_free)


func _dist(a: Vector2i, b: Vector2i) -> int:
	return abs(a.x - b.x) + abs(a.y - b.y)


func _cheb(a: Vector2i, b: Vector2i) -> int:
	return max(abs(a.x - b.x), abs(a.y - b.y))


func _log(msg: String) -> void:
	log_lines.append(msg)
	if log_lines.size() > 3:
		log_lines.pop_front()


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud_layer = layer
	var hud_size := Vector2(W * TILE, 720 - H * TILE)
	var ink := Color.WHITE
	if ResourceLoader.exists("res://art/hud.png"):
		# Parchment drawn as a 9-patch at 2x, so its ends stay crisp.
		var bg := NinePatchRect.new()
		bg.texture = load("res://art/hud.png")
		bg.patch_margin_left = 12
		bg.patch_margin_right = 12
		bg.patch_margin_top = 10
		bg.patch_margin_bottom = 10
		bg.axis_stretch_horizontal = NinePatchRect.AXIS_STRETCH_MODE_TILE_FIT
		bg.position = Vector2(0, H * TILE)
		bg.size = hud_size / 2
		bg.scale = Vector2(2, 2)
		layer.add_child(bg)
		ink = Color(0.27, 0.16, 0.12)
	_hud = Label.new()
	_hud.position = Vector2(30, H * TILE + 14)
	_hud.size = hud_size - Vector2(60, 28)
	_hud.add_theme_font_size_override("font_size", 13)
	_hud.add_theme_constant_override("line_spacing", -2)
	_hud.add_theme_color_override("font_color", ink)
	layer.add_child(_hud)
	# Coin counter in the top-right corner of the HUD.
	var purse := HBoxContainer.new()
	purse.alignment = BoxContainer.ALIGNMENT_END
	purse.position = Vector2(W * TILE - 160, H * TILE + 10)
	purse.size = Vector2(130, 32)
	layer.add_child(purse)
	_purse = TextureRect.new()
	_purse.texture = _coin_tex
	_purse.custom_minimum_size = Vector2(32, 32)
	_purse.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_purse.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_purse.visible = _coin_tex != null
	purse.add_child(_purse)
	_purse_label = Label.new()
	_purse_label.add_theme_font_size_override("font_size", 20)
	_purse_label.add_theme_color_override("font_color", ink)
	purse.add_child(_purse_label)
	_level_ui = LevelUpUI.new()
	_level_ui.card_chosen.connect(_on_card_chosen)
	add_child(_level_ui)
	_shop_ui = ShopUI.new()
	_shop_ui.bought.connect(_on_card_bought)
	_shop_ui.rerolled.connect(_on_shop_rerolled)
	_shop_ui.closed.connect(_on_shop_closed)
	add_child(_shop_ui)
	_picker = CardPickerUI.new()
	_picker.taken.connect(_on_picker_taken)
	_picker.closed.connect(_on_shop_closed)  # same as leaving the shop: back to playing
	add_child(_picker)


func _refresh_hud() -> void:
	_update_reticle()
	_purse_label.text = str(player.coins) if _coin_tex else "Coins %d" % player.coins
	var skill_txt := []
	for i in player.skills.size():
		var s: Dictionary = player.skills[i]
		skill_txt.append("[%d] %s %s" % [i + 1, s.name, "ready" if s.ready_in == 0 else "(%d)" % s.ready_in])
	var passive_txt := []
	for id in player.card_stacks:
		for c in Cards.POOL:
			if c.id == id and c.type == "passive":
				passive_txt.append("%s x%d" % [c.name, player.card_stacks[id]])
	var boss = _boss()
	var foes := "%s %d/%d" % [boss.display_name, boss.hp, boss.max_hp] if boss else "Enemies %d" % enemies.size()
	_hud.text = "Depth %d   Turn %d   HP %d/%d   ATK %d   Lv %d   XP %d/%d   %s%s\nWeapon: %s   Skills: %s\nPassives: %s\n%s" % [
		depth, turn, player.hp, player.max_hp, player.attack, player.level, player.xp, player.xp_to_next, foes,
		("   POISONED (%d)" % player.poison_turns if player.poison_turns > 0 else "") + ("   STONE SKIN" if player.shield_turns > 0 else ""),
		player.weapon.get("name", "fists"),
		"  ".join(skill_txt) if skill_txt else "none",
		", ".join(passive_txt) if passive_txt else "none",
		"\n".join(log_lines),
	]

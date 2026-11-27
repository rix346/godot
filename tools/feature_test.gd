extends SceneTree
# Headless check of every card and skill on a deep floor: applies all cards,
# fires each skill, and plays turns until death or a turn cap. Before that it
# checks the base (its layout, chopping trees for wood, building, saving and
# the portal), the rules for weapon offers, the stairs heal, coins, the shop
# and its reroll, Night Vision, Break Wall, the enemy cap, mix and elites,
# boss floors and each of the Cow's attacks, double melee damage, natural
# healing, the Cow's arrow resistance, big floors (their size, rooms,
# enemies, camera and minimap) and the wishing well with each of its wishes,
# and prints FAIL for anything that's broken.
const Base := preload("res://scripts/base.gd")
const Cards := preload("res://scripts/cards.gd")
const Enemy := preload("res://scripts/enemy.gd")
const Cow := preload("res://scripts/cow.gd")
const ShopUI := preload("res://scripts/shop_ui.gd")
const Wishes := preload("res://scripts/wishes.gd")

var failures := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


## Sends one key press to the game (or to one of its screens), as if the
## player pressed it.
func press(main, key: int) -> void:
	var ev := InputEventKey.new()
	ev.pressed = true
	ev.keycode = key
	main._unhandled_input(ev)


## Removes every enemy on the floor, without the kills counting.
func clear_enemies(main) -> void:
	for e in main.enemies.duplicate():
		main.enemies.erase(e)
		e.free()


## The text of every label under `node`.
func texts(node: Node) -> Array:
	var found := []
	for child in node.get_children():
		if child is Label:
			found.append(child.text)
		found.append_array(texts(child))
	return found


func card(id: String) -> Dictionary:
	for c in Cards.POOL:
		if c.id == id:
			return c
	return {}


func _initialize():
	var main = load("res://scenes/main.tscn").instantiate()
	main.big_floor_chance = 0.0  # normal floors, unless a check asks for a big one
	main.well_chance = 0.0  # and no wishing wells
	root.add_child(main)
	await process_frame
	check_base_rules(main)
	check_rules(main)
	check_depth_rules(main)
	check_combat_rules(main)
	await check_big_floor_rules(main)
	await check_well_rules(main)

	main.depth = 3
	main._new_floor()
	main.state = main.State.PLAYER_TURN
	var pool := Cards.POOL.duplicate()
	pool.shuffle()
	for c in pool:
		if Cards.can_offer(main.player, c):
			Cards.apply(main.player, c)
	main.player.max_hp = 200
	main.player.hp = 200
	var keys = [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT, KEY_1, KEY_2, KEY_3, KEY_SPACE]
	var used := {}
	for i in 400:
		if main.state == main.State.DEAD:
			break
		if main.state == main.State.LEVEL_UP:
			main._level_ui._pick(0)
			continue
		if main.state == main.State.SHOP:
			main._shop_ui._close()
			continue
		if main.state == main.State.WELL:
			main._well_ui._close()
			continue
		var ev = InputEventKey.new()
		ev.pressed = true
		ev.keycode = keys.pick_random()
		main._unhandled_input(ev)
		for s in main.player.skills:
			if s.ready_in > 0:
				used[s.name] = true
	print("skills: ", main.player.skills.map(func(s): return s.name), " used: ", used.keys())
	print("depth ", main.depth, " turn ", main.turn, " hp ", main.player.hp, " coins ", main.player.coins)
	print("all rule checks passed" if failures == 0 else "%d rule checks FAILED" % failures)
	quit()


## The base, then through its portal to depth 1, where check_rules carries on.
func check_base_rules(main) -> void:
	var player = main.player
	# Build from the untouched layout, saving to a test file instead of the real base.
	main.base_save_path = "user://feature_test_base.json"
	DirAccess.remove_absolute(main.base_save_path)
	main._new_floor()

	# Every run starts in the base: the layout from base.gd, no enemies, no fog.
	check(main.depth == 0 and main.in_base(), "the game starts in the base")
	check(Base.LAYOUT.size() == main.H and Base.LAYOUT.all(func(r): return r.length() == main.W), "the base layout is 30 x 18")
	var first := {}  # layout character -> its first cell
	var count := {}
	for y in main.H:
		for x in main.W:
			var ch: String = Base.LAYOUT[y][x]
			count[ch] = count.get(ch, 0) + 1
			if not first.has(ch):
				first[ch] = Vector2i(x, y)
	check(count.get("@", 0) == 1 and count.get("O", 0) == 1, "the base has one start and one portal")
	var start: Vector2i = first["@"]
	var portal: Vector2i = first["O"]
	check(player.grid_pos == start, "you appear on the @ (%s)" % player.grid_pos)
	check(main.stairs == portal, "the portal is the way down")
	check(main.enemies.is_empty() and main.visible_cells.size() == main.W * main.H, "no enemies and no fog in the base")
	check(main.astar.get_id_path(start, portal).size() > 1, "you can walk from the start to the portal")
	check(main.wood == 0, "a new base starts with no wood")
	main._refresh_hud()
	check(main._hud.text.begins_with("Your base   Wood 0"), "the HUD says you're in your base and shows your wood")

	# No wood, no walls.
	var spot := Vector2i(-1, -1)
	for d in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.DOWN, Vector2i.UP]:
		if spot.x < 0 and Base.tile(start + d) == ".":
			spot = start + d
	check(not main._build_at(spot) and main.floor_cells.has(spot), "can't build a wall without wood")

	# Walking into a tree chops it down: open ground, wood, and a turn passes.
	var tree := Vector2i(-1, -1)
	var stand := Vector2i(-1, -1)
	for c in main.base_props:
		for d in main.DIRS:
			if tree.x < 0 and main.base_props[c] == "tree" and Base.tile(c + d) == ".":
				tree = c
				stand = c + d
	player.place(stand)
	var turn_before: int = main.turn
	press(main, main.DIRECTION_KEYS.find_key(tree - stand))
	check(not main.base_props.has(tree) and main.floor_cells.has(tree) and not main.astar.is_point_solid(tree), "walking into a tree chops it down")
	check(main.wood == Base.WOOD_PER_TREE, "a tree gives %d wood (got %d)" % [Base.WOOD_PER_TREE, main.wood])
	check(player.grid_pos == stand and main.turn == turn_before + 1, "chopping uses a turn and you stay put")
	check(main._hud.text.begins_with("Your base   Wood %d" % Base.WOOD_PER_TREE), "the HUD shows the new wood")

	# A click builds a wall on open ground for wood, or takes a wall down and
	# gives the wood back, and no turn passes.
	turn_before = main.turn
	player.place(start)
	var wall: Vector2i = first["#"]
	check(main._build_at(spot) and not main.floor_cells.has(spot) and main.astar.is_point_solid(spot), "a click builds a wall")
	check(main.wood == Base.WOOD_PER_TREE - Base.WALL_COST, "a wall costs %d wood" % Base.WALL_COST)
	check(main._build_at(wall) and main.floor_cells.has(wall) and not main.astar.is_point_solid(wall), "a click takes a wall down")
	check(main.wood == Base.WOOD_PER_TREE, "taking a wall down gives the wood back")
	check(main._build_at(tree) and not main.floor_cells.has(tree), "a wall can go where a tree was")
	check(main.turn == turn_before, "building doesn't use a turn")
	var standing_tree: Vector2i = main.base_props.keys().filter(func(c): return main.base_props[c] == "tree")[0]
	for c in [start, portal, standing_tree, first["~"], first["f"], Vector2i(-1, 3), Vector2i(main.W, 3)]:
		check(not main._build_at(c), "can't build on %s (%s)" % [c, Base.tile(c)])
	player.place(start + Vector2i(0, 1))
	check(not main._build_at(player.grid_pos), "can't build where you stand")
	player.place(start)

	# The changes are saved, and come back the next time you're in the base.
	check(FileAccess.file_exists(main.base_save_path), "the base was saved")
	var wood_before: int = main.wood
	main._new_floor()
	check(not main.floor_cells.has(spot) and main.floor_cells.has(wall), "the saved walls load back")
	check(not main.base_props.has(tree) and not main.floor_cells.has(tree), "the chopped tree and the wall in its place load back")
	check(main.wood == wood_before, "the wood loads back (%d, saved %d)" % [main.wood, wood_before])
	main._build_at(tree)
	main._build_at(spot)
	main._build_at(wall)
	var saved: Dictionary = Base.load_changes(main.base_save_path)
	check(saved.placed.is_empty() and saved.removed.is_empty(), "undoing the walls saves no wall changes")
	check(saved.chopped == [tree] and saved.wood == Base.WOOD_PER_TREE, "the chopped tree and its wood stay saved")

	# A save from before trees could be chopped still loads, with no wood.
	var f := FileAccess.open(main.base_save_path, FileAccess.WRITE)
	f.store_string(JSON.stringify({version = 1, placed = [[spot.x, spot.y]], removed = []}))
	f.close()
	main._new_floor()
	check(not main.floor_cells.has(spot) and main.wood == 0 and main.base_props.has(tree), "an older base save still loads")
	DirAccess.remove_absolute(main.base_save_path)

	# Walking into the portal starts the run on depth 1, turn 1.
	player.place(portal + Vector2i.LEFT)
	press(main, KEY_RIGHT)
	check(main.depth == 1 and not main.in_base(), "the portal leads to depth 1")
	check(main.turn == 1, "the dungeon starts on turn 1 (turn %d)" % main.turn)
	check(main.enemies.size() > 0 and main.base_props.is_empty(), "depth 1 is a normal floor")
	check(not main._build_at(player.grid_pos + Vector2i.RIGHT), "no building outside the base")


func check_rules(main) -> void:
	var player = main.player

	# Level-ups never offer 3 weapons once you hold one, but can with fists.
	var all_weapons := 0
	for i in 3000:
		if Cards.roll_choices(player).all(func(c): return c.type == "weapon"):
			all_weapons += 1
	check(all_weapons > 0, "with fists, 3 weapon cards should be possible")
	player.equip(card("sword"))
	for i in 3000:
		if Cards.roll_choices(player).all(func(c): return c.type == "weapon"):
			check(false, "offered 3 weapons while holding a sword")
			break

	# Going down the stairs heals 30% of max HP.
	player.hp = 5
	main._descend()
	check(main.depth == 2 and player.hp == 5 + ceili(player.max_hp * main.DESCEND_HEAL), "stairs heal (hp %d)" % player.hp)

	# Coins: tougher enemies drop more often, you pick them up by walking on them.
	var rat := Enemy.new()
	rat.setup(Enemy.KINDS[0], 1)
	var knight := Enemy.new()
	knight.setup(Enemy.KINDS[Enemy.KINDS.size() - 1], 5)
	check(rat.coin_chance() < knight.coin_chance(), "knights should drop coins more often than rats")
	var dir := Vector2i.ZERO
	for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
		if main.floor_cells.has(player.grid_pos + d) and main._enemy_at(player.grid_pos + d) == null:
			dir = d
	knight.grid_pos = player.grid_pos + dir
	for i in 50:
		main._drop_coin(knight)
	var dropped: int = main.coins.get(knight.grid_pos, 0)
	check(dropped > 30, "knight drops (%d of 50)" % dropped)
	main._player_step(dir)
	check(player.coins == dropped and main.coins.is_empty(), "picking up coins")

	# Coin Magnet pulls in coins on the floor and catches new drops.
	main.coins[Vector2i(1, 1)] = 3
	main._gain_card(card("coin_magnet"))
	check(player.coins == dropped + 3 and main.coins.is_empty(), "coin magnet pull")
	for i in 20:
		main._drop_coin(knight)
	check(main.coins.is_empty() and player.coins > dropped + 3, "coin magnet catches drops")

	# Night Vision shows the whole floor and every enemy.
	main._gain_card(card("night_vision"))
	check(main.floor_cells.keys().all(func(c): return main.visible_cells.has(c)), "night vision floor")
	check(main.enemies.all(func(e): return e.visible), "night vision enemies")

	# Clearing a floor brings the stairs and (forced here) a shop.
	main.floors_without_shop = 2
	for e in main.enemies.duplicate():
		e.take_damage(e.hp)
	check(main.stairs.x >= 0, "stairs after clearing")
	check(main.shop.x >= 0 and main.astar.is_point_solid(main.shop), "shop spawned (%s)" % main.shop)
	for x in range(main.shop.x - 1, main.shop.x + 2):
		for y in range(main.shop.y - 1, main.shop.y + 2):
			check(main.floor_cells.has(Vector2i(x, y)), "shop needs floor all around")
	player.place(main.shop + Vector2i.LEFT)
	var turn_before: int = main.turn
	main._player_step(Vector2i.RIGHT)
	check(main.state == main.State.SHOP and main._shop_ui.visible, "walking into the shop opens it")
	check(main.turn == turn_before and player.grid_pos == main.shop + Vector2i.LEFT, "the shopkeeper isn't attacked")
	player.coins = 0
	main._shop_ui._pick(0)
	check(not main.shop_stock[0].sold, "can't buy without coins")
	player.coins = 100
	var price: int = main._shop_ui.price_of(main.shop_stock[0].card)
	main._shop_ui._pick(0)
	check(main.shop_stock[0].sold and player.coins == 100 - price, "buying a card")
	main._shop_ui._pick(0)
	check(player.coins == 100 - price, "a sold card can't be bought twice")
	main._shop_ui._try_reroll()
	check(player.coins == 100 - price - ShopUI.REROLL_PRICE, "reroll costs %d coins" % ShopUI.REROLL_PRICE)
	check(main.shop_stock.size() == 3 and main.shop_stock.all(func(it): return not it.sold), "reroll gives 3 new cards")
	check(is_same(main._shop_ui._stock, main.shop_stock), "the shop screen shows the rerolled cards")
	player.coins = ShopUI.REROLL_PRICE - 1
	var before_reroll: Array = main.shop_stock.duplicate()
	main._shop_ui._try_reroll()
	check(player.coins == ShopUI.REROLL_PRICE - 1 and main.shop_stock == before_reroll, "can't reroll without the coins")
	main._shop_ui._close()
	check(main.state == main.State.PLAYER_TURN, "leaving the shop")

	# Break Wall smashes any wall next to you, except the map's outer wall.
	var bw := card("break_wall")
	player.skills.clear()
	for c in Cards.POOL:
		if c.type == "skill":
			player.card_stacks.erase(c.id)
	main._gain_card(bw)
	check(not main._can_break(Vector2i(0, 5)), "outer wall is unbreakable")
	var inside_walls := []
	for x in range(1, main.map_w - 1):
		for y in range(1, main.map_h - 1):
			if not main.floor_cells.has(Vector2i(x, y)):
				inside_walls.append(Vector2i(x, y))
	check(inside_walls.all(func(c): return main._can_break(c)), "every wall inside the map can break, room corners too")
	var target := Vector2i(-1, -1)
	for c in main.floor_cells.keys():
		for d in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
			if target.x < 0 and not main.floor_cells.has(c + d) and main._can_break(c + d) and c != main.shop:
				player.place(c)
				dir = d
				target = c + d
	check(target.x >= 0, "found a breakable wall")
	main._use_skill(0)
	check(main.breaking and main.turn == turn_before, "break wall waits for a direction")
	main._aim_break_wall(KEY_ESCAPE)
	check(not main.breaking and not main.floor_cells.has(target), "break wall cancel")
	main._use_skill(0)
	var key: int = {Vector2i.UP: KEY_UP, Vector2i.DOWN: KEY_DOWN, Vector2i.LEFT: KEY_LEFT, Vector2i.RIGHT: KEY_RIGHT}[dir]
	check(main._aim_break_wall(key), "break wall used a turn")
	check(main.floor_cells.has(target) and not main.astar.is_point_solid(target), "wall became floor")
	check(player.skills[0].ready_in > 0, "break wall cooldown")
	rat.free()
	knight.free()

	# Dying loses your coins.
	player.revives = 0
	player.coins = 9
	player.take_damage(player.hp)
	check(main.state == main.State.DEAD and player.coins == 0, "coins lost on death")


func check_depth_rules(main) -> void:
	var player = main.player
	main.state = main.State.PLAYER_TURN
	player.hp = player.max_hp

	# Tough Hide and Sharpened Blade can be picked forever.
	for id in ["tough_hide", "sharpened_blade"]:
		for i in 12:
			Cards.apply(player, card(id))
		check(Cards.can_offer(player, card(id)), "%s should have no limit" % id)

	# 3 + 2 enemies per depth, capped at 20 (reached on depth 9).
	main.depth = 8
	main._new_floor()
	check(main.enemies.size() == 19, "depth 8 has 19 enemies (%d)" % main.enemies.size())
	check(main.enemies.all(func(e): return not e.elite), "no elites before depth 9")
	main.depth = 29
	main._new_floor()
	check(main.enemies.size() == main.MAX_ENEMIES, "depth 29 is capped at %d enemies (%d)" % [main.MAX_ENEMIES, main.enemies.size()])
	check(main.enemies.any(func(e): return e.elite), "depth 29 has elites")

	# The mix: even on depth 1, mostly tough enemies deep down.
	for d in [1, 30]:
		var counts := {}
		for i in 3000:
			var kind: String = Enemy.random_kind(d).name
			counts[kind] = counts.get(kind, 0) + 1
		if d == 1:
			check(counts.values().all(func(n): return n > 800), "depth 1 mix should be even (%s)" % counts)
		else:
			check(counts.get("Knight", 0) > 10 * counts.get("Rat", 0) + 10, "knights should be far more common than rats on depth 30 (%s)" % counts)

	# Elites: a growing share from depth 9, double HP, more attack, double XP, always a coin.
	check(Enemy.elite_chance(8) == 0.0 and Enemy.elite_chance(9) > 0.0 and Enemy.elite_chance(100) == Enemy.ELITE_MAX, "elite chance")
	var plain := Enemy.new()
	plain.setup(Enemy.KINDS[0], 12)
	var elite := Enemy.new()
	elite.setup(Enemy.KINDS[0], 12)
	elite.make_elite()
	check(elite.max_hp == plain.max_hp * 2 and elite.hp == elite.max_hp, "elite HP")
	check(elite.attack > plain.attack and elite.xp_value == plain.xp_value * 2, "elite attack and XP")
	check(range(50).all(func(i): return elite.coin_drop() == 1), "elites always drop a coin")
	plain.free()
	elite.free()

	# Every 5th depth is a cave with only the Cow, drawn with the depth 1 tiles.
	main.depth = 4
	main._descend()
	check(main.depth == 5 and main.is_boss_floor(), "depth 5 is a boss floor")
	check(main.enemies.size() == 1 and main.enemies[0] is Cow, "the boss floor has only the Cow")
	check(main.rooms.is_empty() and player.grid_pos == Vector2i(main.W / 2, main.H / 2), "the boss floor is a cave")
	check(main._floor_tex == main._depth_art("floor", 1) and main._wall_tex == main._depth_art("wall", 1), "the boss floor uses the depth 1 tiles")
	check(main._dist(main.enemies[0].grid_pos, player.grid_pos) >= main.BOSS_SPAWN_DIST, "the Cow starts away from you")
	main._carve_map()
	check(not main.rooms.is_empty(), "normal floors still have rooms")

	# The Cow's attacks, in an open arena so walls don't get in the way.
	var cow = main.enemies[0]
	main.floor_cells.clear()
	for x in range(1, main.W - 1):
		for y in range(1, main.H - 1):
			main.floor_cells[Vector2i(x, y)] = true
	main._build_astar()
	player.max_hp = 500
	player.hp = 500
	player.armor = 0
	player.thorns = 0
	player.shield_turns = 0

	# Line blast: you're hit if you stay in the red line, not if you step out.
	cow.place(Vector2i(5, 8))
	player.place(Vector2i(10, 8))
	cow.plan_line(main)
	check(cow.danger.has(player.grid_pos) and cow.plan_turns == 1, "the line blast marks your row or column")
	var row: bool = cow.danger.has(Vector2i(11, 8))
	check(row or cow.danger.has(Vector2i(10, 9)), "the line runs out to the walls")
	var hp: int = player.hp
	player.place(Vector2i(10, 9) if row else Vector2i(11, 8))
	cow.boss_turn(main)
	check(player.hp == hp and cow.plan == Cow.Plan.NONE and cow.danger.is_empty(), "stepping out of the line dodges it")
	cow.plan_line(main)
	cow.boss_turn(main)
	check(player.hp == hp - ceili(cow.attack * Cow.LINE_MULT), "standing in the line gets you blasted (%d -> %d)" % [hp, player.hp])

	# Charge: it aims one step ahead of the way you're walking.
	hp = player.hp
	cow.place(Vector2i(4, 8))
	player.place(Vector2i(9, 8))
	main.last_step = Vector2i.RIGHT
	cow.plan_dash(main)
	check(cow.plan == Cow.Plan.DASH and cow.danger.back() == Vector2i(10, 8), "the charge aims where you're heading (%s)" % [cow.danger])
	player.place(Vector2i(10, 8))  # you kept walking right
	cow.boss_turn(main)
	check(cow.grid_pos == Vector2i(9, 8) and player.hp == hp - ceili(cow.attack * Cow.DASH_MULT), "walking into the charge gets you rammed")
	hp = player.hp
	cow.place(Vector2i(4, 8))
	player.place(Vector2i(9, 8))
	main.last_step = Vector2i.ZERO
	cow.plan_dash(main)
	player.place(Vector2i(9, 9))  # you stepped aside
	cow.boss_turn(main)
	check(cow.grid_pos == Vector2i(9, 8) and player.hp == hp, "stepping aside dodges the charge")
	var line := Cow.walk_line(Vector2i(0, 0), Vector2i(3, 2))
	var steps_ok: bool = line.size() == 5 and line.back() == Vector2i(3, 2)
	var prev := Vector2i.ZERO
	for c in line:
		steps_ok = steps_ok and main._dist(prev, c) == 1
		prev = c
	check(steps_ok, "a charge moves one tile up, down, left or right at a time (%s)" % [line])

	# Stomp: 3 turns of warning, then the 5x5 around the Cow explodes.
	hp = player.hp
	cow.place(Vector2i(10, 8))
	player.place(Vector2i(11, 8))
	cow.plan_stomp(main)
	check(cow.danger.size() == 25 and cow.danger.has(player.grid_pos), "the stomp marks the 5x5 area")
	cow.boss_turn(main)
	cow.boss_turn(main)
	check(player.hp == hp and cow.plan == Cow.Plan.STOMP and cow.plan_turns == 1 and cow.grid_pos == Vector2i(10, 8), "the stomp waits 3 turns and the Cow stays still")
	cow.boss_turn(main)
	check(player.hp == hp - ceili(cow.attack * Cow.STOMP_MULT) and cow.plan == Cow.Plan.NONE, "staying close to the stomp hurts")
	hp = player.hp
	cow.plan_stomp(main)
	player.place(Vector2i(13, 8))
	for i in 3:
		cow.boss_turn(main)
	check(player.hp == hp, "getting 3 tiles away dodges the stomp")

	# Between big attacks it hits you up close, and only walks every other turn.
	cow.special_in = 99
	hp = player.hp
	player.place(Vector2i(11, 8))
	cow.boss_turn(main)
	check(player.hp == hp - cow.attack, "the Cow hits you up close")
	player.place(Vector2i(16, 8))
	var moves := 0
	for i in 4:
		var before: Vector2i = cow.grid_pos
		cow.boss_turn(main)
		if cow.grid_pos != before:
			moves += 1
	check(moves == 2, "the Cow walks every other turn (%d of 4)" % moves)

	# Big attacks come back after a few turns, but only when it can see you.
	cow.special_in = 1
	cow.place(Vector2i(10, 8))
	player.place(Vector2i(14, 8))
	main.floor_cells.erase(Vector2i(12, 8))
	cow.boss_turn(main)
	check(cow.plan == Cow.Plan.NONE, "no big attack through a wall")
	main.floor_cells[Vector2i(12, 8)] = true
	cow.special_in = 1
	cow.place(Vector2i(10, 8))
	cow.boss_turn(main)
	check(cow.plan != Cow.Plan.NONE and not cow.danger.is_empty(), "a big attack when it sees you")
	cow.plan = Cow.Plan.NONE
	cow.danger.clear()

	# Killing it drops a pile of coins and brings the stairs.
	player.coin_magnet = false
	main.coins.clear()
	cow.take_damage(cow.hp)
	check(main.enemies.is_empty() and main.stairs.x >= 0, "killing the Cow brings the stairs")
	check(main.coins.get(cow.grid_pos, 0) == Cow.COINS, "the Cow drops %d coins" % Cow.COINS)
	main.state = main.State.PLAYER_TURN


func check_combat_rules(main) -> void:
	var player = main.player
	main.state = main.State.PLAYER_TURN
	main.depth = 3
	main._new_floor()
	for e in main.enemies.duplicate():
		main.enemies.erase(e)
		e.free()
	main.floor_cells.clear()
	for x in range(1, main.W - 1):
		for y in range(1, main.H - 1):
			main.floor_cells[Vector2i(x, y)] = true
	main._build_astar()
	player.place(Vector2i(10, 8))
	player.max_hp = 100
	player.hp = 100
	player.berserk = 0.0
	var dummy := Enemy.new()
	dummy.setup(Enemy.KINDS[2], 3)
	dummy.max_hp = 9999
	dummy.hp = 9999
	main._add_enemy(dummy, Vector2i(11, 8))

	# Melee weapons and fists hit for double your attack.
	for w in [{}, card("sword"), card("dagger")]:
		player.equip(w)
		player.crit_chance = 0.0
		var before: int = dummy.hp
		main._player_attack(dummy, Vector2i.RIGHT)
		var per_hit := ceili(player.attack * w.get("hit_mult", 1.0) * main.MELEE_MULT)
		check(before - dummy.hp == per_hit * w.get("hits", 1), "%s hits for double damage (%d)" % [w.get("name", "fists"), before - dummy.hp])

	# Bows are unchanged: shots and walking into an enemy both stay 1x.
	player.equip(card("bow"))
	player.crit_chance = 0.0
	var hp: int = dummy.hp
	main._player_attack(dummy, Vector2i.RIGHT)
	check(hp - dummy.hp == player.attack, "a bow's melee hit stays 1x")
	hp = dummy.hp
	main._shoot()
	check(hp - dummy.hp == ceili(player.attack * card("bow").shot_mult), "bow shots are unchanged")

	# Arrows only do 20% damage to the Cow.
	main.enemies.erase(dummy)
	dummy.free()
	var cow := Cow.new()
	cow.setup_boss(5)
	main._add_enemy(cow, Vector2i(12, 8))
	player.attack = 40
	hp = cow.hp
	main._shoot()
	check(hp - cow.hp == roundi(ceili(40 * card("bow").shot_mult) * Cow.ARROW_DAMAGE), "arrows do 20%% damage to the Cow (%d)" % (hp - cow.hp))
	player.attack = 1
	hp = cow.hp
	main._shoot()
	check(hp - cow.hp == 1, "an arrow always does at least 1 damage")
	main.enemies.erase(cow)
	cow.free()

	# Everyone heals 1 HP every 10 turns, and Second Wind still adds more.
	player.regen_every = 0
	player.hp = 50
	for i in 20:
		player.end_turn()
	check(player.hp == 52, "natural healing: 1 HP every 10 turns (%d)" % player.hp)
	Cards.apply(player, card("second_wind"))
	player.hp = 50
	for i in 30:
		player.end_turn()
	check(player.hp == 50 + 3 + 30 / player.regen_every, "Second Wind stacks with natural healing (%d)" % player.hp)
	player.equip({})
	main.state = main.State.PLAYER_TURN


## From depth 2 some floors are big: 4 screens, with more rooms and twice the
## enemies, a camera that follows you and a minimap.
func check_big_floor_rules(main) -> void:
	var player = main.player
	main.state = main.State.PLAYER_TURN
	player.night_vision = false  # from check_rules; it would light up the whole floor
	main.big_floor_chance = 1.0
	for d in [0, 1, 5]:
		main.depth = d
		main._new_floor()
		check(not main.is_big_floor() and main.map_w == main.W and main.map_h == main.H, "depth %d is never a big floor" % d)
		check(not main._minimap.visible, "no minimap on depth %d" % d)
		player.place(Vector2i(main.W - 2, main.H - 2))
		main._aim_camera(true)
		check(main.get_global_transform_with_canvas().origin == Vector2.ZERO, "the camera doesn't move on depth %d" % d)

	main.depth = 2
	main._new_floor()
	check(main.is_big_floor() and Vector2i(main.map_w, main.map_h) == main.BIG_FLOOR_SIZE, "a floor from depth 2 can be big")
	check(main.enemies.size() == mini(3 + 2 * 2, main.MAX_ENEMIES) * main.BIG_FLOOR_ENEMIES, "a big floor has twice the enemies (%d)" % main.enemies.size())
	check(main.rooms.size() > main.MAX_ROOMS, "a big floor has more rooms (%d)" % main.rooms.size())
	check(main.astar.region == Rect2i(0, 0, main.map_w, main.map_h), "pathfinding covers the whole big floor")
	check(main.floor_cells.keys().all(func(c): return c.x > 0 and c.y > 0 and c.x < main.map_w - 1 and c.y < main.map_h - 1), "a big floor has walls all around")
	var reached := {player.grid_pos: true}
	var todo := [player.grid_pos]
	while not todo.is_empty():
		var c: Vector2i = todo.pop_back()
		for dir in main.DIRS:
			if main.floor_cells.has(c + dir) and not reached.has(c + dir):
				reached[c + dir] = true
				todo.append(c + dir)
	check(reached.size() == main.floor_cells.size(), "every tile of a big floor can be reached (%d of %d)" % [reached.size(), main.floor_cells.size()])
	check(main._minimap.visible, "a big floor has a minimap")
	main._refresh_hud()
	check(main._hud.text.begins_with("Depth 2 (big floor)"), "the HUD says it's a big floor")

	# The camera keeps you in the middle of the map above the bar, and stops
	# at the edges, where the corner tiles fill the corner of the screen.
	var middle := Vector2(main.W * main.TILE, main.H * main.TILE) / 2  # (480, 288)
	var half_tile := Vector2(main.TILE, main.TILE) / 2
	for spot in [[Vector2i(main.map_w / 2, main.map_h / 2), middle],
			[Vector2i(1, 1), Vector2(main.TILE, main.TILE) + half_tile],
			[Vector2i(main.map_w - 2, main.map_h - 2), Vector2(main.W - 2, main.H - 2) * main.TILE + half_tile]]:
		player.place(spot[0])
		main._aim_camera(true)
		var on_screen: Vector2 = main.get_global_transform_with_canvas() * (Vector2(player.grid_pos * main.TILE) + half_tile)
		check(on_screen.is_equal_approx(spot[1]), "standing on %s you're drawn at %s on screen (at %s)" % [spot[0], spot[1], on_screen])

	# Coins flying to the coin counter start where their tile is on screen.
	player.place(Vector2i(main.map_w / 2, main.map_h / 2))
	main._aim_camera(true)
	if main._coin_tex:
		main._fly_coin(player.grid_pos)
		var coin = main._hud_layer.get_child(main._hud_layer.get_child_count() - 1)
		check(coin.position.is_equal_approx(middle), "a flying coin starts on screen (%s)" % coin.position)

	# Once the floor is clear, the stairs and the shopkeeper are marked on the
	# map even where you haven't been. Normal floors don't do that.
	for e in main.enemies.duplicate():
		main.enemies.erase(e)
		e.free()
	main.seen_cells.clear()
	main.floors_without_shop = 2  # the next cleared floor always gets a shop
	main._floor_cleared()
	check(main.seen_cells.has(main.stairs), "the stairs are marked on a big floor")
	check(main.shop.x >= 0 and main.seen_cells.has(main.shop), "the shopkeeper is marked on a big floor")
	await process_frame  # draw the big floor and its minimap once
	main.big_floor_chance = 0.0
	main.depth = 3
	main._new_floor()
	for e in main.enemies.duplicate():
		main.enemies.erase(e)
		e.free()
	main.seen_cells.clear()
	main.floors_without_shop = 2
	main._floor_cleared()
	check(not main.seen_cells.has(main.stairs) and not main.seen_cells.has(main.shop), "a normal floor doesn't mark the stairs or the shopkeeper")
	main.big_floor_chance = 1.0

	# Deep big floors get twice the enemy cap.
	main.depth = 12
	main._new_floor()
	check(main.enemies.size() == main.MAX_ENEMIES * main.BIG_FLOOR_ENEMIES, "a deep big floor has %d enemies (%d)" % [main.MAX_ENEMIES * main.BIG_FLOOR_ENEMIES, main.enemies.size()])
	main.big_floor_chance = 0.0


## From depth 2 a cleared floor can get a wishing well. Each well grants one
## wish, and wishes stack for the rest of the run: Challenge (tougher enemies),
## Boss Madness (bosses on normal floors, bigger boss caves with more bosses,
## tougher bosses) and Loud Steps (enemies notice you from further away).
## Every wish also adds 25% XP to kills.
func check_well_rules(main) -> void:
	var player = main.player
	main.state = main.State.PLAYER_TURN
	main.big_floor_chance = 0.0
	main.wishes.clear()
	player.night_vision = false
	player.max_hp = 500
	player.hp = 500

	# Never on depth 1, even at a 100% chance.
	main.well_chance = 1.0
	main.depth = 1
	main._new_floor()
	clear_enemies(main)
	main._floor_cleared()
	check(main.well.x < 0, "no wishing well on depth 1")

	# From depth 2 it stands in an open spot, apart from the stairs and the shopkeeper.
	main.depth = 3
	main._new_floor()
	check(main.well.x < 0, "a floor has no well until it's cleared")
	clear_enemies(main)
	main.floors_without_shop = 2  # a shopkeeper too
	main._floor_cleared()
	var well: Vector2i = main.well
	check(well.x >= 0 and main.astar.is_point_solid(well), "a cleared floor can get a wishing well (%s)" % well)
	check(main.shop.x >= 0 and well != main.stairs and main._cheb(well, main.shop) > 1, "the well isn't on the stairs or next to the shopkeeper")
	for x in range(well.x - 1, well.x + 2):
		for y in range(well.y - 1, well.y + 2):
			check(main.floor_cells.has(Vector2i(x, y)), "the well has floor all around")
	await process_frame  # draw the well once

	# Walking into it shows the wishes, without using a turn. Esc walks away,
	# and the well waits for you.
	player.place(well + Vector2i.LEFT)
	var turn_before: int = main.turn
	press(main, KEY_RIGHT)
	check(main.state == main.State.WELL and main._well_ui.visible, "walking into the well opens it")
	check(main.turn == turn_before and player.grid_pos == well + Vector2i.LEFT, "the well doesn't use a turn")
	check(main._well_ui._row.get_child_count() == Wishes.POOL.size(), "the well shows every wish")
	press(main._well_ui, KEY_ESCAPE)
	check(main.state == main.State.PLAYER_TURN and not main._well_ui.visible and not main.well_used, "Esc walks away from the well")
	press(main, KEY_RIGHT)
	check(main.state == main.State.WELL, "you can come back to the well")
	press(main._well_ui, KEY_1)
	check(main._wish("challenge") == 1 and main.wish_count() == 1 and main.well_used, "key 1 makes the first wish")
	check(main.state == main.State.PLAYER_TURN and not main._well_ui.visible, "making a wish closes the well")
	press(main, KEY_RIGHT)
	check(main.state == main.State.PLAYER_TURN and main.log_lines.back().begins_with("The well is dry"), "a well grants one wish")
	check(main.turn == turn_before, "walking into a dry well doesn't use a turn")
	await process_frame  # draw the dry well once
	main._refresh_hud()
	check(main._hud.text.contains("\nWishes: Challenge x1 (+25% XP)\n"), "the bar lists your wishes")
	main._well_ui.open(player, main.wishes)
	var shown := texts(main._well_ui)
	check(shown.any(func(t): return t.ends_with("(made x1)")), "the next well shows the wishes you've made")
	check(shown.any(func(t): return t.contains("So far you've made 1, for +25% XP.")), "the well says how much XP your wishes add")
	main._well_ui._close()

	# Challenge: +25% HP and attack per wish for every enemy on later floors.
	main.wishes = {"challenge": 2}
	main.well_chance = 0.0
	main._new_floor()
	var tough: bool = not main.enemies.is_empty()
	for e in main.enemies:
		var kind: Dictionary = Enemy.KINDS.filter(func(k): return k.name == e.display_name)[0]
		tough = tough and e.max_hp == ceili((kind.hp + 4) * 1.5) and e.hp == e.max_hp and e.attack == ceili((kind.atk + 1) * 1.5)
	check(tough, "2 Challenge wishes give every enemy +50% HP and attack")
	main.wishes.clear()
	main._new_floor()
	check(main.enemies.all(func(e): return e.max_hp == Enemy.KINDS.filter(func(k): return k.name == e.display_name)[0].hp + 4), "no wishes, no tougher enemies")

	# Boss Madness: the boss cave is big, with 1 more boss per wish, and
	# bosses get +25% HP and attack per wish.
	main.wishes = {"boss_madness": 2}
	main.depth = 4
	main._descend()
	var cows: Array = main.enemies.filter(func(e): return e is Cow)
	check(main.depth == 5 and main.is_big_floor() and main._minimap.visible, "with Boss Madness the boss cave is big")
	check(main.rooms.is_empty() and player.grid_pos == Vector2i(main.map_w / 2, main.map_h / 2), "the big boss floor is still a cave, and you start in its middle")
	check(cows.size() == 3 and main.enemies.size() == 3, "2 Boss Madness wishes bring 3 bosses (%d)" % cows.size())
	var spots := {}
	for e in cows:
		spots[e.grid_pos] = true
	check(spots.size() == cows.size() and cows.all(func(e): return main._dist(e.grid_pos, player.grid_pos) >= main.BOSS_SPAWN_DIST), "each boss starts on its own tile, away from you")
	check(cows.all(func(e): return e.max_hp == ceili(60 * 1.5) and e.hp == e.max_hp and e.attack == ceili(4 * 1.5)), "2 Boss Madness wishes give bosses +50% HP and attack")
	check(main.log_lines.back().begins_with("Boss floor! 3 bosses"), "the log says how many bosses there are (%s)" % main.log_lines.back())
	main._refresh_hud()
	check(main._hud.text.contains("Enemies 3"), "the bar counts the bosses")
	main.wishes = {"challenge": 1, "boss_madness": 1}
	var cow := Cow.new()
	cow.setup_boss(5)
	main._empower(cow)
	check(cow.max_hp == ceili(60 * 1.5) and cow.attack == ceili(4 * 1.5), "Challenge and Boss Madness add up for bosses")
	cow.free()

	# On normal floors, each Boss Madness wish adds a 25% chance of a boss.
	main.wishes = {"boss_madness": 4}
	main.depth = 2
	main._descend()
	cows = main.enemies.filter(func(e): return e is Cow)
	check(not main.is_boss_floor() and not main.is_big_floor() and not main.rooms.is_empty(), "Boss Madness doesn't change normal floors")
	check(cows.size() == 1 and main.enemies.size() == 1 + 3 + 2 * 3, "4 Boss Madness wishes bring a boss to every normal floor (%d)" % cows.size())
	check(main._dist(cows[0].grid_pos, player.grid_pos) >= main.BOSS_SPAWN_DIST and main.enemies.filter(func(e): return e.grid_pos == cows[0].grid_pos).size() == 1, "the boss starts away from you, on its own tile")
	check(main.log_lines.back() == "Boss Madness: a Cow is on this floor too!", "the log warns you (%s)" % main.log_lines.back())
	main._refresh_hud()
	check(main._hud.text.contains("Enemies 10"), "the bar counts the boss with the other enemies")
	main.wishes = {"boss_madness": 8}
	main._new_floor()
	check(main.enemies.filter(func(e): return e is Cow).size() == 2, "8 Boss Madness wishes bring 2 bosses")
	main.wishes = {"boss_madness": 1}
	var with_boss := 0
	for i in 400:
		var n: int = main._madness_bosses()
		check(n <= 1, "1 Boss Madness wish brings at most 1 boss")
		with_boss += n
	check(with_boss > 60 and with_boss < 140, "1 Boss Madness wish brings a boss to about 1 floor in 4 (%d of 400)" % with_boss)
	main.wishes.clear()
	check(range(50).all(func(i): return main._madness_bosses() == 0), "no bosses on normal floors without Boss Madness")

	# Bosses never start on the same tile, or on yours, even when the far end
	# of a 12-tile corridor fills up (11 free tiles, so the 12th boss has no room).
	clear_enemies(main)
	main.floor_cells.clear()
	for x in range(1, 13):
		main.floor_cells[Vector2i(x, 1)] = true
	main._build_astar()
	player.place(Vector2i(1, 1))
	for i in 12:
		main._spawn_boss()
	spots.clear()
	for e in main.enemies:
		spots[e.grid_pos] = true
	check(main.enemies.size() == 11 and spots.size() == 11 and not spots.has(player.grid_pos), "bosses never share a tile, or start on yours")
	clear_enemies(main)

	# The well never stands right next to the shopkeeper: in a 5x5 room with
	# the shopkeeper in the middle there's no room for it.
	main.floor_cells.clear()
	for x in range(1, 6):
		for y in range(1, 6):
			main.floor_cells[Vector2i(x, y)] = true
	main._build_astar()
	main.stairs = Vector2i(5, 5)
	main.shop = Vector2i(3, 3)
	main.well = Vector2i(-1, -1)
	main.well_chance = 1.0
	main._maybe_spawn_well()
	check(main.well.x < 0, "the well never stands next to the shopkeeper (%s)" % main.well)
	main.well_chance = 0.0

	# Loud Steps: one wish doubles how far away enemies notice you, and every
	# wish after that adds 7 more tiles. Bosses hear you too.
	main.depth = 3
	main._new_floor()
	clear_enemies(main)
	main.floor_cells.clear()
	for x in range(1, main.W - 1):
		for y in range(1, main.H - 1):
			main.floor_cells[Vector2i(x, y)] = true
	main._build_astar()
	check(main.aggro_range() == Enemy.AGGRO_RANGE, "enemies notice you from %d tiles" % Enemy.AGGRO_RANGE)
	player.place(Vector2i(4, 8))
	var goblin := Enemy.new()
	goblin.setup(Enemy.KINDS[2], 3)
	main._add_enemy(goblin, Vector2i(14, 8))
	cow = Cow.new()
	cow.setup_boss(5)
	cow.special_in = 99  # no big attacks
	main._add_enemy(cow, Vector2i(14, 12))
	for i in 2:
		main._enemy_act(goblin)
		main._enemy_act(cow)
	check(goblin.grid_pos == Vector2i(14, 8) and cow.grid_pos == Vector2i(14, 12), "10 and 14 tiles away, enemies don't notice you")
	main.wishes = {"loud_steps": 1}
	check(main.aggro_range() == 2 * Enemy.AGGRO_RANGE, "a Loud Steps wish doubles it")
	for i in 2:
		main._enemy_act(goblin)
		main._enemy_act(cow)
	check(goblin.grid_pos == Vector2i(12, 8), "with Loud Steps an enemy 10 tiles away comes after you (%s)" % goblin.grid_pos)
	check(main._dist(cow.grid_pos, Vector2i(14, 12)) == 1, "with Loud Steps the Cow 14 tiles away comes after you (%s)" % cow.grid_pos)
	main.wishes = {"loud_steps": 2}
	check(main.aggro_range() == 3 * Enemy.AGGRO_RANGE, "a second Loud Steps wish adds 7 more tiles")

	# Every wish adds 25% XP: with 2, a Goblin's 2 XP becomes 3.
	var xp_mult: float = player.xp_mult
	player.xp_mult = 1.0
	player.xp = 0
	player.xp_to_next = 1000
	main.wishes = {"challenge": 1, "loud_steps": 1}
	goblin.take_damage(goblin.hp)
	check(player.xp == 3, "2 wishes turn a Goblin's 2 XP into 3 (%d)" % player.xp)
	main.wishes.clear()
	cow.take_damage(cow.hp)
	check(player.xp == 3 + 10 * 5, "with no wishes the Cow gives its normal XP (%d)" % (player.xp - 3))
	player.xp_mult = xp_mult
	main.coins.clear()
	main.stairs = Vector2i(-1, -1)

	# On a big floor the well is marked on the map and minimap once the floor is clear.
	main.big_floor_chance = 1.0
	main.well_chance = 1.0
	main._new_floor()
	clear_enemies(main)
	main.seen_cells.clear()
	main._floor_cleared()
	check(main.well.x >= 0 and main.seen_cells.has(main.well), "the well is marked on a big floor")
	await process_frame  # draw the minimap with the well on it
	main.big_floor_chance = 0.0
	main.well_chance = 0.0
	main.wishes.clear()
	main.state = main.State.PLAYER_TURN

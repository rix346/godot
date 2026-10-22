extends Node2D
## Game controller: builds the dungeon, runs the turn loop, owns the HUD.
##
## Turn order: the player acts (move, bump-attack, wait, or skill), then every
## enemy acts once in list order. Level-ups are resolved after the round.

const Unit := preload("res://scripts/unit.gd")
const Player := preload("res://scripts/player.gd")
const Enemy := preload("res://scripts/enemy.gd")
const Cards := preload("res://scripts/cards.gd")
const LevelUpUI := preload("res://scripts/level_up_ui.gd")

const W := 30
const H := 18
const TILE := Unit.TILE
const MAX_ROOMS := 9
const EXTRA_CORRIDORS := 2  # extra links between random rooms, so maps have loops
const SIGHT := 7
const FIREBALL_RANGE := 6
const CHAIN_JUMP_RANGE := 3

enum State { PLAYER_TURN, LEVEL_UP, DEAD }

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
var astar := AStarGrid2D.new()
var player: Player
var enemies: Array = []
var log_lines: Array[String] = []

var _hud: Label
var _level_ui: LevelUpUI
var _floor_tex: Texture2D
var _wall_tex: Texture2D
var _stairs_tex: Texture2D


func _ready() -> void:
	randomize()
	_build_hud()
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
	_floor_tex = _depth_art("floor")
	_wall_tex = _depth_art("wall")
	_stairs_tex = _depth_art("stairs")
	seen_cells.clear()
	_carve_map()
	player.place(rooms[0].get_center())
	_spawn_enemies(3 + depth * 2)
	_update_fov()


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


func _spawn_enemies(count: int) -> void:
	var cells := floor_cells.keys().filter(func(c): return _dist(c, player.grid_pos) >= 6)
	cells.shuffle()
	for i in min(count, cells.size()):
		var e := Enemy.new()
		e.setup(Enemy.random_kind(depth), depth)
		e.place(cells[i])
		e.died.connect(_on_enemy_died)
		add_child(e)
		enemies.append(e)


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
	for c in seen_cells:
		if not visible_cells.has(c):
			draw_rect(Rect2(Vector2(c * TILE), Vector2(TILE, TILE)), Color(0, 0, 0, 0.6))


## Tile art for the current depth: <name>_<depth>.png, else the nearest
## shallower <name>_<n>.png, else <name>.png. So floor_1 and floor_4 make
## depths 1-3 and 4+ look different.
func _depth_art(art_name: String) -> Texture2D:
	for d in range(depth, 0, -1):
		var tex := _load_art("%s_%d" % [art_name, d])
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
	if event.keycode == KEY_ESCAPE and state != State.LEVEL_UP:
		get_tree().change_scene_to_file("res://scenes/title.tscn")
		return
	if state == State.DEAD:
		if event.keycode == KEY_R:
			get_tree().reload_current_scene()
		return
	if state != State.PLAYER_TURN:
		return

	var acted := false
	match event.keycode:
		KEY_UP, KEY_W:
			acted = _player_step(Vector2i.UP)
		KEY_DOWN, KEY_S:
			acted = _player_step(Vector2i.DOWN)
		KEY_LEFT, KEY_A:
			acted = _player_step(Vector2i.LEFT)
		KEY_RIGHT, KEY_D:
			acted = _player_step(Vector2i.RIGHT)
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
	if target == stairs:
		depth += 1
		_log("You descend to depth %d." % depth)
		_new_floor()
	else:
		_shoot()
	return true


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
		_hit(player, e, ceili(player.attack * w.get("shot_mult", 1.0)), "shot")


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
	var d := _dist(e.grid_pos, player.grid_pos)
	if d == 1:
		_attack(e, player)
	elif d <= e.attack_range and _clear_line(e.grid_pos, player.grid_pos):
		_zap(e.grid_pos, player.grid_pos, Color(1, 0.9, 0.5))
		_attack(e, player, true)
	elif d <= Enemy.AGGRO_RANGE:
		var path := astar.get_id_path(e.grid_pos, player.grid_pos)
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
	Cards.apply(player, card)
	player.pending_levels -= 1
	_log("Picked %s." % card.name)
	_check_level_up()
	_refresh_hud()


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
func _player_attack(target, dir: Vector2i) -> void:
	var w: Dictionary = player.weapon
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
			var base := ceili(player.attack * w.get("hit_mult", 1.0))
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
	e.queue_free()
	if enemies.is_empty():
		var cells := floor_cells.keys().filter(func(c): return _dist(c, player.grid_pos) >= 5)
		stairs = cells.pick_random() if not cells.is_empty() else player.grid_pos
		_log("The floor is clear. Stairs (>) appeared!")
		queue_redraw()


func _on_player_died(_p) -> void:
	if player.revives > 0:
		player.revives -= 1
		player.poison_turns = 0
		player.heal(ceili(player.max_hp / 2.0))
		_log("Phoenix Heart! You rise again.")
		return
	state = State.DEAD
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
	_level_ui = LevelUpUI.new()
	_level_ui.card_chosen.connect(_on_card_chosen)
	add_child(_level_ui)


func _refresh_hud() -> void:
	_update_reticle()
	var skill_txt := []
	for i in player.skills.size():
		var s: Dictionary = player.skills[i]
		skill_txt.append("[%d] %s %s" % [i + 1, s.name, "ready" if s.ready_in == 0 else "(%d)" % s.ready_in])
	var passive_txt := []
	for id in player.card_stacks:
		for c in Cards.POOL:
			if c.id == id and c.type == "passive":
				passive_txt.append("%s x%d" % [c.name, player.card_stacks[id]])
	_hud.text = "Depth %d   Turn %d   HP %d/%d   ATK %d   Lv %d   XP %d/%d   Enemies %d%s\nWeapon: %s   Skills: %s\nPassives: %s\n%s" % [
		depth, turn, player.hp, player.max_hp, player.attack, player.level, player.xp, player.xp_to_next, enemies.size(),
		("   POISONED (%d)" % player.poison_turns if player.poison_turns > 0 else "") + ("   STONE SKIN" if player.shield_turns > 0 else ""),
		player.weapon.get("name", "fists"),
		"  ".join(skill_txt) if skill_txt else "none",
		", ".join(passive_txt) if passive_txt else "none",
		"\n".join(log_lines),
	]

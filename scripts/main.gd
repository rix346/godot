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
const DIRS := [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]
const FIREBALL_RANGE := 6
const CHAIN_JUMP_RANGE := 3

enum State { PLAYER_TURN, LEVEL_UP, DEAD }

var state := State.PLAYER_TURN
var depth := 1
var turn := 1
var floor_cells := {}  # Vector2i -> true
var stairs := Vector2i(-1, -1)
var astar := AStarGrid2D.new()
var player: Player
var enemies: Array = []
var log_lines: Array[String] = []

var _hud: Label
var _level_ui: LevelUpUI


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
	_carve_map()
	player.place(Vector2i(W / 2, H / 2))
	_spawn_enemies(3 + depth * 2)
	queue_redraw()


## Drunkard's walk from the centre, so every floor tile is reachable.
func _carve_map() -> void:
	floor_cells.clear()
	var pos := Vector2i(W / 2, H / 2)
	var target := int(W * H * 0.42)
	while floor_cells.size() < target:
		floor_cells[pos] = true
		pos = (pos + DIRS.pick_random()).clamp(Vector2i(1, 1), Vector2i(W - 2, H - 2))

	astar.region = Rect2i(0, 0, W, H)
	astar.cell_size = Vector2(1, 1)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()
	for x in W:
		for y in H:
			astar.set_point_solid(Vector2i(x, y), not floor_cells.has(Vector2i(x, y)))


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
	for x in W:
		for y in H:
			var c := Vector2i(x, y)
			var col := Color(0.16, 0.16, 0.2) if floor_cells.has(c) else Color(0.05, 0.05, 0.07)
			draw_rect(Rect2(Vector2(c * TILE), Vector2(TILE - 1, TILE - 1)), col)
	if stairs.x >= 0:
		draw_rect(Rect2(Vector2(stairs * TILE) + Vector2(4, 4), Vector2(TILE - 8, TILE - 8)), Color(0.95, 0.8, 0.2))
		draw_string(ThemeDB.fallback_font, Vector2(stairs * TILE) + Vector2(4, 22), ">", HORIZONTAL_ALIGNMENT_CENTER, TILE - 8, 16, Color.BLACK)


# --- Input & turn loop -------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
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
		_attack(player, enemy)
		return true
	if not floor_cells.has(target):
		return false
	player.move_to(target)
	if target == stairs:
		depth += 1
		_log("You descend to depth %d." % depth)
		_new_floor()
	return true


func _end_player_turn() -> void:
	player.end_turn()
	_run_enemies()
	if state == State.DEAD:
		_refresh_hud()
		return
	if player.shield_turns > 0:
		player.shield_turns -= 1
		player.queue_redraw()
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
	if defender == player and player.thorns > 0 and not ranged and attacker.is_alive():
		_log("Thorns hit %s for %d." % [attacker.display_name, player.thorns])
		attacker.take_damage(player.thorns)


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
	state = State.DEAD
	_log("You died on depth %d at level %d. Press R to restart." % [depth, player.level])


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
	if log_lines.size() > 4:
		log_lines.pop_front()


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(8, H * TILE + 6)
	_hud.size = Vector2(W * TILE - 16, 720 - H * TILE - 12)
	_hud.add_theme_font_size_override("font_size", 14)
	layer.add_child(_hud)
	_level_ui = LevelUpUI.new()
	_level_ui.card_chosen.connect(_on_card_chosen)
	add_child(_level_ui)


func _refresh_hud() -> void:
	var skill_txt := []
	for i in player.skills.size():
		var s: Dictionary = player.skills[i]
		skill_txt.append("[%d] %s %s" % [i + 1, s.name, "ready" if s.ready_in == 0 else "(%d)" % s.ready_in])
	var passive_txt := []
	for id in player.card_stacks:
		for c in Cards.POOL:
			if c.id == id and c.type == "passive":
				passive_txt.append("%s x%d" % [c.name, player.card_stacks[id]])
	_hud.text = "Depth %d   Turn %d   HP %d/%d   ATK %d   Lv %d   XP %d/%d   Enemies %d%s\nSkills: %s\nPassives: %s\n%s" % [
		depth, turn, player.hp, player.max_hp, player.attack, player.level, player.xp, player.xp_to_next, enemies.size(),
		"   STONE SKIN" if player.shield_turns > 0 else "",
		"  ".join(skill_txt) if skill_txt else "none",
		", ".join(passive_txt) if passive_txt else "none",
		"\n".join(log_lines),
	]

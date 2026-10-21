extends Node2D
## Base for anything that occupies a grid cell and takes turns.

signal died(unit)

const TILE := 32

var grid_pos := Vector2i.ZERO
var max_hp := 10
var hp := 10
var attack := 2
var color := Color.WHITE
var glyph := "?"
var display_name := "Unit"


func place(cell: Vector2i) -> void:
	grid_pos = cell
	position = Vector2(cell * TILE)


func move_to(cell: Vector2i) -> void:
	grid_pos = cell
	var tw := create_tween()
	tw.tween_property(self, "position", Vector2(cell * TILE), 0.08)


func take_damage(amount: int) -> void:
	hp = max(hp - amount, 0)
	_flash()
	popup(str(amount), Color(1, 0.45, 0.35))
	queue_redraw()
	if hp == 0:
		died.emit(self)


func heal(amount: int) -> void:
	var before := hp
	hp = min(hp + amount, max_hp)
	if hp > before:
		popup("+%d" % (hp - before), Color(0.45, 1, 0.45))
	queue_redraw()


## Quick lunge toward `dir` and back, used for melee attacks.
func bump(dir: Vector2i) -> void:
	var base := Vector2(grid_pos * TILE)
	var tw := create_tween()
	tw.tween_property(self, "position", base + Vector2(dir) * 8, 0.05)
	tw.tween_property(self, "position", base, 0.07)


## Floating text above the unit. Parented to our parent so it outlives us.
func popup(text: String, col: Color) -> void:
	var parent := get_parent()
	if parent == null:
		return
	var l := Label.new()
	l.text = text
	l.z_index = 10
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	l.position = position + Vector2(TILE / 2 - 6 + randf_range(-5, 5), -6)
	parent.add_child(l)
	var tw := l.create_tween()
	tw.tween_property(l, "position:y", l.position.y - 22, 0.7)
	tw.parallel().tween_property(l, "modulate:a", 0.0, 0.5).set_delay(0.3)
	tw.tween_callback(l.queue_free)


func is_alive() -> bool:
	return hp > 0


func _flash() -> void:
	modulate = Color(3, 3, 3)
	var tw := create_tween()
	tw.tween_property(self, "modulate", Color.WHITE, 0.15)


func _draw() -> void:
	draw_rect(Rect2(Vector2(3, 3), Vector2(TILE - 6, TILE - 6)), color)
	draw_string(ThemeDB.fallback_font, Vector2(3, 22), glyph, HORIZONTAL_ALIGNMENT_CENTER, TILE - 6, 16, Color.BLACK)
	# HP bar along the bottom edge.
	var frac := float(hp) / max_hp
	draw_rect(Rect2(Vector2(3, TILE - 5), Vector2(TILE - 6, 3)), Color(0.25, 0, 0))
	draw_rect(Rect2(Vector2(3, TILE - 5), Vector2((TILE - 6) * frac, 3)), Color(0.2, 0.9, 0.2))

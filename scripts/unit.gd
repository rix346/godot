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
	queue_redraw()
	if hp == 0:
		died.emit(self)


func heal(amount: int) -> void:
	hp = min(hp + amount, max_hp)
	queue_redraw()


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

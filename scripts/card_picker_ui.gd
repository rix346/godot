extends "res://scripts/level_up_ui.gd"
## Every card in the game in one scrolling grid. Click a card (or arrows and
## Enter) to take it; the grid stays open so you can take more. Esc or Close
## shuts it. Cards you can't take right now are dimmed, with the reason.

signal taken(card: Dictionary)
signal closed

const SCALE := 0.8  # cards drawn at 80% of the level-up size
const COLUMNS := 5
const GAP := 12

var _player
var _scroll: ScrollContainer
var _grid: GridContainer
var _close_button: Button


func _ready() -> void:
	super()
	(get_child(0) as ColorRect).color.a = 0.9  # darker than level-up: the grid covers the whole screen
	var box := _row.get_parent()
	_row.hide()  # the level-up row of 3 isn't used here
	_scroll = ScrollContainer.new()
	_scroll.custom_minimum_size = Vector2(COLUMNS * (CARD_SIZE.x * SCALE + GAP) + 20, 560)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.follow_focus = true
	box.add_child(_scroll)
	_grid = GridContainer.new()
	_grid.columns = COLUMNS
	_grid.add_theme_constant_override("h_separation", GAP)
	_grid.add_theme_constant_override("v_separation", GAP)
	_scroll.add_child(_grid)
	_close_button = Button.new()
	_close_button.text = "Close  [Esc]"
	_close_button.flat = true
	_close_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_close_button.add_theme_font_size_override("font_size", 20)
	_close_button.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	_close_button.add_theme_color_override("font_hover_color", Color(1.0, 0.84, 0.3))
	_close_button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_close_button.pressed.connect(_close)
	box.add_child(_close_button)


func open(player) -> void:
	_player = player
	_title.text = "Pick any card"
	_scroll.scroll_vertical = 0
	_rebuild()
	show()
	_focus_card.call_deferred(0)


func _rebuild() -> void:
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()
	_cards = Cards.POOL
	for i in _cards.size():
		var card: Dictionary = _cards[i]
		var ok := Cards.can_offer(_player, card)
		var cell := VBoxContainer.new()
		cell.add_theme_constant_override("separation", 2)
		var b := _make_card(i, card, _player, SCALE, false)
		cell.add_child(b)
		var note := _label("" if ok else _why_not(card), 12, Color(0.7, 0.7, 0.7))
		note.custom_minimum_size.y = 18
		cell.add_child(note)
		if not ok:
			b.modulate.a = 0.35
			b.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.focus_mode = Control.FOCUS_NONE
		_grid.add_child(cell)


## Why a card can't be taken right now.
func _why_not(card: Dictionary) -> String:
	if card.type == "weapon":
		return "Equipped"
	if card.type == "skill" and not _player.card_stacks.has(card.id):
		return "Skill bar full"
	return "Maxed out"


## Keyboard focus on card i, or the nearest card after it that can be taken.
func _focus_card(i: int) -> void:
	var cells := _grid.get_children()
	for n in cells.size():
		var b := cells[(i + n) % cells.size()].get_child(0) as Button
		if is_instance_valid(b) and b.is_inside_tree() and b.focus_mode != Control.FOCUS_NONE:
			b.grab_focus()
			return
	_close_button.grab_focus()


func _pick(i: int) -> void:
	if not visible or i >= _cards.size() or not Cards.can_offer(_player, _cards[i]):
		return
	var keep := _scroll.scroll_vertical
	taken.emit(_cards[i])
	_rebuild()
	_restore.call_deferred(i, keep)


func _restore(i: int, scroll: int) -> void:
	_scroll.scroll_vertical = scroll
	_focus_card(i)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_close()


func _close() -> void:
	if not visible:
		return
	hide()
	closed.emit()

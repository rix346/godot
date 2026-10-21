extends CanvasLayer
## Level-up overlay: shows up to 3 cards, picked by click or keys 1-3.

signal card_chosen(card: Dictionary)

const Cards := preload("res://scripts/cards.gd")

var _cards: Array = []
var _row: HBoxContainer
var _title: Label


func _ready() -> void:
	layer = 10
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	center.add_child(box)

	_title = Label.new()
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 28)
	box.add_child(_title)

	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 16)
	box.add_child(_row)
	hide()


func show_choices(player, cards: Array) -> void:
	_cards = cards
	_title.text = "Level %d! Pick a card" % (player.level - player.pending_levels + 1)
	for child in _row.get_children():
		child.queue_free()
	for i in cards.size():
		var card: Dictionary = cards[i]
		var b := Button.new()
		b.custom_minimum_size = Vector2(250, 180)
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.text = "[%d]  %s\n%s %s\n\n%s" % [i + 1, card.name, card.rarity.to_upper(), card.type.to_upper(), Cards.describe(player, card)]
		_style(b, Cards.RARITY_COLORS[card.rarity])
		b.pressed.connect(_pick.bind(i))
		_row.add_child(b)
	show()
	if _row.get_child_count() > 0:
		(_row.get_child(_row.get_child_count() - cards.size()) as Button).grab_focus.call_deferred()


func _style(b: Button, col: Color) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.11, 0.11, 0.14)
	normal.border_color = col
	normal.set_border_width_all(3)
	normal.set_corner_radius_all(8)
	var hover := normal.duplicate()
	hover.bg_color = Color(0.18, 0.18, 0.24)
	var focus := hover.duplicate()
	focus.set_border_width_all(5)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", hover)
	b.add_theme_stylebox_override("focus", focus)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(state, col.lightened(0.3))


func _unhandled_input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey and event.pressed):
		return
	var i: int = event.keycode - KEY_1
	if i >= 0 and i < _cards.size():
		get_viewport().set_input_as_handled()
		_pick(i)


func _pick(i: int) -> void:
	if not visible:
		return
	hide()
	card_chosen.emit(_cards[i])

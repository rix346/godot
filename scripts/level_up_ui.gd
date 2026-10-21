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
		b.text = "[%d]  %s\n%s\n\n%s" % [i + 1, card.name, card.type.to_upper(), Cards.describe(player, card)]
		b.add_theme_color_override("font_color", Color(1, 0.85, 0.4) if card.type == "skill" else Color(0.75, 0.9, 1))
		b.pressed.connect(_pick.bind(i))
		_row.add_child(b)
	show()
	if _row.get_child_count() > 0:
		(_row.get_child(_row.get_child_count() - cards.size()) as Button).grab_focus.call_deferred()


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

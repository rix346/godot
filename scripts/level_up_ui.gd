extends CanvasLayer
## Level-up overlay: shows up to 3 cards, picked by click or keys 1-3.

signal card_chosen(card: Dictionary)

const Cards := preload("res://scripts/cards.gd")
const CARD_SIZE := Vector2(192, 300)  # card art is 64x100, drawn at 3x

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
	_row.add_theme_constant_override("separation", 28)
	box.add_child(_row)
	hide()


func show_choices(player, cards: Array) -> void:
	_cards = cards
	_title.text = "Level %d! Pick a card" % (player.level - player.pending_levels + 1)
	for child in _row.get_children():
		child.queue_free()
	for i in cards.size():
		_row.add_child(_make_card(i, cards[i], player))
	show()
	if _row.get_child_count() > 0:
		(_row.get_child(_row.get_child_count() - cards.size()) as Button).grab_focus.call_deferred()


## One card: the art/card_<rarity>.png frame scaled up, name on top, then
## rarity/type, description, and the key to press at the bottom.
func _make_card(i: int, card: Dictionary, player) -> Button:
	var b := Button.new()
	b.custom_minimum_size = CARD_SIZE
	b.pivot_offset = CARD_SIZE / 2
	var frame_path := "res://art/card_%s.png" % card.rarity
	if ResourceLoader.exists(frame_path):
		var frame := StyleBoxTexture.new()
		frame.texture = load(frame_path)
		for state in ["normal", "hover", "pressed", "focus"]:
			b.add_theme_stylebox_override(state, frame if state != "focus" else StyleBoxEmpty.new())
	else:
		_style(b, Cards.RARITY_COLORS[card.rarity])
	b.pressed.connect(_pick.bind(i))
	# Grow the card while it is hovered or selected with the keyboard.
	for sig in [b.mouse_entered, b.focus_entered]:
		sig.connect(func(): b.scale = Vector2(1.06, 1.06))
	for sig in [b.mouse_exited, b.focus_exited]:
		sig.connect(func(): b.scale = Vector2.ONE)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	b.add_child(margin)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 4)
	margin.add_child(box)

	var ink := Color(0.12, 0.12, 0.18)
	box.add_child(_label(card.name, 22, ink))
	box.add_child(_label("%s %s" % [card.rarity.to_upper(), card.type.to_upper()], 11, ink.lightened(0.35)))
	var icon_path := "res://art/%s_%s.png" % [card.type, card.id]
	if ResourceLoader.exists(icon_path):
		var icon := TextureRect.new()
		icon.texture = load(icon_path)
		icon.custom_minimum_size = Vector2(64, 64)  # 32x32 art at 2x
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(icon)
	var desc := _label(Cards.describe(player, card), 14, ink)
	desc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	desc.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(desc)
	box.add_child(_label("[%d]" % (i + 1), 13, ink.lightened(0.35)))
	return b


func _label(text: String, font_size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", col)
	return l


## Fallback look when there is no card_<rarity>.png for this rarity.
func _style(b: Button, col: Color) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = col.lightened(0.6)
	normal.border_color = col
	normal.set_border_width_all(4)
	normal.set_corner_radius_all(8)
	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", normal)
	b.add_theme_stylebox_override("pressed", normal)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())


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

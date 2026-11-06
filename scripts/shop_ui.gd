extends "res://scripts/level_up_ui.gd"
## Shop overlay: the shopkeeper's cards, bought with coins by click or keys
## 1-3. Esc or Leave closes it. main.gd takes the coins and applies the card.
## Reuses the card look from level_up_ui.gd.

signal bought(card: Dictionary, price: int)
signal closed

const PRICES := {common = 3, rare = 5, epic = 8, legendary = 12}
const GOLD := Color(1.0, 0.84, 0.3)
const RED := Color(1.0, 0.45, 0.4)

var _player
var _stock: Array = []  # this floor's shop: [{card, sold}], kept by main.gd
var _buttons: Array[Button] = []
var _wallet: HBoxContainer
var _leave: Button
var _coin_tex: Texture2D


static func price_of(card: Dictionary) -> int:
	return PRICES[card.rarity]


func _ready() -> void:
	super()
	if ResourceLoader.exists("res://art/coin.png"):
		_coin_tex = load("res://art/coin.png")
	var box := _row.get_parent()
	_wallet = HBoxContainer.new()
	_wallet.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_child(_wallet)
	box.move_child(_wallet, 1)  # right under the title
	_leave = Button.new()
	_leave.text = "Leave  [Esc]"
	_leave.flat = true
	_leave.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_leave.add_theme_font_size_override("font_size", 22)
	_leave.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	for state in ["font_hover_color", "font_focus_color", "font_pressed_color", "font_hover_pressed_color"]:
		_leave.add_theme_color_override(state, GOLD)
	_leave.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	_leave.pressed.connect(_close)
	box.add_child(_leave)


func open(player, stock: Array) -> void:
	_player = player
	_stock = stock
	_cards = stock.map(func(item): return item.card)
	_title.text = "Shop"
	_rebuild()
	show()


func _rebuild() -> void:
	for child in _wallet.get_children() + _row.get_children():
		child.get_parent().remove_child(child)
		child.queue_free()
	_fill_coin_row(_wallet, "You have %d" % _player.coins, 20, GOLD)
	_buttons.clear()
	for i in _stock.size():
		var item: Dictionary = _stock[i]
		var card: Dictionary = item.card
		var column := VBoxContainer.new()
		column.add_theme_constant_override("separation", 8)
		var b := _make_card(i, card, _player)
		column.add_child(b)
		_buttons.append(b)
		var price := HBoxContainer.new()
		price.alignment = BoxContainer.ALIGNMENT_CENTER
		price.custom_minimum_size.y = 32
		if item.sold:
			price.add_child(_plain_label("SOLD", 20, Color(0.6, 0.6, 0.6)))
		elif not Cards.can_offer(_player, card):
			price.add_child(_plain_label(_why_not(card), 18, Color(0.6, 0.6, 0.6)))
		else:
			_fill_coin_row(price, str(price_of(card)), 22, GOLD if _player.coins >= price_of(card) else RED)
		column.add_child(price)
		_row.add_child(column)
		if item.sold or not Cards.can_offer(_player, card):
			b.modulate.a = 0.35
			b.mouse_filter = Control.MOUSE_FILTER_IGNORE
			b.focus_mode = Control.FOCUS_NONE
	_focus_first.call_deferred()


## Why a card in stock can't be bought any more (e.g. a level-up since).
func _why_not(card: Dictionary) -> String:
	if card.type == "weapon":
		return "Equipped"
	if card.type == "skill" and not _player.card_stacks.has(card.id):
		return "Skill bar full"
	return "Maxed out"


## Keyboard focus on the first card still for sale, else on Leave.
func _focus_first() -> void:
	for b in _buttons:
		if is_instance_valid(b) and b.is_inside_tree() and b.focus_mode != Control.FOCUS_NONE:
			b.grab_focus()
			return
	_leave.grab_focus()


## Coin icon followed by text, added to `row`.
func _fill_coin_row(row: HBoxContainer, text: String, font_size: int, col: Color) -> void:
	if _coin_tex:
		var icon := TextureRect.new()
		icon.texture = _coin_tex
		icon.custom_minimum_size = Vector2(32, 32)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(icon)
	else:
		text += " coins"
	row.add_child(_plain_label(text, font_size, col))


func _plain_label(text: String, font_size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 4)
	return l


func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_close()
		return
	super(event)


## Buys card i if it's still for sale and you have the coins.
func _pick(i: int) -> void:
	if not visible or i >= _stock.size():
		return
	var item: Dictionary = _stock[i]
	if item.sold or not Cards.can_offer(_player, item.card):
		return
	var price := price_of(item.card)
	if _player.coins < price:
		_wallet.modulate = RED
		_wallet.create_tween().tween_property(_wallet, "modulate", Color.WHITE, 0.4)
		return
	item.sold = true
	bought.emit(item.card, price)
	_rebuild()


func _close() -> void:
	if not visible:
		return
	hide()
	closed.emit()

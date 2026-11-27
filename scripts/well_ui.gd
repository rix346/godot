extends "res://scripts/level_up_ui.gd"
## The wishing well: the wishes from wishes.gd as cards. Make one with a click
## or keys 1-3, and the well dries up (main.gd counts the wish). Esc or Walk
## away leaves it for later. Reuses the card look from level_up_ui.gd.

signal wished(wish: Dictionary)
signal closed

const Wishes := preload("res://scripts/wishes.gd")

var _note: Label
var _leave: Button


func _ready() -> void:
	super()
	var box := _row.get_parent()
	_note = _label("", 16, Color(0.85, 0.85, 0.85))
	_note.custom_minimum_size.x = 640  # wraps instead of stretching the screen
	box.add_child(_note)
	box.move_child(_note, 1)  # right under the title
	_leave = _menu_button("Walk away  [Esc]", _close)
	_leave.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(_leave)


## `made` is wish id -> times you've made it this run.
func open(player, made: Dictionary) -> void:
	_title.text = "Wishing well"
	var total := 0
	for n in made.values():
		total += n
	_note.text = "Each wish makes this run harder, and kills give %d%% more XP." % roundi(Wishes.REWARD * 100)
	if total > 0:
		_note.text += "\nSo far you've made %d, for +%d%% XP." % [total, roundi(total * Wishes.REWARD * 100)]
	_cards = Wishes.POOL
	for child in _row.get_children():
		_row.remove_child(child)
		child.queue_free()
	for i in Wishes.POOL.size():
		var shown: Dictionary = Wishes.POOL[i].duplicate()
		shown.desc = Wishes.describe(shown, made.get(shown.id, 0))
		_row.add_child(_make_card(i, shown, player))
	show()
	_focus_first.call_deferred()


## Keyboard focus on the first wish, once the cards are on screen.
func _focus_first() -> void:
	if visible and _row.get_child_count() > 0:
		(_row.get_child(0) as Button).grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_close()
		return
	super(event)


func _pick(i: int) -> void:
	if not visible:
		return
	hide()
	wished.emit(_cards[i])


func _close() -> void:
	if not visible:
		return
	hide()
	closed.emit()

extends Control
## Title screen: game name plus Play / Credits / Exit inside art/menu_panel.png.
## Built in code like the rest of the UI. Edit CREDITS to change the credits.

const GAME_SCENE := "res://scenes/main.tscn"
const TITLE := "Dungeons: To The Bottom"
const CREDITS := "Game & art\nRihards\n\nProgramming help\nClaude"
const INK := Color(0.27, 0.16, 0.12)
const INK_HOVER := Color(0.62, 0.22, 0.12)
const PANEL_SCALE := 5

var _buttons: VBoxContainer
var _credits: VBoxContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_background()

	var title := Label.new()
	title.text = TITLE
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0, 110)
	title.size = Vector2(960, 80)
	title.add_theme_font_size_override("font_size", 56)
	title.add_theme_color_override("font_color", Color(1.0, 0.82, 0.3))
	title.add_theme_color_override("font_outline_color", Color(0.15, 0.08, 0.05))
	title.add_theme_constant_override("outline_size", 12)
	add_child(title)

	# The scroll: drawn small as a 9-patch, then scaled up so pixels stay crisp.
	var panel_size := Vector2(72, 64)
	var panel_pos := Vector2((960 - panel_size.x * PANEL_SCALE) / 2, 260)
	if ResourceLoader.exists("res://art/menu_panel.png"):
		var bg := NinePatchRect.new()
		bg.texture = load("res://art/menu_panel.png")
		bg.patch_margin_left = 5
		bg.patch_margin_right = 7
		bg.patch_margin_top = 7
		bg.patch_margin_bottom = 7
		bg.position = panel_pos
		bg.size = panel_size
		bg.scale = Vector2(PANEL_SCALE, PANEL_SCALE)
		add_child(bg)
	else:
		var bg := ColorRect.new()
		bg.color = Color(0.93, 0.85, 0.68)
		bg.position = panel_pos
		bg.size = panel_size * PANEL_SCALE
		add_child(bg)

	# Content area inside the scroll's rolled top and bottom edges.
	var inner := Rect2(panel_pos + Vector2(30, 45), panel_size * PANEL_SCALE - Vector2(65, 90))
	_buttons = _column(inner)
	for b in [["Play", _on_play], ["Credits", _on_credits], ["Exit", _on_exit]]:
		_buttons.add_child(_button(b[0], b[1]))

	_credits = _column(inner)
	var text := Label.new()
	text.text = CREDITS
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.add_theme_font_size_override("font_size", 17)
	text.add_theme_color_override("font_color", INK)
	_credits.add_child(text)
	_credits.add_child(_button("Back", _on_back))
	_credits.hide()

	_buttons.get_child(0).grab_focus.call_deferred()


func _build_background() -> void:
	var dark := ColorRect.new()
	dark.color = Color(0.05, 0.04, 0.06)
	dark.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dark)
	if ResourceLoader.exists("res://art/wall.png"):
		var tiles := TextureRect.new()
		tiles.texture = load("res://art/wall.png")
		tiles.stretch_mode = TextureRect.STRETCH_TILE
		tiles.size = Vector2(960, 720)
		tiles.modulate = Color(0.35, 0.35, 0.4)
		add_child(tiles)


func _column(rect: Rect2) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.position = rect.position
	box.size = rect.size
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	return box


func _button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.add_theme_font_size_override("font_size", 30)
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", INK_HOVER)
	b.add_theme_color_override("font_focus_color", INK_HOVER)
	b.add_theme_color_override("font_pressed_color", INK_HOVER)
	b.add_theme_color_override("font_hover_pressed_color", INK_HOVER)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(on_press)
	return b


func _on_play() -> void:
	get_tree().change_scene_to_file(GAME_SCENE)


func _on_credits() -> void:
	_buttons.hide()
	_credits.show()
	_credits.get_child(1).grab_focus()


func _on_back() -> void:
	_credits.hide()
	_buttons.show()
	_buttons.get_child(1).grab_focus()


func _on_exit() -> void:
	get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and _credits.visible:
		_on_back()

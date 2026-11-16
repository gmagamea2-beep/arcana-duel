extends Control
## 영웅 카드 그림 (메인 메뉴 영웅 고르기, 영웅 뽑기 화면).
## 잠긴 영웅은 어둡게 + 자물쇠, 뽑기 전 뒷면은 back = true.

signal pressed(view: Control)

const Art = preload("res://ui/art.gd")
const CardDB = preload("res://core/card_db.gd")

const RARITY_LABEL := {"basic": "기본", "rare": "레어", "epic": "에픽", "legendary": "레전더리"}

var hid := ""
var locked := false
var selected := false
var back := false
## 뒷면일 때 빛나는 색 (뽑기 연출)
var glow_color := Color(0, 0, 0, 0)
var _t := 0.0


func setup(p_hid: String, p_size: Vector2, p_locked: bool = false):
	hid = p_hid
	locked = p_locked
	custom_minimum_size = p_size
	size = p_size
	pivot_offset = p_size / 2.0
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)
	return self


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT and not ev.pressed:
		pressed.emit(self)
		accept_event()


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func rarity() -> String:
	if hid == "":
		return "basic"
	return CardDB.heroes[hid].get("rarity", "basic")


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var k := size.x / 140.0
	if back:
		_draw_back(rect, k)
		return
	var hd: Dictionary = CardDB.heroes[hid]
	var rcol := Art.rarity_color(rarity())
	if rarity() == "legendary" and not locked:
		rcol = rcol.lerp(Color.WHITE, 0.25 + 0.25 * sin(_t * 3.0))
	if selected:
		var gc := Art.COL_SEL
		gc.a = 0.6 + 0.4 * sin(_t * 5.0)
		draw_style_box(Art.panel_style(Color(0, 0, 0, 0), gc, int(5 * k), int(14 * k)), rect.grow(5 * k))
	var bg: Color = Art.faction_color(hd["faction"])
	if locked:
		bg = bg.darkened(0.55)
	draw_style_box(Art.panel_style(bg, rcol if not locked else Color("#3a3f4b"), int(maxf(2.0, 4.0 * k)), int(12 * k)), rect)
	var tex := Art.icon(hd["icon"])
	var icon_rect := Rect2(14 * k, 14 * k, size.x - 28 * k, size.y * 0.5)
	if tex != null:
		var s := minf(icon_rect.size.x, icon_rect.size.y)
		var r := Rect2(icon_rect.position + (icon_rect.size - Vector2(s, s)) / 2.0, Vector2(s, s))
		var col: Color = (Art.FACTION_ACCENT[hd["faction"]] as Color).lerp(Color.WHITE, 0.3)
		if locked:
			col = Color(0.25, 0.27, 0.32)
		draw_texture_rect(tex, r, false, col)
	var y := size.y * 0.5 + 16 * k
	Art.draw_text(self, hd["name"], Rect2(4 * k, y, size.x - 8 * k, 26 * k), int(24 * k), Art.COL_TEXT if not locked else Art.COL_SUB, HORIZONTAL_ALIGNMENT_CENTER, true, 2)
	Art.draw_text(self, hd["title"], Rect2(4 * k, y + 26 * k, size.x - 8 * k, 20 * k), int(15 * k), Art.FACTION_ACCENT[hd["faction"]] if not locked else Art.COL_SUB)
	var rl: String = RARITY_LABEL.get(rarity(), "")
	Art.draw_text(self, rl, Rect2(4 * k, size.y - 30 * k, size.x - 8 * k, 22 * k), int(15 * k), Art.rarity_color(rarity()).lightened(0.2), HORIZONTAL_ALIGNMENT_CENTER, true)
	if locked:
		var lock := Art.icon("padlock")
		if lock != null:
			var ls := 40.0 * k
			draw_texture_rect(lock, Rect2(Vector2(size.x - ls - 6 * k, 6 * k), Vector2(ls, ls)), false, Color("#facc15"))


func _draw_back(rect: Rect2, k: float) -> void:
	if glow_color.a > 0.0:
		for i in 4:
			var g := glow_color
			g.a = glow_color.a * (0.35 - i * 0.08)
			draw_style_box(Art.panel_style(Color(0, 0, 0, 0), g, int(6 * k), int(18 * k)), rect.grow((6 + i * 7) * k))
	draw_style_box(Art.panel_style(Color("#2a1f4a"), Color("#f5b301"), int(maxf(2.0, 5.0 * k)), int(14 * k)), rect)
	draw_style_box(Art.panel_style(Color("#3b2a6b"), Color("#6d5bd0"), int(maxf(1.0, 2.0 * k)), int(10 * k)), rect.grow(-10 * k))
	var tex := Art.icon("cosmic-egg")
	if tex != null:
		var s := minf(size.x, size.y) * 0.55
		var pulse := 0.8 + 0.2 * sin(_t * 4.0)
		draw_texture_rect(tex, Rect2((size - Vector2(s, s)) / 2.0, Vector2(s, s)), false, Color(1, 0.85, 0.4, pulse))
	Art.draw_text(self, "?", Rect2(0, size.y - 60 * k, size.x, 50 * k), int(40 * k), Color("#fde68a"), HORIZONTAL_ALIGNMENT_CENTER, true, 3)

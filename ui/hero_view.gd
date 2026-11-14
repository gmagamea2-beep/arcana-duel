extends Control
## 영웅 초상 + 체력/방어도. 대상으로 고를 수 있다.

signal pressed(view: Control)

const Art = preload("res://ui/art.gd")
const CardDB = preload("res://core/card_db.gd")

var player = null
var highlight := ""
var _t := 0.0
## 피해를 받았을 때 붉게 번쩍임 (1 → 0)
var _flash := 0.0


func setup(p):
	player = p
	custom_minimum_size = Vector2(340, 104)
	size = custom_minimum_size
	mouse_filter = Control.MOUSE_FILTER_STOP
	return self


func set_highlight(h: String) -> void:
	highlight = h
	set_process(h != "" or _flash > 0.0)
	queue_redraw()


func flash() -> void:
	_flash = 1.0
	set_process(true)


func _process(delta: float) -> void:
	_t += delta
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 1.6)
		if _flash == 0.0 and highlight == "" and not player.is_emperor:
			set_process(false)
	queue_redraw()


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit(self)
		accept_event()


func _draw() -> void:
	if player == null:
		return
	var w := size.x
	var h := size.y
	var rect := Rect2(Vector2.ZERO, size)
	var hd: Dictionary = CardDB.heroes.get(player.hero_id, {})
	var faction: String = hd.get("faction", "neutral")
	if highlight != "":
		var col := Art.COL_TARGET if highlight == "target" else Art.COL_OK
		col.a = 0.65 + 0.35 * sin(_t * 6.0)
		draw_style_box(Art.panel_style(Color(0, 0, 0, 0), col, 5, 18), rect.grow(6))
	var border := Art.FACTION_ACCENT.get(faction, Color.WHITE) as Color
	if player.is_emperor:
		border = Color.from_hsv(fmod(_t * 0.25, 1.0), 0.7, 1.0)
		set_process(true)
	draw_style_box(Art.panel_style(Art.faction_color(faction), border, 3, 16), rect)
	# 초상
	var pr := Rect2(8, 8, h - 16, h - 16)
	draw_style_box(Art.panel_style(Color(0, 0, 0, 0.35), Color(0, 0, 0, 0), 0, 12), pr)
	var icon_name: String = "laurel-crown" if player.is_emperor else hd.get("icon", "")
	var tex := Art.icon(icon_name)
	if tex != null:
		draw_texture_rect(tex, pr.grow(-8), false, border.lerp(Color.WHITE, 0.3))
	var x := h + 4.0
	var text_w := w - x - (138.0 if player.armor > 0 else 92.0)
	Art.draw_text(self, player.name, Rect2(x, 6, text_w, 26), 17, Art.COL_SUB, HORIZONTAL_ALIGNMENT_LEFT)
	Art.draw_text(self, player.hero_name, Rect2(x, 32, text_w, 34), 26, Art.COL_TEXT, HORIZONTAL_ALIGNMENT_LEFT, true)
	Art.draw_text(self, "%s 진영" % CardDB.FACTION_NAMES.get(faction, ""), Rect2(x, 66, text_w, 26), 15, border, HORIZONTAL_ALIGNMENT_LEFT)
	# 체력 / 방어도
	Art.draw_badge(self, Vector2(w - 44, h / 2.0 + 4), 32, Art.COL_HP, str(player.hp))
	Art.draw_text(self, "체력", Rect2(w - 76, 2, 64, 18), 13, Art.COL_SUB)
	if player.armor > 0:
		# 방어도: 체력 왼쪽에 크게 (피해를 체력보다 먼저 막음)
		var c := Vector2(w - 108, h / 2.0 + 4)
		var shield := PackedVector2Array([c + Vector2(-22, -24), c + Vector2(22, -24), c + Vector2(22, 4), c + Vector2(0, 26), c + Vector2(-22, 4)])
		draw_colored_polygon(shield, Art.COL_ARMOR)
		draw_polyline(shield + PackedVector2Array([shield[0]]), Color.WHITE, 2.0)
		Art.draw_text(self, str(player.armor), Rect2(c - Vector2(22, 22), Vector2(44, 40)), 24, Color.BLACK, HORIZONTAL_ALIGNMENT_CENTER, true)
		Art.draw_text(self, "방어도", Rect2(w - 140, 2, 64, 18), 13, Art.COL_ARMOR)
	if _flash > 0.0:
		draw_style_box(Art.panel_style(Color(1, 0.15, 0.15, 0.45 * _flash), Color(0, 0, 0, 0), 0, 16), rect)

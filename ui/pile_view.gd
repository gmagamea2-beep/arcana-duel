extends Control
## 내 덱 / 버린 더미 표시. 누르면 안에 든 카드 목록을 볼 수 있다.

signal pressed(view: Control)

const Art = preload("res://ui/art.gd")

var kind := "deck"  # deck / discard
var count := 0
## 버린 더미 맨 위 카드 데이터 (없으면 빈 딕셔너리)
var top: Dictionary = {}
var highlight := ""
var _t := 0.0


func setup(p_kind: String):
	kind = p_kind
	custom_minimum_size = Vector2(120, 196)
	mouse_filter = Control.MOUSE_FILTER_STOP
	return self


func set_state(p_count: int, p_top: Dictionary = {}) -> void:
	count = p_count
	top = p_top
	queue_redraw()


func set_highlight(h: String) -> void:
	highlight = h
	set_process(h != "")
	queue_redraw()


func card_rect() -> Rect2:
	return Rect2(Vector2(10, 30), Vector2(size.x - 20, (size.x - 20) * 1.4))


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit(self)
		accept_event()


func _draw() -> void:
	var title := "덱" if kind == "deck" else "버린 더미"
	Art.draw_text(self, title, Rect2(0, 0, size.x, 26), 18, Art.COL_SUB, HORIZONTAL_ALIGNMENT_CENTER, true)
	var r := card_rect()
	if highlight != "":
		var col := Art.COL_SEL
		col.a = 0.6 + 0.4 * sin(_t * 6.0)
		draw_style_box(Art.panel_style(Color(1, 0.85, 0.1, 0.10), col, 5, 14), r.grow(8))
	if count <= 0:
		draw_style_box(Art.panel_style(Color(1, 1, 1, 0.03), Color("#3a4050"), 2, 10), r)
	elif kind == "deck":
		# 카드 뒷면을 겹쳐 쌓은 모양
		var layers := mini(3, count)
		for i in range(layers - 1, -1, -1):
			var o := Vector2(i * 4, -i * 4)
			draw_style_box(Art.panel_style(Color("#2a1f4a"), Color("#f5b301"), 3, 10), Rect2(r.position + o, r.size))
		var tex := Art.icon("crossed-swords")
		if tex != null:
			var s := r.size.x * 0.55
			draw_texture_rect(tex, Rect2(r.position + (r.size - Vector2(s, s)) / 2.0, Vector2(s, s)), false, Color(1, 0.85, 0.4, 0.85))
	else:
		var f: String = top.get("faction", "neutral")
		draw_style_box(Art.panel_style(Art.faction_color(f), Art.rarity_color(top.get("rarity", "basic")), 3, 10), r)
		var tex2 := Art.icon(top.get("icon", ""))
		if tex2 != null:
			var s2 := r.size.x * 0.6
			draw_texture_rect(tex2, Rect2(r.position + Vector2((r.size.x - s2) / 2.0, 12), Vector2(s2, s2)), false, Color(1, 1, 1, 0.75))
		Art.draw_text(self, top.get("name", ""), Rect2(r.position.x + 4, r.end.y - 34, r.size.x - 8, 28), 15, Art.COL_TEXT, HORIZONTAL_ALIGNMENT_CENTER, true, 2)
	# 장수
	Art.draw_badge(self, Vector2(size.x - 18, r.end.y - 6), 18, Color("#111827"), str(count))

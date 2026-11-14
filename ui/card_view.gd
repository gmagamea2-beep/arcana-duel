extends Control
## 카드 한 장을 직접 그리는 컨트롤.
## mode: "hand"(세로 카드), "detail"(큰 세로 카드), "board"(필드 위 유닛), "market"(시장 가로줄),
##       "trap_back"(상대 함정 뒷면), "trap_own"(내 함정), "field"(공용 필드)

signal pressed(view: Control)

const Art = preload("res://ui/art.gd")
const CardDB = preload("res://core/card_db.gd")

var data: Dictionary = {}
var inst = null
var mode := "hand"
## "", "ok"(사용/공격 가능), "sel"(선택됨), "target"(대상 가능), "mark"(교체 표시)
var highlight := ""
var price := -1
var dim := false
var caption := ""
var meta_info: Dictionary = {}
var _t := 0.0


func setup(p_data: Dictionary, p_inst = null, p_mode: String = "hand"):
	data = p_data
	inst = p_inst
	mode = p_mode
	mouse_filter = Control.MOUSE_FILTER_STOP
	match mode:
		"hand":
			custom_minimum_size = Vector2(170, 238)
		"detail":
			custom_minimum_size = Vector2(200, 280)
		"board":
			custom_minimum_size = Vector2(140, 168)
		"field":
			custom_minimum_size = Vector2(150, 110)
		"market":
			custom_minimum_size = Vector2(300, 84)
		"trap_back", "trap_own":
			custom_minimum_size = Vector2(64, 84)
	size = custom_minimum_size
	set_process(data.get("rarity", "") == "ultimate" or highlight != "")
	return self


func set_highlight(h: String) -> void:
	highlight = h
	set_process(h != "" or data.get("rarity", "") == "ultimate")
	queue_redraw()


func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit(self)
		accept_event()


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	match mode:
		"hand", "detail":
			_draw_portrait()
		"board":
			_draw_board()
		"field":
			_draw_field()
		"market":
			_draw_market()
		"trap_back":
			_draw_trap(false)
		"trap_own":
			_draw_trap(true)


# ── 공통 ──

func _rarity() -> String:
	return data.get("rarity", "common")


func _border_color() -> Color:
	if _rarity() == "ultimate":
		return Color.from_hsv(fmod(_t * 0.25, 1.0), 0.75, 1.0)
	return Art.rarity_color(_rarity())


func _draw_glow(rect: Rect2, radius: int) -> void:
	if highlight == "":
		return
	var col := Art.COL_OK
	match highlight:
		"sel":
			col = Art.COL_SEL
		"target":
			col = Art.COL_TARGET
		"mark":
			col = Art.COL_TARGET
	var pulse := 0.65 + 0.35 * sin(_t * 6.0)
	col.a = pulse
	var sb := Art.panel_style(Color(0, 0, 0, 0), col, 5, radius + 4)
	draw_style_box(sb, rect.grow(6))


func _frame(rect: Rect2, border_w: int, radius: int, border_col: Color = Color(0, 0, 0, 0)) -> void:
	var bc := border_col if border_col.a > 0 else _border_color()
	var sb := Art.panel_style(Art.faction_color(data.get("faction", "neutral")), bc, border_w, radius)
	draw_style_box(sb, rect)


func _draw_icon(rect: Rect2, alpha: float = 1.0) -> void:
	var tex := Art.icon(data.get("icon", ""))
	if tex == null:
		return
	var s := minf(rect.size.x, rect.size.y)
	var r := Rect2(rect.position + (rect.size - Vector2(s, s)) / 2.0, Vector2(s, s))
	var col: Color = Art.FACTION_ACCENT.get(data.get("faction", "neutral"), Color.WHITE)
	col = col.lerp(Color.WHITE, 0.35)
	col.a = alpha
	draw_texture_rect(tex, r, false, col)


func _cur_attack() -> int:
	return inst.attack if inst != null else int(data.get("attack", 0))


func _cur_health() -> int:
	return inst.health if inst != null else int(data.get("health", 0))


func _health_color() -> Color:
	if inst == null:
		return Color.WHITE
	if inst.health < inst.max_health:
		return Color("#fecaca")
	if inst.max_health > int(data.get("health", 0)):
		return Color("#bbf7d0")
	return Color.WHITE


func _attack_color() -> Color:
	if inst != null and inst.attack > int(data.get("attack", 0)):
		return Color("#14532d")
	return Color.BLACK


## 키워드 + 효과 문구
func rules_text() -> String:
	var parts: Array = []
	var kws: Array = inst.keywords if inst != null else data.get("keywords", [])
	var kw_names: Array = []
	for k in kws:
		kw_names.append(CardDB.KEYWORD_NAMES.get(k, k))
	if not kw_names.is_empty():
		parts.append(", ".join(PackedStringArray(kw_names)))
	var tx: String = data.get("text", "")
	if tx != "" and tx != "토큰":
		parts.append(tx)
	return "\n".join(PackedStringArray(parts))


func type_line() -> String:
	var t: String = CardDB.TYPE_NAMES.get(data.get("type", ""), "")
	var r: String = CardDB.RARITY_NAMES.get(_rarity(), "")
	var f: String = CardDB.FACTION_NAMES.get(data.get("faction", ""), "")
	return "%s · %s · %s" % [t, f, r]


# ── 세로 카드 (손패 / 상세) ──

func _draw_portrait() -> void:
	var w := size.x
	var h := size.y
	var k := w / 200.0
	var rect := Rect2(Vector2.ZERO, size)
	_draw_glow(rect, int(12 * k))
	_frame(rect, int(maxf(3.0, 5.0 * k)), int(12 * k))
	# 그림 영역
	var art_rect := Rect2(14 * k, 46 * k, w - 28 * k, 104 * k)
	draw_style_box(Art.panel_style(Color(0, 0, 0, 0.35), Color(0, 0, 0, 0), 0, int(8 * k)), art_rect)
	_draw_icon(art_rect.grow(-6 * k))
	# 이름
	Art.draw_text(self, data.get("name", ""), Rect2(46 * k, 6 * k, w - 52 * k, 36 * k), int(20 * k), Art.COL_TEXT, HORIZONTAL_ALIGNMENT_CENTER, true)
	# 비용
	Art.draw_badge(self, Vector2(24 * k, 24 * k), 19 * k, Art.COL_MANA, str(int(data.get("cost", 0))))
	# 종류 줄
	Art.draw_text(self, type_line(), Rect2(6 * k, 152 * k, w - 12 * k, 22 * k), int(14 * k), _border_color().lightened(0.2))
	# 효과 문구
	var bottom_pad := 44.0 * k if data.get("type", "") == "unit" else 12.0 * k
	Art.draw_multiline(self, rules_text(), Rect2(10 * k, 176 * k, w - 20 * k, h - 176 * k - bottom_pad), int(16 * k), Art.COL_TEXT)
	# 공격력 / 체력
	if data.get("type", "") == "unit":
		Art.draw_badge(self, Vector2(26 * k, h - 26 * k), 20 * k, Art.COL_ATK, str(_cur_attack()), _attack_color())
		Art.draw_badge(self, Vector2(w - 26 * k, h - 26 * k), 20 * k, Art.COL_HP, str(_cur_health()), _health_color())
	# 시장 가격
	if price >= 0:
		Art.draw_badge(self, Vector2(w - 22 * k, 22 * k), 18 * k, Art.COL_GOLD, str(price), Color.BLACK)
	if caption != "":
		Art.draw_text(self, caption, Rect2(0, h - 30 * k, w, 26 * k), int(16 * k), Art.COL_SEL, HORIZONTAL_ALIGNMENT_CENTER, true)
	if highlight == "mark":
		draw_rect(rect, Color(0, 0, 0, 0.45))
		Art.draw_text(self, "교체", rect, int(40 * k), Art.COL_TARGET, HORIZONTAL_ALIGNMENT_CENTER, true)
	elif dim:
		draw_style_box(Art.panel_style(Color(0, 0, 0, 0.42), Color(0, 0, 0, 0), 0, int(12 * k)), rect)


# ── 필드 위 유닛 ──

func _draw_board() -> void:
	var w := size.x
	var h := size.y
	var k := w / 140.0
	var rect := Rect2(Vector2.ZERO, size)
	_draw_glow(rect, int(14 * k))
	var taunt: bool = inst != null and inst.has_kw("taunt")
	if taunt:
		_frame(rect, int(7 * k), int(14 * k), Color("#cbd5e1"))
	else:
		_frame(rect, int(3 * k), int(14 * k))
	_draw_icon(Rect2(22 * k, 26 * k, w - 44 * k, 82 * k), 0.95)
	Art.draw_text(self, data.get("name", ""), Rect2(8 * k, 4 * k, w - 16 * k, 24 * k), int(15 * k), Art.COL_TEXT, HORIZONTAL_ALIGNMENT_CENTER, true)
	# 키워드 배지
	var tags: Array = []
	if inst != null:
		for kw in ["charge", "poison", "lifesteal"]:
			if inst.has_kw(kw):
				tags.append(CardDB.KEYWORD_NAMES[kw])
		var tx: String = data.get("text", "")
		if tx.begins_with("유언"):
			tags.append("유언")
		elif tx.begins_with("내 턴 종료"):
			tags.append("성장")
	if not tags.is_empty():
		Art.draw_text(self, " ".join(PackedStringArray(tags)), Rect2(4 * k, 108 * k, w - 8 * k, 20 * k), int(13 * k), Art.COL_SEL)
	if taunt:
		Art.draw_text(self, "도발", Rect2(0, h - 44 * k, w, 18 * k), int(13 * k), Color("#e2e8f0"), HORIZONTAL_ALIGNMENT_CENTER, true)
	Art.draw_badge(self, Vector2(22 * k, h - 22 * k), 18 * k, Art.COL_ATK, str(_cur_attack()), _attack_color())
	Art.draw_badge(self, Vector2(w - 22 * k, h - 22 * k), 18 * k, Art.COL_HP, str(_cur_health()), _health_color())
	if inst != null and inst.has_kw("shield"):
		var sb := Art.panel_style(Color(1, 0.85, 0.2, 0.12), Color("#fde047"), int(3 * k), int(18 * k))
		draw_style_box(sb, rect.grow(-2))
	if inst != null:
		if inst.sleeping:
			Art.draw_text(self, "묶임", Rect2(w - 46 * k, 26 * k, 40 * k, 20 * k), int(14 * k), Color("#86efac"), HORIZONTAL_ALIGNMENT_CENTER, true)
		elif inst.summoned_turn and not inst.has_kw("charge"):
			Art.draw_text(self, "Zz", Rect2(w - 40 * k, 26 * k, 34 * k, 20 * k), int(16 * k), Art.COL_SUB, HORIZONTAL_ALIGNMENT_CENTER, true)
	if dim:
		draw_style_box(Art.panel_style(Color(0, 0, 0, 0.35), Color(0, 0, 0, 0), 0, int(14 * k)), rect)


# ── 공용 필드 ──

func _draw_field() -> void:
	var w := size.x
	var h := size.y
	var rect := Rect2(Vector2.ZERO, size)
	_draw_glow(rect, 12)
	_frame(rect, 4, 12)
	_draw_icon(Rect2(8, 22, 56, 56))
	Art.draw_text(self, data.get("name", ""), Rect2(6, 2, w - 12, 22), 15, Art.COL_TEXT, HORIZONTAL_ALIGNMENT_CENTER, true)
	Art.draw_text(self, caption, Rect2(66, 28, w - 72, 22), 14, Art.COL_SEL, HORIZONTAL_ALIGNMENT_LEFT, true)
	Art.draw_text(self, "필드", Rect2(66, 52, w - 72, 20), 13, Art.COL_SUB, HORIZONTAL_ALIGNMENT_LEFT)
	Art.draw_text(self, "눌러서 보기", Rect2(0, h - 24, w, 20), 12, Art.COL_SUB)


# ── 시장 가로줄 ──

func _draw_market() -> void:
	var w := size.x
	var h := size.y
	var rect := Rect2(Vector2.ZERO, size)
	_draw_glow(rect, 10)
	_frame(rect, 3, 10)
	var icon_rect := Rect2(8, 8, h - 16, h - 16)
	draw_style_box(Art.panel_style(Color(0, 0, 0, 0.35), Color(0, 0, 0, 0), 0, 8), icon_rect)
	_draw_icon(icon_rect.grow(-6))
	Art.draw_badge(self, Vector2(18, 18), 14, Art.COL_MANA, str(int(data.get("cost", 0))))
	var x := h + 2.0
	var text_w := w - x - 64
	Art.draw_text(self, data.get("name", ""), Rect2(x, 4, text_w, 28), 21, Art.COL_TEXT, HORIZONTAL_ALIGNMENT_LEFT, true)
	var stats := ""
	if data.get("type", "") == "unit":
		stats = "  %d/%d" % [int(data.get("attack", 0)), int(data.get("health", 0))]
	Art.draw_text(self, type_line() + stats, Rect2(x, 30, text_w, 20), 14, _border_color().lightened(0.2), HORIZONTAL_ALIGNMENT_LEFT)
	var rt := rules_text().replace("\n", " · ")
	if rt != "":
		var f := Art.font()
		var y := 54.0 + f.get_ascent(15)
		draw_multiline_string(f, Vector2(x, y), rt, HORIZONTAL_ALIGNMENT_LEFT, text_w, 15, 2, Art.COL_SUB)
	if price >= 0:
		Art.draw_badge(self, Vector2(w - 34, h / 2.0), 24, Art.COL_GOLD, str(price), Color.BLACK)
	if dim:
		draw_style_box(Art.panel_style(Color(0, 0, 0, 0.45), Color(0, 0, 0, 0), 0, 10), rect)


# ── 함정 ──

func _draw_trap(own: bool) -> void:
	var rect := Rect2(Vector2.ZERO, size)
	var sb := Art.panel_style(Color("#3b2f52") if not own else Art.faction_color(data.get("faction", "neutral")), Color("#a78bfa"), 3, 8)
	draw_style_box(sb, rect)
	if own:
		_draw_icon(Rect2(10, 8, size.x - 20, 40), 0.9)
		Art.draw_text(self, data.get("name", ""), Rect2(2, 50, size.x - 4, 30), 12, Art.COL_TEXT, HORIZONTAL_ALIGNMENT_CENTER, true)
	else:
		Art.draw_text(self, "?", rect, 40, Color("#ddd6fe"), HORIZONTAL_ALIGNMENT_CENTER, true)
